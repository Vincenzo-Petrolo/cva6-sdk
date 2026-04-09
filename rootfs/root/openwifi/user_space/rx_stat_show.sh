#!/usr/bin/env bash

#==============================================================================
# rx_stat_show.sh — RX packet statistics display + PER calculation
#
# Usage: ./rx_stat_show.sh [clear | num_total]
#   No argument  = show stats only
#   Non-numeric  = show stats then clear all counters
#   Numeric (>0) = show stats then compute PER against that target total
#
# Author: Andreas T. Kristensen (ZCU104 port)
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"

home_dir=$(pwd)

openwifi_cd_sdr_sysfs

set -x
# show
cat rx_data_pkt_num_total
cat rx_data_pkt_num_fail
cat rx_mgmt_pkt_num_total
cat rx_mgmt_pkt_num_fail
cat rx_ack_pkt_num_total
cat rx_ack_pkt_num_fail

cat rx_data_pkt_mcs_realtime
cat rx_data_pkt_fail_mcs_realtime
cat rx_mgmt_pkt_mcs_realtime
cat rx_mgmt_pkt_fail_mcs_realtime
cat rx_ack_pkt_mcs_realtime

cat rx_data_ok_agc_gain_value_realtime
cat rx_data_fail_agc_gain_value_realtime
cat rx_mgmt_ok_agc_gain_value_realtime
cat rx_mgmt_fail_agc_gain_value_realtime
cat rx_ack_ok_agc_gain_value_realtime

# clear — pass any non-numeric arg to clear, or a number for PER calculation
if [[ -n "${1:-}" ]]; then
  case "$1" in
    *[!0-9]*)
      # not a number — clear counters
      echo 0 > rx_data_pkt_num_total
      echo 0 > rx_data_pkt_num_fail
      echo 0 > rx_mgmt_pkt_num_total
      echo 0 > rx_mgmt_pkt_num_fail
      echo 0 > rx_ack_pkt_num_total
      echo 0 > rx_ack_pkt_num_fail

      echo 0 > rx_data_pkt_mcs_realtime
      echo 0 > rx_data_pkt_fail_mcs_realtime
      echo 0 > rx_mgmt_pkt_mcs_realtime
      echo 0 > rx_mgmt_pkt_fail_mcs_realtime
      echo 0 > rx_ack_pkt_mcs_realtime

      echo 0 > rx_data_ok_agc_gain_value_realtime
      echo 0 > rx_data_fail_agc_gain_value_realtime
      echo 0 > rx_mgmt_ok_agc_gain_value_realtime
      echo 0 > rx_mgmt_fail_agc_gain_value_realtime
      echo 0 > rx_ack_ok_agc_gain_value_realtime
      ;;
    *)
      # is a number — target total for PER calculation
      num_received=$(cat rx_data_pkt_num_total)
      num_failed=$(cat rx_data_pkt_num_fail)
      num_correct=$((num_received - num_failed))
      num_total=$(($1))
      if [[ "$num_total" -eq 0 ]]; then
        echo "ERROR: target total must be > 0" >&2
        exit 1
      fi
      PER_ENLARGE_FACTOR=10000
      num_correct_scale=$((num_correct * PER_ENLARGE_FACTOR))
      PCR=$((num_correct_scale / num_total))
      PER=$((PER_ENLARGE_FACTOR - PCR))
      echo "PCR $PCR / $PER_ENLARGE_FACTOR"
      echo "PER $PER / $PER_ENLARGE_FACTOR"
      ;;
  esac
fi
set +x

cd "$home_dir"
