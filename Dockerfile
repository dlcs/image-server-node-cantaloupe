FROM ubuntu:jammy as build

ENV CANTALOUPE_VERSION=5.0.6
ENV OPENJPEG_VERSION=2.5.2
ENV GROK_VERSION=13.0.0
ARG DEBIAN_FRONTEND=noninteractive

# Install various dependencies:
# * ca-certificates is needed by wget
# * wget download stuffs in this dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    unzip

RUN wget -q https://github.com/cantaloupe-project/cantaloupe/releases/download/v$CANTALOUPE_VERSION/cantaloupe-$CANTALOUPE_VERSION.zip \
    && unzip cantaloupe-$CANTALOUPE_VERSION.zip \
    && wget -q https://github.com/uclouvain/openjpeg/releases/download/v$OPENJPEG_VERSION/openjpeg-v$OPENJPEG_VERSION-linux-x86_64.tar.gz \
    && tar -xzf openjpeg-v$OPENJPEG_VERSION-linux-x86_64.tar.gz \
    && wget -q https://github.com/GrokImageCompression/grok/releases/download/v$GROK_VERSION/grok-ubuntu-latest.zip \
    && unzip grok-ubuntu-latest.zip \
    && wget -q https://download.java.net/java/GA/jdk18/43f95e8614114aeaa8e8a5fcf20a682d/36/GPL/openjdk-18_linux-x64_bin.tar.gz \
    && tar xfz openjdk-18_linux-x64_bin.tar.gz

FROM ubuntu:jammy

ENV CANTALOUPE_VERSION=5.0.6
ENV OPENJPEG_VERSION=2.5.2
ENV JAVA_HOME=/opt/jdk
ENV PATH=$PATH:/opt/jdk/bin:/opt/maven/bin
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/lib
ENV MAXHEAP=2g
ENV INITHEAP=256m
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

# Copy JDK + latest Maven
COPY --from=build /jdk-18 /opt/jdk

# Copy GrokProcessor
COPY --from=build /grok-ubuntu-latest/bin/* /bin
COPY --from=build /grok-ubuntu-latest/lib/* /lib
COPY --from=build /grok-ubuntu-latest/include/grok-13.0/* /usr/lib

# Copy OpenJPEG
COPY --from=build /openjpeg-v$OPENJPEG_VERSION-linux-x86_64/bin/* /bin
COPY --from=build /openjpeg-v$OPENJPEG_VERSION-linux-x86_64/lib/* /lib
COPY --from=build /openjpeg-v$OPENJPEG_VERSION-linux-x86_64/include/openjpeg-2.5/* /usr/lib/

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

# Copy sample properties file + delegates
COPY cantaloupe.properties.sample /cantaloupe/cantaloupe.properties.sample
COPY delegates.rb /cantaloupe/delegates.rb

COPY entrypoint/* /opt/app/
RUN chmod +x --recursive /opt/app/

EXPOSE 8182
USER cantaloupeusr
CMD ["sh", "-c", "java -Dcantaloupe.config=/cantaloupe/cantaloupe.properties.sample -Xmx$MAXHEAP -Xms$INITHEAP -jar /cantaloupe/cantaloupe-$CANTALOUPE_VERSION.jar"]