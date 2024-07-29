#! /bin/bash

if [[ -z $KAKADU_LOCATION ]]; then
  echo "Need to specify KAKADU_LOCATION envvar"
  exit 125
fi

if [[ -z $KAKADU_VERSION ]]; then
  echo "Need to specify KAKADU_VERSION envvar"
  exit 125
fi

echo "Copying Kakadu $KAKADU_VERSION from S3 ..."
mkdir /opt/kakadu/
python3.12 /opt/app/s3_download.py $KAKADU_LOCATION /opt/kakadu/kakadu.tar.gz

echo "Extracting Kakadu ..."
cd /opt/kakadu/ && tar -xvzf kakadu.tar.gz

if [[ ! -z $PROPERTIES_LOCATION ]]; then
  echo "Copying properties files from S3 ..."
  python3.12 /opt/app/s3_download.py $PROPERTIES_LOCATION /opt/cantaloupe/cantaloupe.properties
fi

java -Dcantaloupe.config=/opt/cantaloupe/cantaloupe.properties -Djava.library.path=/opt/openjpeg/lib64:/opt/turbojpeg/lib64:/opt/kakadu/java/kdu_jni:/opt/kakadu/kakadu-$KAKADU_VERSION/lib/Linux-x86-64-gcc/ -jar /opt/cantaloupe/cantaloupe.jar