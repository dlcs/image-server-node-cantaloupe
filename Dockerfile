FROM ubuntu:jammy as build

ENV CANTALOUPE_VERSION=5.0.5
ENV OPENJPEG_VERSION=2.5.0
ARG DEBIAN_FRONTEND=noninteractive

# Install various dependencies:
# * ca-certificates is needed by wget
# * wget download stuffs in this dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    unzip

RUN wget -q https://github.com/GrokImageCompression/grok/releases/download/v7.6.5/libgrokj2k1_7.6.5-1_amd64.deb \
    && wget -q https://github.com/GrokImageCompression/grok/releases/download/v7.6.5/grokj2k-tools_7.6.5-1_amd64.deb \
    && wget -q https://github.com/cantaloupe-project/cantaloupe/releases/download/v$CANTALOUPE_VERSION/cantaloupe-$CANTALOUPE_VERSION.zip \
    && unzip cantaloupe-$CANTALOUPE_VERSION.zip \
    && wget -q https://github.com/uclouvain/openjpeg/releases/download/v$OPENJPEG_VERSION/openjpeg-v$OPENJPEG_VERSION-linux-x86_64.tar.gz \
    && tar -xzf openjpeg-v$OPENJPEG_VERSION-linux-x86_64.tar.gz

FROM ubuntu:jammy

ENV CANTALOUPE_VERSION=5.0.5
ENV OPENJPEG_VERSION=2.5.0
ENV JAVA_HOME=/opt/jdk
ENV PATH=$PATH:/opt/jdk/bin:/opt/maven/bin
ARG DEBIAN_FRONTEND=noninteractive

LABEL maintainer="Donald Gray <donald.gray@digirati.com>"
LABEL org.opencontainers.image.source=https://github.com/dlcs/image-server-node-cantaloupe
LABEL org.opencontainers.image.description="Cantaloupe image-server on Ubuntu"

# Install various dependencies:
# * ffmpeg is needed by FfmpegProcessor
# * libopenjp2-tools is needed by OpenJpegProcessor
# * All the rest is needed by GrokProcessor
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libopenjp2-tools \
    liblcms2-dev \
    libpng-dev \
    libzstd-dev \
    libtiff-dev \
    libjpeg-dev \
    zlib1g-dev \
    libwebp-dev \
    libimage-exiftool-perl \
    default-jre-headless \
    awscli \
    && rm -rf /var/lib/apt/lists/*

# Install GrokProcessor deps
COPY --from=build /libgrokj2k1_7.6.5-1_amd64.deb /libgrokj2k1_7.6.5-1_amd64.deb
COPY --from=build /grokj2k-tools_7.6.5-1_amd64.deb /grokj2k-tools_7.6.5-1_amd64.deb
RUN dpkg -i ./libgrokj2k1_7.6.5-1_amd64.deb \
    && dpkg -i --ignore-depends=libjpeg62-turbo ./grokj2k-tools_7.6.5-1_amd64.deb \
    && rm libgrokj2k1_7.6.5-1_amd64.deb \
    && rm grokj2k-tools_7.6.5-1_amd64.deb

# Copy OpenJPEG
COPY --from=build /openjpeg-v$OPENJPEG_VERSION-linux-x86_64/bin/* /bin
COPY --from=build /openjpeg-v$OPENJPEG_VERSION-linux-x86_64/lib/* /lib

# Copy TurboJpegProcessor dependencies + create symlinks
COPY libjpeg /opt/libjpeg-turbo/lib

RUN ln -s /opt/libjpeg-turbo/lib/libjpeg.so.62.3.0 /opt/libjpeg-turbo/lib/libjpeg.so.62 
RUN ln -s /opt/libjpeg-turbo/lib/libjpeg.so.62 /opt/libjpeg-turbo/lib/libjpeg.so

RUN ln -s /opt/libjpeg-turbo/lib/libturbojpeg.so.0.2.0 /opt/libjpeg-turbo/lib/libturbojpeg.so.0
RUN ln -s /opt/libjpeg-turbo/lib/libturbojpeg.so.0 /opt/libjpeg-turbo/lib/libturbojpeg.so

# Add non-root user
RUN adduser --system cantaloupeusr

# Setup Cantaloupe
COPY --from=build /cantaloupe-$CANTALOUPE_VERSION/cantaloupe-$CANTALOUPE_VERSION.jar /cantaloupe/cantaloupe-$CANTALOUPE_VERSION.jar
RUN mkdir -p /var/log/cantaloupe /var/cache/cantaloupe \
    && chown -R cantaloupeusr /cantaloupe /var/log/cantaloupe /var/cache/cantaloupe

# Copy sample properties file
COPY cantaloupe.properties.sample /cantaloupe/cantaloupe.properties.sample

COPY entrypoint/* /opt/app/
RUN chmod +x --recursive /opt/app/

EXPOSE 8182
USER cantaloupeusr
CMD ["sh", "-c", "java -Dcantaloupe.config=/cantaloupe/cantaloupe.properties.sample -jar /cantaloupe/cantaloupe-$CANTALOUPE_VERSION.jar"]