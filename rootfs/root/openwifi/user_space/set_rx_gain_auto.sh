#!/usr/bin/env bash

#==============================================================================
# set_rx_gain_auto.sh — AD9361 AGC fast_attack mode + register activation
#
# Usage: ./set_rx_gain_auto.sh
#
# Author: Xianjun Jiao
# SPDX-FileCopyrightText: 2019 UGent
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"
home_dir=$(pwd)

# AD9361 AGC control register (activate sequence)
REG_AGC_CTRL=0x0fa
AGC_ACTIVATE_STEP1=0x5
AGC_ACTIVATE_STEP2=0xE5

set -x
# Set gain control mode (bus sysfs)
openwifi_cd_iio_device in_voltage_rf_bandwidth

echo fast_attack > in_voltage0_gain_control_mode
cat in_voltage0_gain_control_mode
cat in_voltage0_hardwaregain

# Apply AGC register settings (debugfs)
openwifi_cd_iio_device direct_reg_access

echo "$REG_AGC_CTRL" "$AGC_ACTIVATE_STEP1" > direct_reg_access
echo "$REG_AGC_CTRL" "$AGC_ACTIVATE_STEP2" > direct_reg_access

cd "$home_dir"

set +x
