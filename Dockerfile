FROM registry.access.redhat.com/ubi8/ubi:latest AS jpegturbo-build

RUN yum module install -y llvm-toolset && yum install -y git cmake java-21-openjdk-devel
ENV JAVA_HOME=/usr/lib/jvm/jre-21-openjdk

ARG jpegturbo_commitish="3.0.3"
RUN git clone -b "${jpegturbo_commitish}" https://github.com/libjpeg-turbo/libjpeg-turbo.git /work && \
    mkdir /work/build /opt/turbojpeg

RUN cmake -DCMAKE_INSTALL_PREFIX=/opt/turbojpeg -DWITH_JAVA=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo -B /work/build -S /work && \
    cmake --build /work/build -t install

FROM registry.access.redhat.com/ubi8/ubi:latest AS openjpeg-build

RUN yum module install -y llvm-toolset && yum install -y git cmake

ARG openjpeg_commitish="v2.5.2"
RUN git clone -b "${openjpeg_commitish}" https://github.com/uclouvain/openjpeg/ /work && \
    mkdir /work/build /opt/openjpeg

RUN cmake -DCMAKE_INSTALL_PREFIX=/opt/openjpeg -DCMAKE_BUILD_TYPE=RelWithDebInfo -B /work/build -S /work && \
    cmake --build /work/build -t install

FROM registry.access.redhat.com/ubi8/ubi:latest AS cantaloupe-build

RUN yum install -y git java-21-openjdk-devel java-21-openjdk-headless maven

ARG cantaloupe_commitish="v5.0.6"
RUN git clone -b "${cantaloupe_commitish}" https://github.com/cantaloupe-project/cantaloupe /work

WORKDIR /work
ENV JAVA_HOME=/usr/lib/jvm/jre-21-openjdk
RUN --mount=type=cache,target=/root/.m2 mvn dependency:go-offline
COPY --from=jpegturbo-build /work/java /work/src/main/java
RUN --mount=type=cache,target=/root/.m2 mvn package -DskipTests

FROM registry.access.redhat.com/ubi8/ubi

LABEL org.opencontainers.image.source=https://github.com/dlcs/image-server-node-cantaloupe
LABEL org.opencontainers.image.description="Cantaloupe image-server on RedHat"

ENV OPENJPEGPROCESSOR_PATH_TO_BINARIES=/opt/openjpeg/bin
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/openjpeg/lib64

RUN yum install -y java-21-openjdk-devel
RUN dnf -y install python3.12 python3.12-pip

COPY --from=openjpeg-build /opt/openjpeg /opt/openjpeg
COPY --from=jpegturbo-build /opt/turbojpeg /opt/turbojpeg

RUN mkdir /opt/cantaloupe
COPY --from=cantaloupe-build /work/target/cantaloupe-*.jar /opt/cantaloupe/cantaloupe.jar

COPY cantaloupe.properties.sample /opt/cantaloupe/cantaloupe.properties.sample
COPY delegates.rb /opt/cantaloupe/delegates.rb

COPY config/requirements.txt /opt/app/
RUN /usr/bin/pip3.12 install --no-warn-script-location --requirement /opt/app/requirements.txt

COPY entrypoint/* /opt/app/
RUN find . -name "*.sh" -exec chmod +x {} \;

COPY config/* /opt/app/

EXPOSE 8182
CMD [ "java", "-Dcantaloupe.config=/opt/cantaloupe/cantaloupe.properties.sample", "-Djava.library.path=/opt/openjpeg/lib64:/opt/turbojpeg/lib64", "-jar", "/opt/cantaloupe/cantaloupe.jar"]