#!/usr/bin/env bash

#==============================================================================
# set_tx_port.sh — TX port A/B routing via AD9361 SPI
#
# Usage: ./set_tx_port.sh [0|1]
#   0 = port B, 1 = port A
#   No argument = show current state
#
# Author: Xianjun Jiao
# Author: Andreas T. Kristensen (ZCU104 port)
# SPDX-FileCopyrightText: 2019 UGent
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"

#==============================================================================
# Constants
#==============================================================================
# AD9361 register 0x004: Input Select (TX/RX port routing)
REG_TX_PORT_CTRL=0x004
TX_PORT_B=0x43                      # select TX port B (SMA connector B)
TX_PORT_A=0x3                       # select TX port A (SMA connector A)

set -x
openwifi_cd_iio_device direct_reg_access
set +x

if [[ "$#" -eq 1 ]]; then
  if [[ "$1" == "0" ]]; then
    echo "$REG_TX_PORT_CTRL" "$TX_PORT_B" > direct_reg_access
    status=$( cat direct_reg_access )
    if [[ "$status" == "$TX_PORT_B" ]]; then
      echo "Tx port B selected."
    else
      echo "WARNING: switching Tx port B unsuccessful" >&2
    fi
  elif [[ "$1" == "1" ]]; then
    echo "$REG_TX_PORT_CTRL" "$TX_PORT_A" > direct_reg_access
    status=$( cat direct_reg_access )
    if [[ "$status" == "$TX_PORT_A" ]]; then
      echo "Tx port A selected."
    else
      echo "WARNING: switching Tx port A unsuccessful" >&2
    fi
  else
    echo "ERROR: argument must be 0 (port B) or 1 (port A)" >&2
    exit 1
  fi
elif [[ "$#" -eq 0 ]]; then
  echo "Reading status only. Enter 1 or 0 as argument to select port A or B."
  echo "$REG_TX_PORT_CTRL" > direct_reg_access
  status=$( cat direct_reg_access )
  if [[ "$status" == "$TX_PORT_B" ]]; then
    echo "Tx port B is used"
  elif [[ "$status" == "$TX_PORT_A" ]]; then
    echo "Tx port A is used"
  else
    echo "WARNING Unrecognized value $status." >&2
  fi
else
  echo "Too many arguments, specify only one for selecting port A (1) or B (0)." >&2
  exit 1
fi
