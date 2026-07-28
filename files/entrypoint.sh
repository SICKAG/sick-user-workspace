#!/bin/bash
set -e

WELCOME="/etc/profile.d/welcome.sh"

if [ -t 0 ]; then
  [ -f "$WELCOME" ] && . "$WELCOME"
  exec "$@"
else
  tail -f /dev/null
fi