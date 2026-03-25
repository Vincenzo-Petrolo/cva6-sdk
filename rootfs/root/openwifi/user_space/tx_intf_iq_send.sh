#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"

home_dir=$(pwd)

set -x
openwifi_cd_sdr_sysfs

echo 1 > tx_intf_iq_ctl
cat tx_intf_iq_ctl

cd "$home_dir"
