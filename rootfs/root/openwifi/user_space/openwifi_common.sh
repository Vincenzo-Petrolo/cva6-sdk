#!/usr/bin/env bash
#==============================================================================
# openwifi_common.sh — Shared helper for OpenWiFi user-space scripts
#
# Source this at the top of scripts that need sysfs access, interface
# detection, or IIO device detection:
#   source "$(dirname "$0")/openwifi_common.sh"
#
# Provides:
#   openwifi_cd_sdr_sysfs  — cd to the sdr sysfs directory (auto-detect)
#   openwifi_cd_iio_device — cd to the AD9361 IIO debugfs directory
#   OPENWIFI_IFACE         — WiFi interface name (auto-detected or override)
#   OPENWIFI_DATA_DIR      — path to ~/openwifi/arbitrary_iq_gen/
#
# Supports: Zynq-7020 (32-bit), ZCU104 (aarch64), Theshire/CVA6 (rv64)
#
# Requires bash. Callers set their own error handling (set -euo pipefail).
# This library does NOT set error handling — it runs under the caller's opts.
#
# Author: Andreas T. Kristensen
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

# Interface auto-detect: prefer sdr* (OpenWiFi data NIC), then first wireless,
# then hardcoded sdr0 fallback.  This ordering avoids picking up mon0 or a USB
# WiFi dongle's wlan0 when both coexist with the SDR interface.
# Exported so child scripts (e.g., csi_fuzzer.sh called from csi_fuzzer_scan.sh)
# inherit it without re-running iw dev on every invocation.
if [[ -z "${OPENWIFI_IFACE:-}" ]]; then
  OPENWIFI_IFACE=$(iw dev 2>/dev/null | awk '$1 == "Interface" && $2 ~ /^sdr/ { print $2; exit }' || true)
  if [[ -z "$OPENWIFI_IFACE" ]]; then
    OPENWIFI_IFACE=$(iw dev 2>/dev/null | awk '$1 == "Interface" { print $2; exit }' || true)
  fi
  if [[ -z "$OPENWIFI_IFACE" ]]; then
    OPENWIFI_IFACE="sdr0"
  fi
fi
export OPENWIFI_IFACE

# Data directory (IQ files, etc.)
if [[ -z "${OPENWIFI_DATA_DIR:-}" ]]; then
  OPENWIFI_DATA_DIR="${HOME}/openwifi/arbitrary_iq_gen"
fi
export OPENWIFI_DATA_DIR

#------------------------------------------------------------------------------
# openwifi_cd_sdr_sysfs — cd to the sdr sysfs directory
#
# Checks five paths (theshire root-level, theshire `soc:sdr`, theshire
# `/soc/sdr` fallback, Zynq newer, Zynq older) and exits with an error if
# none found.
#
# Theshire DTS has `sdr: sdr` at the device-tree root (not inside
# `soc: soc { simple-bus }`), so Linux creates `/sys/devices/platform/sdr`.
# The /soc/sdr variant is kept as fallback in case the DTS is reorganized.
#
# Args: none
# Returns: 0 on success, exits 1 if no sdr sysfs path found
#------------------------------------------------------------------------------
openwifi_cd_sdr_sysfs() {
  if [[ -d "/sys/devices/platform/sdr" ]]; then
    cd /sys/devices/platform/sdr || exit 1
  elif [[ -d "/sys/devices/platform/soc/soc:sdr" ]]; then
    cd /sys/devices/platform/soc/soc:sdr || exit 1
  elif [[ -d "/sys/devices/platform/soc/sdr" ]]; then
    cd /sys/devices/platform/soc/sdr || exit 1
  elif [[ -d "/sys/devices/platform/fpga-axi@0/fpga-axi@0:sdr" ]]; then
    cd /sys/devices/platform/fpga-axi@0/fpga-axi@0:sdr || exit 1
  elif [[ -d "/sys/devices/soc0/fpga-axi@0/fpga-axi@0:sdr" ]]; then
    cd /sys/devices/soc0/fpga-axi@0/fpga-axi@0:sdr || exit 1
  else
    printf 'ERROR: cannot find sdr sysfs path\n' >&2
    exit 1
  fi
}

#------------------------------------------------------------------------------
# openwifi_cd_iio_device — cd to an AD9361 IIO directory containing a target file
#
# Searches two sysfs trees for iio:device0 through iio:device4:
#   /sys/kernel/debug/iio/  — debugfs (direct_reg_access lives here)
#   /sys/bus/iio/devices/   — bus sysfs (in_voltage_rf_bandwidth, in_voltage0_rssi)
#
# Args:
#   $1 — target file to find (default: direct_reg_access)
#------------------------------------------------------------------------------
openwifi_cd_iio_device() {
  local iio_target="${1:-direct_reg_access}"
  local i=0
  # Search debugfs first (direct_reg_access), then bus sysfs (voltage/bandwidth)
  while [[ "$i" -le 4 ]]; do
    if [[ -f "/sys/kernel/debug/iio/iio:device${i}/${iio_target}" ]]; then
      cd "/sys/kernel/debug/iio/iio:device${i}/" || return 1
      return 0
    fi
    if [[ -f "/sys/bus/iio/devices/iio:device${i}/${iio_target}" ]]; then
      cd "/sys/bus/iio/devices/iio:device${i}/" || return 1
      return 0
    fi
    i=$((i + 1))
  done
  printf 'ERROR: cannot find %s in iio:device0..4\n' "$iio_target" >&2
  printf 'Check log to make sure ad9361 driver is loaded!\n' >&2
  return 1
}
