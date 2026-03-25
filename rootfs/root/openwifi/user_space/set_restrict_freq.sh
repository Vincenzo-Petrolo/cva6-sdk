#!/usr/bin/env bash

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"
home_dir=$(pwd)

openwifi_cd_sdr_sysfs

# set
if [[ -n "${1:-}" ]]; then
  echo "$1" > restrict_freq_mhz
fi

# show
cat restrict_freq_mhz

cd "$home_dir"

