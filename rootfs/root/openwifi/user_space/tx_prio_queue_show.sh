#!/usr/bin/env bash

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"
home_dir=$(pwd)

openwifi_cd_sdr_sysfs

set -x
# show
cat tx_prio_queue

# clear
if [[ -n "${1:-}" ]]; then
  echo 0 > tx_prio_queue
fi
set +x

cd "$home_dir"

