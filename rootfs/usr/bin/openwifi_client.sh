#!/bin/sh
#******************************************************************************
# openwifi_client.sh
#
# Thin client-mode helper for the OpenWiFi mac80211 interface on the CVA6 Linux
# target. This script wraps the standard Linux WiFi userspace flow and keeps all
# runtime state under /run/openwifi.
#
# Supported commands:
#   scan [iface]
#   connect <ssid> <passphrase> [iface]
#   status [iface]
#   disconnect [iface]
#
# Optional environment:
#   THS_WIFI_FREQ_MHZ   pin association scans to one channel frequency in MHz
#******************************************************************************

set -eu

#==============================================================================
# Constants
#==============================================================================
PATH=/usr/sbin:/usr/bin:/sbin:/bin
readonly RUNTIME_DIR="/run/openwifi"
readonly ASSOC_TIMEOUT_SEC=20

#==============================================================================
# Helpers
#==============================================================================

usage() {
  echo "Usage:"
  echo "  openwifi_client.sh scan [iface]"
  echo "  openwifi_client.sh connect <ssid> <passphrase> [iface]"
  echo "  openwifi_client.sh status [iface]"
  echo "  openwifi_client.sh disconnect [iface]"
  echo
  echo "Optional environment:"
  echo "  THS_WIFI_FREQ_MHZ=<freq MHz>  pin association scans to one channel"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

# Find the first wireless interface reported by iw.
find_openwifi_iface() {
  iw dev 2>/dev/null | awk '$1 == "Interface" { print $2; exit }'
}

# Resolve the requested interface or fall back to auto-detection.
resolve_iface() {
  iface_arg="${1:-}"

  if [ -n "$iface_arg" ]; then
    echo "$iface_arg"
    return 0
  fi

  iface_auto="$(find_openwifi_iface)"
  if [ -n "$iface_auto" ]; then
    echo "$iface_auto"
    return 0
  fi

  echo "No WiFi interface found. Pass the interface explicitly." >&2
  exit 1
}

# Compute per-interface runtime file paths under /run/openwifi.
state_paths() {
  iface="$1"
  conf_path="${RUNTIME_DIR}/wpa_supplicant-${iface}.conf"
  ctrl_dir="${RUNTIME_DIR}/ctrl-${iface}"
  pid_path="${RUNTIME_DIR}/wpa_supplicant-${iface}.pid"
}

# Write a temporary wpa_supplicant config for one SSID/passphrase pair.
write_wpa_config() {
  ssid="$1"
  passphrase="$2"
  conf_path="$3"
  ctrl_dir="$4"
  scan_freq_mhz="${5:-}"

  mkdir -p "$RUNTIME_DIR" "$ctrl_dir"
  {
    echo "ctrl_interface=${ctrl_dir}"
    echo "update_config=0"
    wpa_passphrase "$ssid" "$passphrase" | awk -v scan_freq_mhz="$scan_freq_mhz" '
      /^network=\{/ {
        print
        if (scan_freq_mhz != "") {
          print "\tscan_freq=" scan_freq_mhz
        }
        next
      }
      { print }
    '
  } > "$conf_path"
}

# Validate optional frequency pinning input from the environment.
validate_scan_freq_mhz() {
  scan_freq_mhz="${1:-}"

  if [ -z "$scan_freq_mhz" ]; then
    return 0
  fi

  case "$scan_freq_mhz" in
    *[!0-9]*)
      echo "THS_WIFI_FREQ_MHZ must be an integer in MHz: ${scan_freq_mhz}" >&2
      exit 1
      ;;
  esac
}

# Wait for wpa_supplicant to finish association before starting DHCP.
wait_for_association() {
  iface="$1"
  ctrl_dir="$2"
  remaining_sec="$ASSOC_TIMEOUT_SEC"

  while [ "$remaining_sec" -gt 0 ]; do
    if wpa_cli -p "$ctrl_dir" -i "$iface" status 2>/dev/null \
      | grep -q '^wpa_state=COMPLETED$'; then
      return 0
    fi

    sleep 1
    remaining_sec=$((remaining_sec - 1))
  done

  echo "Timed out waiting for WiFi association on ${iface}" >&2
  wpa_cli -p "$ctrl_dir" -i "$iface" status 2>/dev/null || true
  return 1
}

#==============================================================================
# Actions
#==============================================================================

scan_iface() {
  iface="$1"

  ip link set "$iface" up
  iw dev "$iface" scan
}

connect_iface() {
  ssid="$1"
  passphrase="$2"
  iface="$3"
  scan_freq_mhz="${THS_WIFI_FREQ_MHZ:-}"

  state_paths "$iface"
  validate_scan_freq_mhz "$scan_freq_mhz"

  ip link set "$iface" up

  if [ -f "$pid_path" ]; then
    pid="$(cat "$pid_path" 2>/dev/null || true)"
    if [ -n "$pid" ]; then
      kill "$pid" 2>/dev/null || true
    fi
  fi

  write_wpa_config "$ssid" "$passphrase" "$conf_path" "$ctrl_dir" "$scan_freq_mhz"

  if [ -n "$scan_freq_mhz" ]; then
    echo "Pinning association scan to ${scan_freq_mhz} MHz on ${iface}"
  fi

  wpa_supplicant -B -i "$iface" -c "$conf_path" -P "$pid_path" -C "$ctrl_dir"
  wait_for_association "$iface" "$ctrl_dir"

  # Wait for carrier — mac80211 carrier-on is async and delayed on 100MHz CVA6.
  # Without this, first udhcpc attempt hits NO-CARRIER window and fails.
  echo "Waiting for carrier on ${iface}..."
  for _ in 1 2 3 4 5; do
    [ "$(cat /sys/class/net/${iface}/carrier 2>/dev/null)" = "1" ] && break
    sleep 1
  done

  udhcpc -i "$iface" -q -n -t 5

  # Enable quickack on the default route to disable delayed ACK (40ms wait).
  # On an asymmetric link (AP sends data, board sends ACKs), delayed ACK adds
  # pure latency with zero piggybacking benefit.  Measured: 34→64 KB/s (2x).
  gw=$(ip route show default dev "$iface" 2>/dev/null | awk '{print $3}')
  if [ -n "$gw" ]; then
    ip route change default via "$gw" dev "$iface" quickack 1 2>/dev/null || true
  fi
}

status_iface() {
  iface="$1"

  state_paths "$iface"

  echo "Interface: $iface"
  echo
  iw dev "$iface" info
  echo
  ip addr show dev "$iface"

  if [ -d "$ctrl_dir" ]; then
    echo
    wpa_cli -p "$ctrl_dir" -i "$iface" status || true
  fi
}

disconnect_iface() {
  iface="$1"

  state_paths "$iface"

  if [ -d "$ctrl_dir" ]; then
    wpa_cli -p "$ctrl_dir" -i "$iface" disconnect || true
    wpa_cli -p "$ctrl_dir" -i "$iface" terminate || true
  fi

  if [ -f "$pid_path" ]; then
    pid="$(cat "$pid_path" 2>/dev/null || true)"
    if [ -n "$pid" ]; then
      kill "$pid" 2>/dev/null || true
    fi
  fi

  ip addr flush dev "$iface" || true
  ip link set "$iface" down || true
}

#==============================================================================
# Main
#==============================================================================

need_cmd iw
need_cmd ip

action="${1:-}"

case "$action" in
  scan)
    iface="$(resolve_iface "${2:-}")"
    scan_iface "$iface"
    ;;
  connect)
    if [ "$#" -lt 3 ]; then
      usage
      exit 1
    fi
    need_cmd wpa_passphrase
    need_cmd wpa_supplicant
    need_cmd wpa_cli
    need_cmd udhcpc
    iface="$(resolve_iface "${4:-}")"
    connect_iface "$2" "$3" "$iface"
    ;;
  status)
    need_cmd wpa_cli
    iface="$(resolve_iface "${2:-}")"
    status_iface "$iface"
    ;;
  disconnect)
    need_cmd wpa_cli
    iface="$(resolve_iface "${2:-}")"
    disconnect_iface "$iface"
    ;;
  *)
    usage
    exit 1
    ;;
esac
