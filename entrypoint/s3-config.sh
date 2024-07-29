#! /bin/bash

if [[ -z $PROPERTIES_LOCATION ]]; then
  echo "Need to specify PROPERTIES_LOCATION envvar"
  exit 125
fi

echo "Copying properties files from S3 ..."
python3.12 /opt/app/s3_download.py $PROPERTIES_LOCATION /opt/cantaloupe/cantaloupe.properties

java -Dcantaloupe.config=/opt/cantaloupe/cantaloupe.properties -Djava.library.path=/opt/openjpeg/lib64:/opt/turbojpeg/lib64 -jar /opt/cantaloupe/cantaloupe.jar