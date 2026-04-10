#!/usr/bin/env bash

#==============================================================================
# openwifi_laptop_ap_connect.sh — Matched laptop-AP helper for open/WPA2 tests
#
# This helper is intentionally separate from openwifi_client.sh. It exists for
# the controlled laptop-AP harness used in the throughput/debug guides, where
# both open and WPA2 modes keep the same static-IP topology and route-level
# quickack policy.
#
# Usage:
#   bash ./openwifi_laptop_ap_connect.sh open [iface]
#   bash ./openwifi_laptop_ap_connect.sh wpa2 [iface]
#   bash ./openwifi_laptop_ap_connect.sh status [iface]
#   bash ./openwifi_laptop_ap_connect.sh disconnect [iface]
#
# Optional environment:
#   THS_WIFI_FREQ_MHZ     fixed channel frequency in MHz (default: 2447)
#   THS_LAPTOP_AP_OPEN_SSID   open SSID   (default: theshire-lab-open)
#   THS_LAPTOP_AP_WPA2_SSID   WPA2 SSID   (default: theshire-lab-wpa2)
#   THS_LAPTOP_AP_WPA2_PSK    WPA2 PSK    (default: theshire-test)
#   THS_LAPTOP_AP_ADDR_CIDR   target IP   (default: 192.168.50.2/24)
#
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail
# shellcheck disable=SC1091
# shellcheck source=./openwifi_common.sh
. "$(dirname "$0")/openwifi_common.sh"

readonly RUNTIME_DIR="/run/openwifi"
readonly DEFAULT_FREQ_MHZ="2447"
readonly OPEN_SSID="${THS_LAPTOP_AP_OPEN_SSID:-theshire-lab-open}"
readonly WPA2_SSID="${THS_LAPTOP_AP_WPA2_SSID:-theshire-lab-wpa2}"
readonly WPA2_PSK="${THS_LAPTOP_AP_WPA2_PSK:-theshire-test}"
readonly TARGET_ADDR_CIDR="${THS_LAPTOP_AP_ADDR_CIDR:-192.168.50.2/24}"
readonly TARGET_NET_CIDR="${THS_LAPTOP_AP_NET_CIDR:-192.168.50.0/24}"
readonly TARGET_PEER_IP="${THS_LAPTOP_AP_PEER_IP:-192.168.50.1}"

usage() {
  echo "Usage: $0 <open|wpa2|status|disconnect> [iface]"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

runtime_paths() {
  local iface="$1"
  WPA_CONF_PATH="${RUNTIME_DIR}/wpa_laptop_ap_${iface}.conf"
  WPA_CTRL_DIR="${RUNTIME_DIR}/ctrl-laptop-ap-${iface}"
  WPA_PID_PATH="${RUNTIME_DIR}/wpa_laptop_ap_${iface}.pid"
}

setup_static_ip() {
  local iface="$1"
  ip route flush dev "$iface" 2>/dev/null || true
  ip addr flush dev "$iface" 2>/dev/null || true
  ip addr add "$TARGET_ADDR_CIDR" dev "$iface"
  ip route replace "$TARGET_NET_CIDR" dev "$iface" quickack 1
}

disconnect_iface() {
  local iface="$1"

  runtime_paths "$iface"
  if [[ -f "$WPA_PID_PATH" ]]; then
    kill "$(cat "$WPA_PID_PATH")" 2>/dev/null || true
    rm -f "$WPA_PID_PATH"
  fi
  if [[ -d "$WPA_CTRL_DIR" ]]; then
    wpa_cli -p "$WPA_CTRL_DIR" -i "$iface" terminate >/dev/null 2>&1 || true
  fi
  ip route flush dev "$iface" 2>/dev/null || true
  ip addr flush dev "$iface" 2>/dev/null || true
  iw dev "$iface" disconnect >/dev/null 2>&1 || true
  ip link set "$iface" down 2>/dev/null || true
}

connect_open() {
  local iface="$1"
  local freq_mhz="${THS_WIFI_FREQ_MHZ:-$DEFAULT_FREQ_MHZ}"

  disconnect_iface "$iface"
  ip link set "$iface" up
  iw dev "$iface" connect -w "$OPEN_SSID" "$freq_mhz"
  setup_static_ip "$iface"
  ip route get "$TARGET_PEER_IP" || true
}

connect_wpa2() {
  local iface="$1"
  local freq_mhz="${THS_WIFI_FREQ_MHZ:-$DEFAULT_FREQ_MHZ}"
  local timeout_sec=20

  disconnect_iface "$iface"
  runtime_paths "$iface"
  mkdir -p "$RUNTIME_DIR" "$WPA_CTRL_DIR"
  ip link set "$iface" up

  {
    echo "ctrl_interface=${WPA_CTRL_DIR}"
    echo "update_config=0"
    wpa_passphrase "$WPA2_SSID" "$WPA2_PSK" | awk -v scan_freq_mhz="$freq_mhz" '
      /^network=\{/ {
        print
        print "\tscan_freq=" scan_freq_mhz
        next
      }
      { print }
    '
  } > "$WPA_CONF_PATH"

  wpa_supplicant -B -i "$iface" -c "$WPA_CONF_PATH" -P "$WPA_PID_PATH" -C "$WPA_CTRL_DIR"

  while [[ "$timeout_sec" -gt 0 ]]; do
    if wpa_cli -p "$WPA_CTRL_DIR" -i "$iface" status 2>/dev/null | grep -q '^wpa_state=COMPLETED$'; then
      setup_static_ip "$iface"
      ip route get "$TARGET_PEER_IP" || true
      return 0
    fi
    sleep 1
    timeout_sec=$((timeout_sec - 1))
  done

  echo "Timed out waiting for WPA2 association on ${iface}" >&2
  wpa_cli -p "$WPA_CTRL_DIR" -i "$iface" status 2>/dev/null || true
  exit 1
}

show_status() {
  local iface="$1"

  runtime_paths "$iface"
  iw dev "$iface" link 2>/dev/null || echo "iw link unavailable"
  ip addr show dev "$iface" 2>/dev/null || echo "ip addr unavailable"
  ip route show dev "$iface" 2>/dev/null || echo "ip route unavailable"
  if [[ -d "$WPA_CTRL_DIR" ]]; then
    wpa_cli -p "$WPA_CTRL_DIR" -i "$iface" status 2>/dev/null || echo "wpa_cli unavailable"
  fi
}

main() {
  local cmd="${1:-}"
  local iface="${2:-$OPENWIFI_IFACE}"

  if [[ -z "$cmd" ]]; then
    usage
    exit 1
  fi

  need_cmd iw
  need_cmd ip
  need_cmd wpa_supplicant
  need_cmd wpa_cli
  need_cmd wpa_passphrase

  case "$cmd" in
    open)
      connect_open "$iface"
      ;;
    wpa2)
      connect_wpa2 "$iface"
      ;;
    status)
      show_status "$iface"
      ;;
    disconnect)
      disconnect_iface "$iface"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
