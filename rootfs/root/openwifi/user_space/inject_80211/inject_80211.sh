#!/usr/bin/env bash

#==============================================================================
# inject_80211.sh — 802.11n packet injection sweep
#
# Usage: ./inject_80211.sh
#   Sweeps MCS 0..7 x frame sizes 50..1450 bytes on wlan0 (in monitor mode).
#
# Author: Michael Mehari
# Author: Andreas T. Kristensen (ZCU104 port)
# SPDX-FileCopyrightText: 2019 UGent
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail

HW_MODE='n'
COUNT=100
DELAY_US=1000                       # inter-packet delay (microseconds)
IF="wlan0"

# 802.11n packet sweep parameters
MCS_INDEX_MAX=7                     # MCS 0..7 (HT single-stream rates)
FRAME_SIZE_MIN_BYTES=50
FRAME_SIZE_MAX_BYTES=1450
FRAME_SIZE_STEP_BYTES=100

for ((size_bytes = FRAME_SIZE_MIN_BYTES; size_bytes <= FRAME_SIZE_MAX_BYTES; size_bytes += FRAME_SIZE_STEP_BYTES)); do
  for ((mcs = 0; mcs <= MCS_INDEX_MAX; mcs++)); do
    ow_inject_80211 -m "$HW_MODE" -n "$COUNT" -d "$DELAY_US" -r "$mcs" -s "$size_bytes" "$IF" || true
    sleep 1
  done
done
