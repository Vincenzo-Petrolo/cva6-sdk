#!/bin/sh
#==============================================================================
# monitor_ch.sh — Set WiFi interface to monitor mode on a given channel
#
# Theshire-specific override (uses iw instead of iwconfig).
# The upstream version uses iwconfig which is not available on Buildroot.
#
# Usage:
#   ./monitor_ch.sh [interface] [channel]
#   ./monitor_ch.sh wlan0 36
#
# SPDX-FileCopyrightText: 2019 UGent (original), 2026 EPFL-ESL (theshire port)
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================
set -eu

if [ $# -ne 2 ]; then
  echo "Usage: ./monitor_ch.sh <interface> <channel>" >&2
  exit 1
fi

nic_name="$1"
ch_number="$2"

ip link set "$nic_name" down
iw dev "$nic_name" set type monitor
ip link set "$nic_name" up
iw dev "$nic_name" set channel "$ch_number"
iw dev "$nic_name" info

./agc_settings.sh 1
