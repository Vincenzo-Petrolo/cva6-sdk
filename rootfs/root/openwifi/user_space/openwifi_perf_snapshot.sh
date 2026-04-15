#!/usr/bin/env bash

#==============================================================================
# openwifi_perf_snapshot.sh — One-shot OpenWiFi performance/debug snapshot
#
# Dumps the most useful STA/AP state for quick bottleneck triage on theshire:
# - link / station state
# - selected OpenWiFi dmesg markers
# - TX/RX statistics
# - TX queue state
# - direct sysfs counters including stall/error counters
# - interrupt / softirq / softnet state
# - lightweight scheduler/load snapshot
# - minstrel rc_stats when available
#
# Usage:
#   bash ./openwifi_perf_snapshot.sh [iface]
#
# Args:
#   iface  Optional interface name. Defaults to OPENWIFI_IFACE from
#          openwifi_common.sh auto-detection.
#
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail
# shellcheck disable=SC1091
# shellcheck source=./openwifi_common.sh
. "$(dirname "$0")/openwifi_common.sh"

iface="${1:-$OPENWIFI_IFACE}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
original_kernel_printk="$(cat /proc/sys/kernel/printk 2>/dev/null || true)"

section() {
  printf '\n=== %s ===\n' "$1"
}

restore_kernel_printk() {
  if [[ -n "$original_kernel_printk" ]]; then
    printf '%s\n' "$original_kernel_printk" > /proc/sys/kernel/printk 2>/dev/null || true
  fi
}

trap restore_kernel_printk EXIT

# Temporarily raise console logging during the snapshot so warning-level dmesg
# output remains visible while collecting evidence. Restore the prior setting on
# exit so the helper does not leave verbose printk enabled for follow-on traffic.
echo 7 > /proc/sys/kernel/printk

section "snapshot"
date
echo "iface: $iface"

section "kernel printk"
if [[ -n "$original_kernel_printk" ]]; then
  echo "before snapshot: $original_kernel_printk"
else
  echo "before snapshot: unavailable"
fi
echo -n "during snapshot: "
cat /proc/sys/kernel/printk 2>/dev/null || echo "/proc/sys/kernel/printk unavailable"

section "iw link"
iw dev "$iface" link 2>/dev/null || echo "iw link unavailable"

section "station dump"
iw dev "$iface" station dump 2>/dev/null || echo "station dump unavailable"

section "ip addr"
ip addr show dev "$iface" 2>/dev/null || echo "ip addr unavailable"

section "selected dmesg markers"
dmesg | grep -E 'Rx A-MPDU request|did not acknowledge authentication response|Removed STA|Destroyed STA|disassoc|deauth|openwifi_tx:|openwifi_ampdu_action:|rx_dma_watchdog:|invalid header' || \
  echo "no matching markers"

section "tx stats"
"${script_dir}/tx_stat_show.sh" || echo "tx_stat_show failed"

section "rx stats"
"${script_dir}/rx_stat_show.sh" || echo "rx_stat_show failed"

section "tx prio queue"
"${script_dir}/tx_prio_queue_show.sh" || echo "tx_prio_queue_show failed"

section "runtime knobs"
if command -v sdrctl >/dev/null 2>&1; then
  echo -n "drv_rx[0] (rx sensitivity threshold): "
  sdrctl dev "$iface" get reg drv_rx 0 2>/dev/null || echo "unavailable"
  echo -n "drv_xpu[0] (LBT threshold): "
  sdrctl dev "$iface" get reg drv_xpu 0 2>/dev/null || echo "unavailable"
  echo -n "drv_tx[7] (tx debug level): "
  sdrctl dev "$iface" get reg drv_tx 7 2>/dev/null || echo "unavailable"
  echo -n "drv_rx[7] (rx debug level): "
  sdrctl dev "$iface" get reg drv_rx 7 2>/dev/null || echo "unavailable"
else
  echo "sdrctl unavailable"
fi

section "statistics collection"
openwifi_cd_sdr_sysfs
if [[ -f stat_enable ]]; then
  stat_enable_value="$(cat stat_enable 2>/dev/null || echo "unavailable")"
  echo "stat_enable: ${stat_enable_value}"
  if [[ "$stat_enable_value" != "1" ]]; then
    echo "warning: TX/RX packet counters below may be stale or incomplete because stat_enable != 1"
  fi
else
  echo "stat_enable: missing"
fi

section "ampdu rx state"
openwifi_cd_sdr_sysfs
if [[ -f ampdu_rx_state ]]; then
  cat ampdu_rx_state
else
  echo "ampdu_rx_state: missing"
fi

section "rssi / gain readback"
"${script_dir}/rssi_openwifi_show.sh" 2>/dev/null || echo "rssi_openwifi_show failed"
"${script_dir}/rssi_ad9361_show.sh" 1 2>/dev/null || echo "rssi_ad9361_show failed"
"${script_dir}/rx_gain_show.sh" 2>/dev/null || echo "rx_gain_show failed"

section "direct sysfs counters"
openwifi_cd_sdr_sysfs
for attr in \
  tx_data_pkt_need_ack_num_total \
  tx_data_pkt_need_ack_num_total_fail \
  tx_data_pkt_need_ack_num_retx \
  tx_dma_stall_enter_count \
  tx_dma_stall_clear_count \
  tx_dma_stall_fast_drop_count \
  tx_dma_timeout_count \
  tx_dma_error_count \
  tx_dma_hard_stop_count \
  tx_dma_soft_stop_count \
  tx_dma_stall_window_count \
  rx_data_pkt_num_total \
  rx_data_pkt_num_fail \
  rx_invalid_header_count \
  rx_dma_cb_full_count \
  rx_irq49_count \
  rx_dma_cb_count \
  rx_dma_wd_restart_count \
  csma_cfg0; do
  if [[ -f "$attr" ]]; then
    printf '%s: ' "$attr"
    cat "$attr"
  else
    printf '%s: missing\n' "$attr"
  fi
done

section "interrupts"
cat /proc/interrupts 2>/dev/null || echo "/proc/interrupts unavailable"

section "softirqs"
cat /proc/softirqs 2>/dev/null || echo "/proc/softirqs unavailable"

section "softnet_stat"
cat /proc/net/softnet_stat 2>/dev/null || echo "/proc/net/softnet_stat unavailable"

section "loadavg"
cat /proc/loadavg 2>/dev/null || echo "/proc/loadavg unavailable"

section "schedstat"
cat /proc/schedstat 2>/dev/null || echo "/proc/schedstat unavailable"

section "vmstat"
if command -v vmstat >/dev/null 2>&1; then
  vmstat 1 3 2>/dev/null || echo "vmstat failed"
else
  echo "vmstat not available"
fi

section "minstrel rc_stats"
mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
cat /sys/kernel/debug/ieee80211/phy0/netdev:"$iface"/stations/*/rc_stats 2>/dev/null || \
  echo "rc_stats not available"
