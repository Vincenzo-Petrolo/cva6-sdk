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
#   ./openwifi_perf_snapshot.sh [iface]
#
# Args:
#   iface  Optional interface name. Defaults to OPENWIFI_IFACE from
#          openwifi_common.sh auto-detection.
#
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"

iface="${1:-$OPENWIFI_IFACE}"

section() {
  printf '\n=== %s ===\n' "$1"
}

# Keep console logging verbose enough that OpenWiFi warnings stay visible on the
# serial console during measurement runs.
echo 7 > /proc/sys/kernel/printk

section "snapshot"
date
echo "iface: $iface"

section "kernel printk"
cat /proc/sys/kernel/printk 2>/dev/null || echo "/proc/sys/kernel/printk unavailable"

section "iw link"
iw dev "$iface" link 2>/dev/null || echo "iw link unavailable"

section "station dump"
iw dev "$iface" station dump 2>/dev/null || echo "station dump unavailable"

section "ip addr"
ip addr show dev "$iface" 2>/dev/null || echo "ip addr unavailable"

section "selected dmesg markers"
dmesg | grep -E 'Rx A-MPDU request|did not acknowledge authentication response|Removed STA|Destroyed STA|disassoc|deauth|openwifi_tx:|rx_dma_watchdog:|invalid header' || \
  echo "no matching markers"

section "tx stats"
"$(dirname "$0")/tx_stat_show.sh" || echo "tx_stat_show failed"

section "rx stats"
"$(dirname "$0")/rx_stat_show.sh" || echo "rx_stat_show failed"

section "tx prio queue"
"$(dirname "$0")/tx_prio_queue_show.sh" || echo "tx_prio_queue_show failed"

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

section "rssi / gain readback"
"$(dirname "$0")/rssi_openwifi_show.sh" 2>/dev/null || echo "rssi_openwifi_show failed"
"$(dirname "$0")/rssi_ad9361_show.sh" 1 2>/dev/null || echo "rssi_ad9361_show failed"
"$(dirname "$0")/rx_gain_show.sh" 2>/dev/null || echo "rx_gain_show failed"

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
