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
aws s3 cp $KAKADU_LOCATION /opt/kakadu/kakadu.tar.gz

echo "Extracting Kakadu ..."
cd /opt/kakadu/ && tar -xvzf kakadu.tar.gz

echo "Configuring Kakadu ..."
cp /opt/kakadu/java/kdu_jni/* /usr/lib -r
cp /opt/kakadu/kakadu-$KAKADU_VERSION/lib/Linux-x86-64-gcc/* /usr/lib -r

bash /opt/app/s3-config.sh