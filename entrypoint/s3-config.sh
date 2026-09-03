#!/bin/bash
#
# Deprecated - kept so existing task definitions using
# `command: /opt/app/s3-config.sh` keep working.
#
# The default entrypoint now pulls the properties file from S3 whenever
# PROPERTIES_LOCATION is set, so no command override is needed.
#
if [[ -z $PROPERTIES_LOCATION ]]; then
  echo "Need to specify PROPERTIES_LOCATION envvar"
  exit 125
fi

exec /opt/app/entrypoint.sh
