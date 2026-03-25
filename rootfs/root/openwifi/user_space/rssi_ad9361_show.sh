#!/usr/bin/env bash

#==============================================================================
# rssi_ad9361_show.sh — AD9361 RSSI readback via IIO sysfs
#
# Usage: ./rssi_ad9361_show.sh <num_reads>
# Reads in_voltage0_rssi from AD9361 IIO device and applies calibration offset.
#
# Reads RSSI in dB from RX1, let's call it "r".
# Linear fit offset "o" depends on frequency (2.4GHz or 5GHz and FMCOMMS2/3).
# RSSI(dBm) = -r + o
# 2.4GHz(ch 6) FMCOMMS2: o = 16.74
# 2.4GHz(ch 6) FMCOMMS3: o = 17.44
# 5GHz (ch 44) FMCOMMS2: o = 25.41
# 5GHz (ch 44) FMCOMMS3: o = 24.58
#
# Author: Xianjun Jiao
# SPDX-FileCopyrightText: 2019 UGent
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
