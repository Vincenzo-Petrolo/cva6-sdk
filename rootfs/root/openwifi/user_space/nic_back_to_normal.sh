#!/bin/sh
#==============================================================================
# nic_back_to_normal.sh — Restore WiFi interface from monitor to managed mode
#
# Theshire-specific override (uses iw instead of iwconfig).
# The upstream version uses iwconfig which is not available on Buildroot.
#
# Usage:
#   ./nic_back_to_normal.sh [interface]
#   ./nic_back_to_normal.sh wlan0
#
# SPDX-FileCopyrightText: 2019 UGent (original), 2026 EPFL-ESL (theshire port)
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================
set -eu

if [ $# -ne 1 ]; then
  echo "Usage: ./nic_back_to_normal.sh <interface>" >&2
  exit 1
fi

nic_name="$1"

ip link set "$nic_name" down
iw dev "$nic_name" set type managed
ip link set "$nic_name" up
iw dev "$nic_name" info

./agc_settings.sh 1
