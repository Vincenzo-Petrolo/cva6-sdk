#!/usr/bin/env bash

#==============================================================================
# rssi_ad9361_show.sh — AD9361 RSSI readback via IIO sysfs
#
# Usage: ./rssi_ad9361_show.sh <num_reads>
# Reads the raw in_voltage0_rssi value from the AD9361 IIO device.
#
# Output is the AD9361-provided RSSI readback in dB from RX1. This helper does
# not apply any frequency- or board-dependent calibration offset, so do not
# interpret the printed value as calibrated dBm directly.
# Historical empirical offsets that were used for manual post-processing:
# RSSI(dBm) ~= -r + o
# 2.4GHz(ch 6) FMCOMMS2: o = 16.74
# 2.4GHz(ch 6) FMCOMMS3: o = 17.44
# 5GHz (ch 44) FMCOMMS2: o = 25.41
# 5GHz (ch 44) FMCOMMS3: o = 24.58
#
# Author: Xianjun Jiao
# Author: Andreas T. Kristensen (ZCU104 port)
# SPDX-FileCopyrightText: 2019 UGent
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"
home_dir=$(pwd)

openwifi_cd_iio_device in_voltage0_rssi

if [[ $# -lt 1 ]]; then
  cat in_voltage0_rssi
else
  num_read=$1
  for ((i = 0; i < num_read; i++)); do
    rssi_str=$(cat in_voltage0_rssi)
    echo "$rssi_str" | sed 's/ *dB//'
  done
fi
cd "$home_dir"
