#!/usr/bin/env bash

#==============================================================================
# csi_fuzzer.sh — CSI fuzzer coefficient writer (tx_intf register 5 bit layout)
#
# Usage: ./csi_fuzzer.sh <c1_rot90> <c1_coeff> <c2_rot90> <c2_coeff>
#
# Author: Xianjun Jiao
# Author: Andreas T. Kristensen (ZCU104 port)
# SPDX-FileCopyrightText: 2019 UGent
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"

if [[ "$#" -lt 4 ]]; then
    echo "You must enter 4 arguments: c1_rot90_en c1_raw(-64 to 63) c2_rot90_en c2_raw(-64 to 63)" >&2
    exit 1
fi

c1_rot90_en=$1
c1_raw=$2
c2_rot90_en=$3
c2_raw=$4

if (( c1_rot90_en != 0 && c1_rot90_en != 1 )); then
    echo "c1_rot90_en must be 0 or 1!" >&2
    exit 1
fi

if (( c1_raw < -64 || c1_raw > 63 )); then
    echo "c1_raw must be -64 to 63!" >&2
    exit 1
fi

if (( c2_rot90_en != 0 && c2_rot90_en != 1 )); then
    echo "c2_rot90_en must be 0 or 1!" >&2
    exit 1
fi

if (( c2_raw < -64 || c2_raw > 63 )); then
    echo "c2_raw must be -64 to 63!" >&2
    exit 1
fi

# tx_intf reg 5 bit layout (CSI fuzzer coefficients):
#   bits  6:0  = c1 unsigned (7-bit two's complement: negative += 128)
#   bit   9    = c1_rot90_en
#   bits 16:10 = c2 unsigned (7-bit, same encoding)
#   bit  19    = c2_rot90_en

#==============================================================================
# Constants
#==============================================================================

TWOS_COMP_MOD=128      # 2^7 — add to negative values for 7-bit unsigned representation
C1_ROT90_BIT=512       # 1 << 9
C2_FIELD_SHIFT=1024    # 1 << 10
C2_ROT90_BIT=524288    # 1 << 19

if (( c1_raw < 0 )); then
    unsigned_c1=$((TWOS_COMP_MOD + c1_raw))
else
    unsigned_c1=$c1_raw
fi

if (( c2_raw < 0 )); then
    unsigned_c2=$((TWOS_COMP_MOD + c2_raw))
else
    unsigned_c2=$c2_raw
fi

unsigned_dec_combined=$((unsigned_c1 + C1_ROT90_BIT * c1_rot90_en + C2_FIELD_SHIFT * unsigned_c2 + C2_ROT90_BIT * c2_rot90_en))

# sdrctl tx_intf register 5 = CSI fuzzer coefficient register
SDRCTL_REG_TX_INTF_CSI_FUZZER=5

echo "sdrctl dev $OPENWIFI_IFACE set reg tx_intf $SDRCTL_REG_TX_INTF_CSI_FUZZER $unsigned_dec_combined"
sdrctl dev "$OPENWIFI_IFACE" set reg tx_intf "$SDRCTL_REG_TX_INTF_CSI_FUZZER" "$unsigned_dec_combined"
