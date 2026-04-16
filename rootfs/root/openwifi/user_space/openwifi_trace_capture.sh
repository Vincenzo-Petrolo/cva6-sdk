#!/usr/bin/env bash

#==============================================================================
# openwifi_trace_capture.sh — Bounded trace capture helper for CVA6 WiFi tests
#
# Records one short trace window around association or a short transfer burst.
# This is intentionally conservative: baseline measurements should be run first
# without tracing, then this helper can capture a narrow follow-up window.
#
# Usage:
#   bash ./openwifi_trace_capture.sh <assoc|download-short|upload-short> [iface]
#   bash ./openwifi_trace_capture.sh <mode> [iface] -- <command...>
#
# Examples:
#   bash ./openwifi_trace_capture.sh assoc wlan0
#   bash ./openwifi_trace_capture.sh download-short wlan0 -- iperf3 -c 192.168.50.1 -t 5 -R
#
# Output:
#   /tmp/openwifi_trace_<mode>_<timestamp>/
#     trace.dat
#     trace.txt
#     meta.txt
#
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail
# shellcheck disable=SC1091
# shellcheck source=./openwifi_common.sh
. "$(dirname "$0")/openwifi_common.sh"

readonly DEFAULT_MODE="download-short"
readonly DEFAULT_CAPTURE_SEC=8

usage() {
  echo "Usage: $0 <assoc|download-short|upload-short> [iface]"
  echo "       $0 <mode> [iface] -- <command...>"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

timeout_prefix_for_capture() {
  local capture_sec="$1"

  if command -v timeout >/dev/null 2>&1; then
    printf 'timeout\0%ss\0' "$capture_sec"
    return 0
  fi

  if command -v busybox >/dev/null 2>&1 && busybox timeout 1 true >/dev/null 2>&1; then
    printf 'busybox\0timeout\0%s\0' "$capture_sec"
    return 0
  fi

  echo "Missing required command: timeout (or busybox timeout)" >&2
  exit 1
}

ensure_debugfs() {
  mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
  mount -t tracefs none /sys/kernel/tracing 2>/dev/null || true
}

resolve_capture_sec() {
  local mode="$1"
  case "$mode" in
    assoc)
      echo 12
      ;;
    download-short|upload-short)
      echo "$DEFAULT_CAPTURE_SEC"
      ;;
    *)
      echo "Unsupported trace mode: ${mode}" >&2
      exit 1
      ;;
  esac
}

main() {
  local mode="${1:-$DEFAULT_MODE}"
  local iface="$OPENWIFI_IFACE"
  local capture_sec
  local ts
  local out_dir
  local -a command_argv=()
  local -a bounded_prefix=()

  if [[ "${1:-}" = "-h" || "${1:-}" = "--help" ]]; then
    usage
    exit 0
  fi

  need_cmd trace-cmd
  need_cmd iw
  ensure_debugfs

  capture_sec="$(resolve_capture_sec "$mode")"
  mapfile -d '' -t bounded_prefix < <(timeout_prefix_for_capture "$capture_sec")
  ts="$(date +%Y%m%d_%H%M%S)"
  out_dir="/tmp/openwifi_trace_${mode}_${ts}"
  mkdir -p "$out_dir"

  shift $(( $# > 0 ? 1 : 0 )) || true
  if [[ $# -gt 0 && "${1:-}" != "--" ]]; then
    iface="$1"
    shift
  fi
  if [[ "${1:-}" = "--" ]]; then
    shift
    command_argv=("$@")
  fi

  {
    echo "mode: $mode"
    echo "iface: $iface"
    echo "capture_sec: $capture_sec"
    echo "timestamp: $ts"
    iw dev "$iface" link 2>/dev/null || echo "iw link unavailable"
  } > "${out_dir}/meta.txt"

  echo "Trace output dir: ${out_dir}"

  if [[ ${#command_argv[@]} -gt 0 ]]; then
    echo "Recording command trace for up to ${capture_sec}s: ${command_argv[*]}"
    trace-cmd record \
      -o "${out_dir}/trace.dat" \
      -e sched:sched_switch \
      -e sched:sched_wakeup \
      -e irq:irq_handler_entry \
      -e irq:irq_handler_exit \
      -e irq:softirq_entry \
      -e irq:softirq_exit \
      -e net:net_dev_queue \
      -e skb:kfree_skb \
      -- "${bounded_prefix[@]}" "${command_argv[@]}"
  else
    echo "Recording ${capture_sec}s idle window; run the traffic or association manually now."
    trace-cmd record \
      -o "${out_dir}/trace.dat" \
      -e sched:sched_switch \
      -e sched:sched_wakeup \
      -e irq:irq_handler_entry \
      -e irq:irq_handler_exit \
      -e irq:softirq_entry \
      -e irq:softirq_exit \
      -e net:net_dev_queue \
      -e skb:kfree_skb \
      sleep "$capture_sec"
  fi

  trace-cmd report "${out_dir}/trace.dat" > "${out_dir}/trace.txt"
  echo "Saved trace.dat and trace.txt under ${out_dir}"
}

main "$@"
