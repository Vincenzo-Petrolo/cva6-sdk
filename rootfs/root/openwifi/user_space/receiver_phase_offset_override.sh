#!/usr/bin/env bash

#==============================================================================
# receiver_phase_offset_override.sh — RX phase offset register override
#
# Usage: ./receiver_phase_offset_override.sh [phase_offset]
#   With argument: set phase offset override via sdrctl rx reg 19
#   Without argument: disable override (clear bit 31)
#
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"

# sdrctl RX register for receiver phase offset control
SDRCTL_REG_RX_PHASE_OFFSET=19

# bits 15:0 = signed phase offset (masked to 16 bits)
# bit 31    = override enable
PHASE_MASK=65535       # 0xFFFF — lower 16 bits
OVERRIDE_EN=2147483648 # 0x80000000 — bit 31 (decimal avoids 1<<31 signed overflow on
                       # 32-bit shells; requires 64-bit shell arithmetic — aarch64/rv64)

set -x

if [[ -n "${1:-}" ]]; then
  phase_offset=$1
else
  echo "Disable phase offset override by setting bit31 to 0"
  reg_val=0  # bit 31 clear = override disabled
  printf "reg_val=0x%X\n" "$reg_val"
  echo "sdrctl dev $OPENWIFI_IFACE set reg rx $SDRCTL_REG_RX_PHASE_OFFSET $reg_val"
  sdrctl dev "$OPENWIFI_IFACE" set reg rx "$SDRCTL_REG_RX_PHASE_OFFSET" "$reg_val"
  exit 0
fi

echo "phase_offset=$phase_offset"

reg_val=$(( (phase_offset & PHASE_MASK) | OVERRIDE_EN ))
printf "reg_val=0x%X\n" "$reg_val"

sdrctl dev "$OPENWIFI_IFACE" set reg rx "$SDRCTL_REG_RX_PHASE_OFFSET" "$reg_val"

set +x
