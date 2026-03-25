#!/usr/bin/env bash

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"
home_dir=$(pwd)

openwifi_cd_sdr_sysfs

set -x
# show
cat tx_data_pkt_need_ack_num_total
cat tx_data_pkt_need_ack_num_total_fail
cat tx_data_pkt_need_ack_num_retx
cat tx_data_pkt_need_ack_num_retx_fail

cat tx_data_pkt_mcs_realtime
cat tx_data_pkt_fail_mcs_realtime

cat tx_mgmt_pkt_need_ack_num_total
cat tx_mgmt_pkt_need_ack_num_total_fail
cat tx_mgmt_pkt_need_ack_num_retx
cat tx_mgmt_pkt_need_ack_num_retx_fail

cat tx_mgmt_pkt_mcs_realtime
cat tx_mgmt_pkt_fail_mcs_realtime

# clear
if [[ -n "${1:-}" ]]; then
  echo 0 > tx_data_pkt_need_ack_num_total
  echo 0 > tx_data_pkt_need_ack_num_total_fail
  echo 0 > tx_data_pkt_need_ack_num_retx
  echo 0 > tx_data_pkt_need_ack_num_retx_fail

  echo 0 > tx_data_pkt_mcs_realtime
  echo 0 > tx_data_pkt_fail_mcs_realtime
  
  echo 0 > tx_mgmt_pkt_need_ack_num_total
  echo 0 > tx_mgmt_pkt_need_ack_num_total_fail
  echo 0 > tx_mgmt_pkt_need_ack_num_retx
  echo 0 > tx_mgmt_pkt_need_ack_num_retx_fail

  echo 0 > tx_mgmt_pkt_mcs_realtime
  echo 0 > tx_mgmt_pkt_fail_mcs_realtime
fi
set +x

cd "$home_dir"

