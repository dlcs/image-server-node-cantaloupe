FROM registry.access.redhat.com/ubi8/ubi:latest AS openjpeg-build

RUN yum module install -y llvm-toolset && yum install -y git cmake
RUN git clone https://github.com/uclouvain/openjpeg/ /work && \
    mkdir /work/build /opt/openjpeg

RUN cmake -DCMAKE_INSTALL_PREFIX=/opt/openjpeg -DCMAKE_BUILD_TYPE=RelWithDebInfo -B /work/build -S /work && \
    cmake --build /work/build -t install

FROM registry.access.redhat.com/ubi8/ubi:latest AS cantaloupe-build
RUN yum install -y git java-21-openjdk-devel java-21-openjdk-headless maven
RUN git clone https://github.com/cantaloupe-project/cantaloupe /work
WORKDIR /work
ENV JAVA_HOME=/usr/lib/jvm/jre-21-openjdk
RUN mvn dependency:resolve
RUN mvn clean package -DskipTests

FROM registry.access.redhat.com/ubi8/openjdk-21-runtime
COPY --from=openjpeg-build /opt/openjpeg /opt/openjpeg
RUN mkdir /opt/cantaloupe
COPY --from=cantaloupe-build /work/target/cantaloupe-*.jar /opt/cantaloupe/cantaloupe.jar
COPY cantaloupe.properties.sample /opt/cantaloupe/cantaloupe.properties.sample
EXPOSE 8182
CMD ["java",  "-Dcantaloupe.config=/opt/cantaloupe/cantaloupe.properties.sample",  "-jar", "/opt/cantaloupe/cantaloupe.jar"]