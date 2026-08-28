#!/bin/bash
#
# Single launch path for the image. Optional steps run only when the matching
# envvar is set, so the same entrypoint covers every deployment:
#
#   (nothing set)         -> bundled cantaloupe.properties.sample
#   PROPERTIES_LOCATION   -> properties file pulled from S3
#   KAKADU_LOCATION       -> Kakadu binaries pulled from S3 and installed
#                            (requires root - copies into /usr/lib)
#
# JVM flags: -Xms/-Xmx come from INITHEAP/MAXHEAP. Set either to an empty string
# to omit that flag entirely, e.g. to hand sizing to the JVM instead:
#   MAXHEAP= INITHEAP= JAVA_OPTS=-XX:MaxRAMPercentage=75
#
set -euo pipefail

CONFIG=/cantaloupe/cantaloupe.properties.sample

if [[ -n ${KAKADU_LOCATION:-} ]]; then
  if [[ -z ${KAKADU_VERSION:-} ]]; then
    echo "KAKADU_LOCATION is set but KAKADU_VERSION is not"
    exit 125
  fi

  echo "Copying Kakadu $KAKADU_VERSION from S3 ..."
  mkdir -p /opt/kakadu
  aws s3 cp "$KAKADU_LOCATION" /opt/kakadu/kakadu.tar.gz

  echo "Extracting Kakadu ..."
  tar -xzf /opt/kakadu/kakadu.tar.gz -C /opt/kakadu

  echo "Configuring Kakadu ..."
  cp -r /opt/kakadu/java/kdu_jni/* /usr/lib
  cp -r "/opt/kakadu/kakadu-$KAKADU_VERSION/lib/Linux-x86-64-gcc/"* /usr/lib
fi

if [[ -n ${PROPERTIES_LOCATION:-} ]]; then
  echo "Copying properties file from S3 ..."
  aws s3 cp "$PROPERTIES_LOCATION" /cantaloupe/cantaloupe.properties
  CONFIG=/cantaloupe/cantaloupe.properties
fi

HEAP_OPTS=()
if [[ -n ${INITHEAP:-} ]]; then
  HEAP_OPTS+=("-Xms$INITHEAP")
fi
if [[ -n ${MAXHEAP:-} ]]; then
  HEAP_OPTS+=("-Xmx$MAXHEAP")
fi

echo "Starting Cantaloupe with config $CONFIG ..."
exec java \
  -Dcantaloupe.config="$CONFIG" \
  "${HEAP_OPTS[@]}" \
  ${JAVA_OPTS:-} \
  -jar /cantaloupe/cantaloupe.jar
