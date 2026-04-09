#!/usr/bin/env bash

#==============================================================================
# agc_settings.sh — AD9361 AGC register configuration (default vs optimized)
#
# Usage: ./agc_settings.sh <0|1>
#   0 = default AGC, 1 = optimized AGC
#
# Author: Xianjun Jiao
# Author: Andreas T. Kristensen (ZCU104 port)
# SPDX-FileCopyrightText: 2019 UGent
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"
if [[ "$#" -ne 1 ]]; then
    echo "You must enter 1 to apply new settings or 0 to restore default settings" >&2
    exit 1
fi

#==============================================================================
# Constants
#==============================================================================

# AD9361 AGC register addresses (SPI map)
REG_AGC_LARGE_OVL_THRESH=0x15C      # ADC large-overload threshold
REG_AGC_LARGE_OVL_EXCEED_CNT=0x106  # large-overload exceed counter
REG_AGC_OUTER_THRESH_HIGH=0x103     # outer threshold high
REG_AGC_OUTER_THRESH_LOW=0x101      # outer threshold low
REG_AGC_GAIN_UPDATE_CTR=0x110       # gain update counter
                                    # DO NOT use 0x4A — breaks auth response
REG_AGC_SETTLED_LOW=0x114           # AGC settled low threshold
REG_AGC_LARGE_LMT_OVL_CNT=0x115    # large LMT overload count
REG_AGC_ATTACK_DELAY=0x10A          # attack/decay timing
REG_AGC_CTRL=0x0fa                  # AGC control (activate sequence)
AGC_ACTIVATE_STEP1=0x5              # two-write activation: step 1
AGC_ACTIVATE_STEP2=0xE5             # two-write activation: step 2

openwifi_cd_iio_device direct_reg_access

set -x
if [[ "$1" == "0" ]]; then
  echo "$REG_AGC_LARGE_OVL_THRESH"      0x72 > direct_reg_access
  echo "$REG_AGC_LARGE_OVL_EXCEED_CNT"  0x72 > direct_reg_access
  echo "$REG_AGC_OUTER_THRESH_HIGH"     0x08 > direct_reg_access
  echo "$REG_AGC_OUTER_THRESH_LOW"      0x0A > direct_reg_access
  echo "$REG_AGC_GAIN_UPDATE_CTR"       0x40 > direct_reg_access
  echo "$REG_AGC_SETTLED_LOW"           0x30 > direct_reg_access
  echo "$REG_AGC_LARGE_LMT_OVL_CNT"    0x00 > direct_reg_access
  echo "$REG_AGC_ATTACK_DELAY"          0x58 > direct_reg_access
  echo "Applied default AGC settings"
elif [[ "$1" == "1" ]]; then
  echo "$REG_AGC_LARGE_OVL_THRESH"      0x70 > direct_reg_access
  echo "$REG_AGC_LARGE_OVL_EXCEED_CNT"  0x77 > direct_reg_access
  echo "$REG_AGC_OUTER_THRESH_HIGH"     0x1C > direct_reg_access
  echo "$REG_AGC_OUTER_THRESH_LOW"      0x0C > direct_reg_access
  echo "$REG_AGC_GAIN_UPDATE_CTR"       0x48 > direct_reg_access
  # DO NOT change 0x48 to 0x4A! Otherwise: did not acknowledge authentication response
  echo "$REG_AGC_SETTLED_LOW"           0xb0 > direct_reg_access
  # 0x30 is the original value for REG_AGC_SETTLED_LOW
  echo "$REG_AGC_LARGE_LMT_OVL_CNT"    0x80 > direct_reg_access
  echo "$REG_AGC_ATTACK_DELAY"          0x18 > direct_reg_access
  echo "Applied optimized AGC settings"
else
  echo "ERROR: argument must be 0 (default) or 1 (optimized)" >&2
  exit 1
fi

# AGC activation sequence (https://github.ugent.be/xjiao/openwifi/issues/148)
echo "$REG_AGC_CTRL" "$AGC_ACTIVATE_STEP1" > direct_reg_access
echo "$REG_AGC_CTRL" "$AGC_ACTIVATE_STEP2" > direct_reg_access
set +x
