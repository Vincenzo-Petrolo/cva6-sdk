#!/usr/bin/env bash

#==============================================================================
# openwifi_perf_sweep.sh — Small parameter sweep for associated OpenWiFi tests
#
# Runs a cautious one-variable-at-a-time sweep against an already-associated
# theshire STA link. For each test point, it:
#   - applies one tuning value
#   - clears OpenWiFi counters
#   - runs one iperf3 download
#   - runs one iperf3 upload
#   - runs one ping burst
#   - saves a snapshot bundle to /tmp
#
# This is intentionally small and explicit. It is NOT an auto-tuning framework.
#
# Usage:
#   ./openwifi_perf_sweep.sh <peer_ip> [iface]
#
# Example:
#   ./openwifi_perf_sweep.sh 192.168.50.1 wlan0
#
# Requirements:
#   - interface already associated and reachable
#   - iperf3 server already running on the peer
#
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"

peer_ip="${1:-}"
iface="${2:-$OPENWIFI_IFACE}"

if [[ -z "$peer_ip" ]]; then
  echo "Usage: $0 <peer_ip> [iface]" >&2
  exit 1
fi

# Keep console logging verbose enough that OpenWiFi warnings stay visible on the
# serial console throughout the sweep.
echo 7 > /proc/sys/kernel/printk

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need_cmd iw
need_cmd iperf3
need_cmd ping
need_cmd sdrctl

if ! iw dev "$iface" link 2>/dev/null | grep -qv 'Not connected'; then
  echo "ERROR: $iface is not associated" >&2
  exit 1
fi

if ! ping -c 1 -W 2 "$peer_ip" >/dev/null 2>&1; then
  echo "ERROR: peer $peer_ip is not reachable" >&2
  exit 1
fi

ts="$(date +%Y%m%d_%H%M%S)"
out_dir="/tmp/openwifi_sweep_${ts}"
mkdir -p "$out_dir"

echo "Sweep output dir: $out_dir"

run_case() {
  local case_name="$1"
  local drv_rx_threshold="$2"
  local quickack_flag="$3"
  local case_dir="${out_dir}/${case_name}"
  local peer_net

  mkdir -p "$case_dir"
  peer_net="$(printf '%s' "$peer_ip" | awk -F. '{print $1"."$2"."$3".0/24"}')"

  echo
  echo "=== CASE ${case_name} ==="
  echo "drv_rx threshold: ${drv_rx_threshold}"
  echo "quickack: ${quickack_flag}"

  sdrctl dev "$iface" set reg drv_rx 0 "$drv_rx_threshold"

  if [[ "$quickack_flag" = "1" ]]; then
    ip route replace "$peer_net" dev "$iface" quickack 1
    echo 0 > /proc/sys/net/ipv4/tcp_slow_start_after_idle
    echo 1 > /proc/sys/net/ipv4/tcp_no_metrics_save
  else
    ip route replace "$peer_net" dev "$iface"
  fi

  cd "$(dirname "$0")"
  ./stat_enable.sh 1
  ./tx_stat_show.sh clear
  ./rx_stat_show.sh clear
  ./tx_prio_queue_show.sh clear

  ./openwifi_perf_snapshot.sh "$iface" > "${case_dir}/before.txt" 2>&1 || true
  iperf3 -c "$peer_ip" -t 15 -R > "${case_dir}/iperf_download.txt" 2>&1 || true
  iperf3 -c "$peer_ip" -t 15 > "${case_dir}/iperf_upload.txt" 2>&1 || true
  ping -c 10 "$peer_ip" > "${case_dir}/ping.txt" 2>&1 || true
  ./openwifi_perf_snapshot.sh "$iface" > "${case_dir}/after.txt" 2>&1 || true
}

# Conservative first sweep:
# - receiver sensitivity at two values already observed to matter
# - with and without quickack
run_case "drv60_qack0" 60 0
run_case "drv60_qack1" 60 1
run_case "drv65_qack0" 65 0
run_case "drv65_qack1" 65 1

echo
echo "Sweep complete. Results saved under $out_dir"
