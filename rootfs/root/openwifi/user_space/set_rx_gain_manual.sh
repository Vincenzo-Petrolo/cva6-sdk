#!/usr/bin/env bash

#==============================================================================
# set_rx_gain_manual.sh — AD9361 manual RX gain control
#
# Usage: ./set_rx_gain_manual.sh [gain_value]
#
# Author: Xianjun Jiao
# Author: Andreas T. Kristensen (ZCU104 port)
# SPDX-FileCopyrightText: 2019 UGent
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"

gain_dB="${1:-0}"

home_dir=$(pwd)

set -x
openwifi_cd_iio_device in_voltage_rf_bandwidth

echo manual > in_voltage0_gain_control_mode
cat in_voltage0_gain_control_mode

if [[ $# -ge 1 ]]; then
  echo "$gain_dB" > in_voltage0_hardwaregain
fi

cat in_voltage0_hardwaregain

cd "$home_dir"

set +x
