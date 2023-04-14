#! /bin/bash

if [[ -z $PROPERTIES_LOCATION ]]; then
  echo "Need to specify PROPERTIES_LOCATION envvar"
  exit 125
fi

echo "Copying properties files from S3 ..."
aws s3 cp $PROPERTIES_LOCATION /cantaloupe/cantaloupe.properties

java -Dcantaloupe.config=/cantaloupe/cantaloupe.properties -Xmx$MAXHEAP -Xms$INITHEAP -jar /cantaloupe/cantaloupe-$CANTALOUPE_VERSION.jar