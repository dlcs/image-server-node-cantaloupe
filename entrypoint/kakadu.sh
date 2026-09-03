#!/bin/bash
#
# Deprecated - kept so existing task definitions using
# `command: /opt/app/kakadu.sh` keep working.
#
# The default entrypoint now installs Kakadu whenever KAKADU_LOCATION is set,
# so no command override is needed. Still requires running as root, since the
# Kakadu libraries are copied into /usr/lib.
#
if [[ -z $KAKADU_LOCATION ]]; then
  echo "Need to specify KAKADU_LOCATION envvar"
  exit 125
fi

if [[ -z $KAKADU_VERSION ]]; then
  echo "Need to specify KAKADU_VERSION envvar"
  exit 125
fi

exec /opt/app/entrypoint.sh
