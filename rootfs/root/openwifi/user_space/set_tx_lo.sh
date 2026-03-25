#!/usr/bin/env bash

#==============================================================================
# set_tx_lo.sh — TX LO power-down control via AD9361 SPI
#
# Usage: ./set_tx_lo.sh [0|1]
#   0 = power down TX LO, 1 = power up TX LO
#   No argument = show current state
#
# Author: Xianjun Jiao
# SPDX-FileCopyrightText: 2019 UGent
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"

#==============================================================================
# Constants
#==============================================================================
# AD9361 register 0x051: TX Synth Power Down Override (TX LO power-down)
REG_TX_LO_CTRL=0x051
TX_LO_OFF=0x10                      # bit 4 set = TX LO powered down
TX_LO_ON=0x0                        # bits clear = TX LO active

set -x
openwifi_cd_iio_device direct_reg_access
set +x

if [[ "$#" -eq 1 ]]; then
  if [[ "$1" == "0" ]]; then
    echo "$REG_TX_LO_CTRL" "$TX_LO_OFF" > direct_reg_access
    status=$( cat direct_reg_access )
    if [[ "$status" == "$TX_LO_OFF" ]]; then
      echo "Tx LO turned off"
    else
      echo "WARNING: turning Tx LO off unsuccessful" >&2
    fi
  elif [[ "$1" == "1" ]]; then
    echo "$REG_TX_LO_CTRL" "$TX_LO_ON" > direct_reg_access
    status=$( cat direct_reg_access )
    if [[ "$status" == "$TX_LO_ON" ]]; then
      echo "Tx LO turned on"
    else
      echo "WARNING: turning Tx LO on unsuccessful" >&2
    fi
  else
    echo "ERROR: argument must be 0 (off) or 1 (on)" >&2
    exit 1
  fi
elif [[ "$#" -eq 0 ]]; then
  echo "Reading status only. Enter 1 or 0 as argument to set Tx LO on or off."
  echo "$REG_TX_LO_CTRL" > direct_reg_access
  status=$( cat direct_reg_access )
  if [[ "$status" == "$TX_LO_OFF" ]]; then
    echo "Tx LO is off"
  elif [[ "$status" == "$TX_LO_ON" ]]; then
    echo "Tx LO is on"
  else
    echo "WARNING Unrecognized value $status." >&2
  fi
else
  echo "Too many arguments, specify only one for turning on (1) or off (0) the Tx LO." >&2
  exit 1
fi
