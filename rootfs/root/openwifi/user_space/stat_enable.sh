#!/usr/bin/env bash

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"
home_dir=$(pwd)

openwifi_cd_sdr_sysfs

# set
if [[ -n "${1:-}" ]]; then
  echo "$1" > stat_enable
else
  echo 1 > stat_enable
fi

# show
cat stat_enable

cd "$home_dir"
