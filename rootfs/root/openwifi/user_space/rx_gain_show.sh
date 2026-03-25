#!/usr/bin/env bash

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"
home_dir=$(pwd)

openwifi_cd_sdr_sysfs

set -x
cat rx_data_ok_agc_gain_value_realtime
cat rx_data_fail_agc_gain_value_realtime
cat rx_mgmt_ok_agc_gain_value_realtime
cat rx_mgmt_fail_agc_gain_value_realtime
cat rx_ack_ok_agc_gain_value_realtime
set +x

cd "$home_dir"

