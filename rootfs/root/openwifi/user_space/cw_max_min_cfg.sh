#!/usr/bin/env bash

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"
home_dir=$(pwd)

openwifi_cd_sdr_sysfs

set -x
#set
if [[ -n "${1:-}" ]]; then
  echo "$1" > cw_max_min_cfg
fi

# show
cat cw_max_min_cfg
set +x

cd "$home_dir"
