ARG CANTALOUPE_VERSION=5.0.7
ARG OPENJPEG_VERSION=2.5.4
ARG GROK_VERSION=20.4.0

FROM ubuntu:noble AS build
ARG CANTALOUPE_VERSION
ARG OPENJPEG_VERSION
ARG GROK_VERSION
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip

WORKDIR /dist
RUN curl -fsSLO https://github.com/cantaloupe-project/cantaloupe/releases/download/v$CANTALOUPE_VERSION/cantaloupe-$CANTALOUPE_VERSION.zip \
    && unzip -q cantaloupe-$CANTALOUPE_VERSION.zip \
    && cp cantaloupe-$CANTALOUPE_VERSION/cantaloupe-$CANTALOUPE_VERSION.jar /dist/cantaloupe.jar \
    && curl -fsSLO https://github.com/uclouvain/openjpeg/releases/download/v$OPENJPEG_VERSION/openjpeg-v$OPENJPEG_VERSION-linux-x86_64.tar.gz \
    && tar -xzf openjpeg-v$OPENJPEG_VERSION-linux-x86_64.tar.gz \
    && mv openjpeg-v$OPENJPEG_VERSION-linux-x86_64 /dist/openjpeg \
    && curl -fsSLO https://github.com/GrokImageCompression/grok/releases/download/v$GROK_VERSION/grok-ubuntu-latest.zip \
    && unzip -q grok-ubuntu-latest.zip \
    && mv grok-ubuntu-latest /dist/grok

# Drop build byproducts the release bundles ship alongside the tools: static
# archives, cmake/pkgconfig metadata, a python module dir, and - in Grok's case -
# an unreleased dev build of curl that would otherwise land on PATH. Pruned here
# rather than with globbed COPYs, because a glob dereferences the .so symlinks
# and bloats the image with duplicate copies of each library.
RUN rm -rf /dist/grok/lib/cmake /dist/grok/lib/pkgconfig /dist/grok/lib/python3.14 \
    && rm -rf /dist/openjpeg/lib/cmake /dist/openjpeg/lib/pkgconfig \
    && rm -f /dist/grok/lib/*.a /dist/openjpeg/lib/*.a \
    && rm -f /dist/grok/bin/curl /dist/grok/bin/curl-config /dist/grok/bin/mk-ca-bundle.pl

# AWS CLI v2 - the `awscli` apt package has no installation candidate on noble
RUN curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip \
    && unzip -q awscliv2.zip \
    && ./aws/install -i /opt/aws-cli -b /dist/aws-bin

FROM ubuntu:noble
ARG CANTALOUPE_VERSION
ARG DEBIAN_FRONTEND=noninteractive

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV PATH=${JAVA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/lib
ENV MAXHEAP=2g
ENV INITHEAP=256m
# Extra JVM flags, appended after -Xms/-Xmx. See entrypoint/entrypoint.sh.
ENV JAVA_OPTS=
ENV HOME=/home/cantaloupe

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    ffmpeg \
    liblcms2-2 \
    libpng16-16 \
    libzstd1 \
    libtiff6 \
    zlib1g \
    libwebp7 \
    libimage-exiftool-perl \
    libpsl5t64 \
    libturbojpeg \
    openjdk-21-jre-headless \
    adduser \
    && rm -rf /var/lib/apt/lists/*

# Whole directories, so the .so version symlinks are preserved rather than
# dereferenced into duplicate files. They were pruned in the build stage above.
COPY --from=build /dist/grok/bin/ /usr/local/bin/
COPY --from=build /dist/grok/lib/ /usr/local/lib/
COPY --from=build /dist/openjpeg/bin/ /usr/local/bin/
COPY --from=build /dist/openjpeg/lib/ /usr/local/lib/
COPY --from=build /opt/aws-cli /opt/aws-cli
COPY --from=build /dist/aws-bin/ /usr/local/bin/

# Cantaloupe bundles the TurboJPEG Java binding but not the native lib, and its
# TJLoader hardcodes this path. Symlink Ubuntu's packaged lib into place
RUN mkdir -p /opt/libjpeg-turbo/lib \
    && ln -s /usr/lib/x86_64-linux-gnu/libturbojpeg.so.0 /opt/libjpeg-turbo/lib/libturbojpeg.so

RUN adduser --system --home /home/cantaloupe --group cantaloupe

COPY --from=build /dist/cantaloupe.jar /cantaloupe/cantaloupe.jar
COPY cantaloupe.properties.sample /cantaloupe/cantaloupe.properties.sample
COPY delegates.rb /cantaloupe/delegates.rb
COPY --chmod=755 entrypoint/ /opt/app/

RUN mkdir -p /var/log/cantaloupe /var/cache/cantaloupe /home/cantaloupe/images \
    && chown -R cantaloupe:cantaloupe /cantaloupe /var/log/cantaloupe /var/cache/cantaloupe /home/cantaloupe

LABEL maintainer="Donald Gray <donald.gray@digirati.com>"
LABEL org.opencontainers.image.source=https://github.com/dlcs/image-server-node-cantaloupe
LABEL org.opencontainers.image.description="Cantaloupe image-server on Ubuntu"
LABEL org.opencontainers.image.version=$CANTALOUPE_VERSION

EXPOSE 8182
USER cantaloupe
CMD ["/opt/app/entrypoint.sh"]
