#!/usr/bin/env bash

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"
home_dir=$(pwd)

openwifi_cd_sdr_sysfs

# set
if [[ -n "${1:-}" ]]; then
  echo "$1" > dbg_ch0
fi

# show
cat dbg_ch0

cd "$home_dir"

