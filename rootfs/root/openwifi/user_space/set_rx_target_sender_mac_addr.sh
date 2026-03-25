#!/usr/bin/env bash

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"
home_dir=$(pwd)

openwifi_cd_sdr_sysfs

set -x
# set
if [[ -n "${1:-}" ]]; then
  echo "$1" > rx_target_sender_mac_addr
fi

# show
cat rx_target_sender_mac_addr
set +x

cd "$home_dir"

