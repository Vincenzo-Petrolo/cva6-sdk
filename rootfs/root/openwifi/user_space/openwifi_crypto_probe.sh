#!/usr/bin/env bash

#==============================================================================
# openwifi_crypto_probe.sh — Plain-vs-SSH transfer helper for CVA6 experiments
#
# This helper standardizes the target-side setup for the application-layer
# crypto probe. It is NOT the primary WiFi throughput benchmark; use iperf3 for
# that. The goal here is to compare an unencrypted transfer against an SSH/scp
# transfer in the same direction.
#
# Usage:
#   bash ./openwifi_crypto_probe.sh prepare [size_mb] [file]
#   bash ./openwifi_crypto_probe.sh recv-plain [port] [outfile]
#   bash ./openwifi_crypto_probe.sh send-plain <peer_ip> [port] [file]
#   bash ./openwifi_crypto_probe.sh show-commands <board_ip> <laptop_ip> [port] [cipher]
#
# Defaults:
#   size_mb = 8
#   file    = /tmp/openwifi_crypto_probe.bin
#   port    = 9000
#   cipher  = aes128-ctr
#
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail

readonly DEFAULT_SIZE_MB=8
readonly DEFAULT_FILE="/tmp/openwifi_crypto_probe.bin"
readonly DEFAULT_PORT=9000
readonly DEFAULT_CIPHER="aes128-ctr"

usage() {
  echo "Usage:"
  echo "  $0 prepare [size_mb] [file]"
  echo "  $0 recv-plain [port] [outfile]"
  echo "  $0 send-plain <peer_ip> [port] [file]"
  echo "  $0 show-commands <board_ip> <laptop_ip> [port] [cipher]"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

prepare_file() {
  local size_mb="${1:-$DEFAULT_SIZE_MB}"
  local file_path="${2:-$DEFAULT_FILE}"

  need_cmd dd
  need_cmd sha256sum
  dd if=/dev/urandom of="$file_path" bs=1M count="$size_mb"
  sha256sum "$file_path"
}

recv_plain() {
  local port="${1:-$DEFAULT_PORT}"
  local outfile="${2:-$DEFAULT_FILE}.recv"

  need_cmd nc
  echo "Receiving plain transfer on port ${port} -> ${outfile}"
  nc -l -p "$port" > "$outfile"
  sha256sum "$outfile" 2>/dev/null || true
}

send_plain() {
  local peer_ip="$1"
  local port="${2:-$DEFAULT_PORT}"
  local file_path="${3:-$DEFAULT_FILE}"

  need_cmd nc
  nc "$peer_ip" "$port" < "$file_path"
}

show_commands() {
  local board_ip="$1"
  local laptop_ip="$2"
  local port="${3:-$DEFAULT_PORT}"
  local cipher="${4:-$DEFAULT_CIPHER}"

  cat <<EOF
Laptop plain receive:
  nc -l -p ${port} > /tmp/openwifi_crypto_probe.recv

Laptop source file for plain/scp push:
  dd if=/dev/urandom of=${DEFAULT_FILE} bs=1M count=${DEFAULT_SIZE_MB}

Board plain send:
  bash ./openwifi_crypto_probe.sh send-plain ${laptop_ip} ${port} ${DEFAULT_FILE}

Laptop scp push to board:
  scp -c ${cipher} ${DEFAULT_FILE} root@${board_ip}:/tmp/openwifi_crypto_probe.push

Laptop scp pull from board:
  scp -c ${cipher} root@${board_ip}:${DEFAULT_FILE} /tmp/openwifi_crypto_probe.pull

Recommended note:
  Record the cipher explicitly in your notes or force it with -c so the result is reproducible.
EOF
}

main() {
  local cmd="${1:-}"

  case "$cmd" in
    prepare)
      prepare_file "${2:-}" "${3:-}"
      ;;
    recv-plain)
      recv_plain "${2:-}" "${3:-}"
      ;;
    send-plain)
      if [[ $# -lt 2 ]]; then
        usage
        exit 1
      fi
      send_plain "$2" "${3:-}" "${4:-}"
      ;;
    show-commands)
      if [[ $# -lt 3 ]]; then
        usage
        exit 1
      fi
      show_commands "$2" "$3" "${4:-}" "${5:-}"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
