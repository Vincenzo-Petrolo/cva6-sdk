#!/usr/bin/env bash

#==============================================================================
# theshire_diag_dma.sh — DMA health diagnostic for theshire (CVA6/ZCU104)
#
# Adapted from openwifi kernel_boot/boards/zcu104_fmcs2/scripts/diagnostics/
# zcu104_diag_dma_health.sh for theshire-specific DMA base addresses and
# local (non-SSH) execution.
#
# Usage:
#   ./theshire_diag_dma.sh                  # full snapshot + 20s monitor
#   ./theshire_diag_dma.sh snapshot         # one-shot register dump
#   ./theshire_diag_dma.sh monitor [secs]   # per-second register loop
#   ./theshire_diag_dma.sh irqstep [secs]   # before/after with wait window
#   ./theshire_diag_dma.sh decision         # TX DMA decision tree check
#
# DMA base addresses (from cheshire.zcu104.dts):
#   TX DMA:      0x40000000  (dma_tx — DDR → WiFi baseband)
#   RX DMA:      0x40010000  (dma_rx — WiFi baseband → DDR)
#   Side TX DMA: 0x40001000  (dma_side_tx — DDR → side_ch)
#   Side RX DMA: 0x40011000  (dma_side_rx — side_ch → DDR)
#
# Register offsets are identical to Zynq ADI axi_dmac — only the base differs.
#
# Author: Andreas T. Kristensen (adapted from openwifi zcu104_diag_dma_health.sh)
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail

#==============================================================================
# Theshire DMA base addresses
#==============================================================================
TX_DMA=0x40000000
RX_DMA=0x40010000
SIDE_TX_DMA=0x40001000
SIDE_RX_DMA=0x40011000

# OpenWiFi IP bases (for PHY/XPU context)
RX_INTF=0x40040000
TX_INTF=0x40060000
XPU=0x40070000
AXI_AD9361=0x40080000

#==============================================================================
# ADI axi_dmac register offsets (same across all instances)
#==============================================================================
OFF_IRQ_MASK=0x080
OFF_IRQ_PEND=0x084
OFF_IRQ_SRC=0x088
OFF_CTRL=0x400
OFF_XFER_ID=0x404
OFF_START=0x408
OFF_FLAGS=0x40c
OFF_DEST_ADDR=0x410
OFF_SRC_ADDR=0x414
OFF_X_LENGTH=0x418
OFF_XFER_DONE=0x428
OFF_ACTIVE_ID=0x42c
OFF_STATUS=0x430
OFF_CUR_DEST=0x434
OFF_CUR_SRC=0x438
OFF_DBG0=0x43c
OFF_DBG1=0x440
OFF_DBG2=0x444
OFF_PART_LEN=0x44c
OFF_PART_ID=0x450

#==============================================================================
# Helpers
#==============================================================================

read_reg32() {
  local addr="$1"
  if val="$(busybox devmem "${addr}" 32 2>/dev/null)"; then
    echo "${val}"
  else
    echo "n/a"
  fi
}

# Convert devmem hex output to decimal (handles 0x0, 0X00000000, 0x00000002, etc.)
# Returns 0 for "n/a" or empty input.
reg_to_dec() {
  local val="$1"
  if [[ "$val" == "n/a" ]] || [[ -z "$val" ]]; then
    echo 0
  else
    printf '%d' "$val" 2>/dev/null || echo 0
  fi
}

# Read register at base + offset
read_dma_reg() {
  local base="$1"
  local offset="$2"
  read_reg32 $(printf '0x%08X' $((base + offset)))
}

irq_count_by_pattern() {
  local pat="$1"
  awk -v pat="$pat" '
    $0 ~ pat {
      found = 1
      for (i = 2; i <= NF; i++)
        if ($i ~ /^[0-9]+$/) sum += $i
    }
    END { if (found) print sum + 0; else print 0 }
  ' /proc/interrupts
}

#==============================================================================
# Snapshot: full register dump for one DMA instance
#==============================================================================
print_dma_snapshot() {
  local label="$1"
  local base="$2"
  printf "  %s (base 0x%08X):\n" "$label" "$base"
  printf "    CTRL:      %s\n" "$(read_dma_reg "$base" $OFF_CTRL)"
  printf "    XFER_ID:   %s\n" "$(read_dma_reg "$base" $OFF_XFER_ID)"
  printf "    START:     %s\n" "$(read_dma_reg "$base" $OFF_START)"
  printf "    FLAGS:     %s  (expect 0x2: LAST=1,CYCLIC=0)\n" "$(read_dma_reg "$base" $OFF_FLAGS)"
  printf "    SRC_ADDR:  %s\n" "$(read_dma_reg "$base" $OFF_SRC_ADDR)"
  printf "    DEST_ADDR: %s\n" "$(read_dma_reg "$base" $OFF_DEST_ADDR)"
  printf "    X_LENGTH:  %s\n" "$(read_dma_reg "$base" $OFF_X_LENGTH)"
  printf "    XFER_DONE: %s\n" "$(read_dma_reg "$base" $OFF_XFER_DONE)"
  printf "    ACTIVE_ID: %s\n" "$(read_dma_reg "$base" $OFF_ACTIVE_ID)"
  printf "    STATUS:    %s\n" "$(read_dma_reg "$base" $OFF_STATUS)"
  printf "    CUR_DEST:  %s\n" "$(read_dma_reg "$base" $OFF_CUR_DEST)"
  printf "    CUR_SRC:   %s\n" "$(read_dma_reg "$base" $OFF_CUR_SRC)"
  printf "    DBG2:      %s\n" "$(read_dma_reg "$base" $OFF_DBG2)"
  printf "    PART_LEN:  %s\n" "$(read_dma_reg "$base" $OFF_PART_LEN)"
  printf "    IRQ_MASK:  %s  (expect 0x0: unmasked)\n" "$(read_dma_reg "$base" $OFF_IRQ_MASK)"
  printf "    IRQ_PEND:  %s  (expect 0x0: none stuck)\n" "$(read_dma_reg "$base" $OFF_IRQ_PEND)"
  printf "    IRQ_SRC:   %s\n" "$(read_dma_reg "$base" $OFF_IRQ_SRC)"
  echo
}

print_full_snapshot() {
  local tag="$1"
  echo "=== ${tag} SNAPSHOT ==="
  echo "Date: $(date)"
  echo

  print_dma_snapshot "TX DMA (WiFi TX)" "$TX_DMA"
  print_dma_snapshot "RX DMA (WiFi RX)" "$RX_DMA"
  print_dma_snapshot "Side TX DMA" "$SIDE_TX_DMA"
  print_dma_snapshot "Side RX DMA" "$SIDE_RX_DMA"

  echo "OpenWiFi context:"
  printf "  XPU CSMA_CFG (reg19):  %s  (expect 0xA4A44332)\n" "$(read_reg32 $(printf '0x%08X' $((XPU + 19*4))))"
  printf "  DAC DATA_SEL (ch0):    %s  (expect 0x2: DMA mode)\n" "$(read_reg32 0x40084418)"
  printf "  rx_intf loopback:      %s  (expect 0x0: normal)\n" "$(read_dma_reg $RX_INTF 0x0C)"
  echo

  echo "Interrupt lines:"
  grep -E 'sdr|40000000|40010000|40001000|40011000' /proc/interrupts 2>/dev/null | sed 's/^/  /' || echo "  (no matching IRQ lines)"
  printf "  Counts: rx_pkt=%s tx_dma=%s rx_dma=%s\n" \
    "$(irq_count_by_pattern 'rx_pkt')" \
    "$(irq_count_by_pattern '40000000')" \
    "$(irq_count_by_pattern '40010000')"

  # Sysfs stall counters (if available)
  echo
  echo "DMA sysfs counters:"
  for attr in tx_dma_stall_enter_count tx_dma_stall_clear_count tx_dma_timeout_count \
              tx_dma_error_count tx_dma_hard_stop_count rx_dma_wd_restart_count; do
    val="$(cat /sys/devices/platform/soc/soc:sdr/${attr} 2>/dev/null || \
           cat /sys/devices/platform/sdr/${attr} 2>/dev/null || \
           cat /sys/devices/platform/soc/sdr/${attr} 2>/dev/null || echo 'n/a')"
    printf "  %-35s %s\n" "${attr}:" "$val"
  done
  echo
}

#==============================================================================
# Monitor: per-second TX/RX DMA register loop
#==============================================================================
run_monitor() {
  local duration="${1:-20}"
  echo "=== DMA MONITOR (${duration}s) ==="
  echo "Legend: TX_DONE/RX_DONE should increment. FLAGS should stay 0x2."
  echo

  local i
  for i in $(seq 1 "$duration"); do
    printf "t=%02d TX[DONE=%s START=%s ACTIVE=%s FLAGS=%s] RX[DONE=%s START=%s ACTIVE=%s] IRQ[tx=%s rx=%s pkt=%s]\n" \
      "$i" \
      "$(read_dma_reg $TX_DMA $OFF_XFER_DONE)" \
      "$(read_dma_reg $TX_DMA $OFF_START)" \
      "$(read_dma_reg $TX_DMA $OFF_ACTIVE_ID)" \
      "$(read_dma_reg $TX_DMA $OFF_FLAGS)" \
      "$(read_dma_reg $RX_DMA $OFF_XFER_DONE)" \
      "$(read_dma_reg $RX_DMA $OFF_START)" \
      "$(read_dma_reg $RX_DMA $OFF_ACTIVE_ID)" \
      "$(irq_count_by_pattern '40000000')" \
      "$(irq_count_by_pattern '40010000')" \
      "$(irq_count_by_pattern 'rx_pkt')"
    sleep 1
  done
  echo
}

#==============================================================================
# IRQ step: before/after comparison with wait window
#==============================================================================
run_irqstep() {
  local wait_s="${1:-10}"
  echo "=== IRQ STEP TEST ==="
  echo "BEFORE:"
  print_full_snapshot "IRQ STEP BEFORE"
  echo ">>> Waiting ${wait_s}s — trigger auth/scan NOW <<<"
  sleep "$wait_s"
  echo
  echo "AFTER:"
  print_full_snapshot "IRQ STEP AFTER"
  echo "Interpretation:"
  echo "  - XFER_DONE changed but IRQ counts flat => IRQ delivery/PLIC routing issue"
  echo "  - TX_DONE static with CTRL=1 => TX pipeline stalled"
  echo "  - FLAGS != 0x2 => CYCLIC bit hazard (TX-done IRQ impossible)"
  echo "  - IRQ_PEND nonzero => interrupt fired but CPU never serviced it"
  echo
}

#==============================================================================
# Decision tree: automated TX DMA health check
#==============================================================================
run_decision_tree() {
  echo "=== TX DMA DECISION TREE ==="
  echo

  local ctrl flags irq_mask xfer_done irq_pend irq_src
  ctrl="$(read_dma_reg $TX_DMA $OFF_CTRL)"
  flags="$(read_dma_reg $TX_DMA $OFF_FLAGS)"
  irq_mask="$(read_dma_reg $TX_DMA $OFF_IRQ_MASK)"
  xfer_done="$(read_dma_reg $TX_DMA $OFF_XFER_DONE)"
  irq_pend="$(read_dma_reg $TX_DMA $OFF_IRQ_PEND)"
  irq_src="$(read_dma_reg $TX_DMA $OFF_IRQ_SRC)"
  local tx_irq_count
  tx_irq_count="$(irq_count_by_pattern '40000000')"

  printf "  CTRL:      %s\n" "$ctrl"
  printf "  FLAGS:     %s\n" "$flags"
  printf "  IRQ_MASK:  %s\n" "$irq_mask"
  printf "  XFER_DONE: %s\n" "$xfer_done"
  printf "  IRQ_PEND:  %s\n" "$irq_pend"
  printf "  IRQ_SRC:   %s\n" "$irq_src"
  printf "  IRQ count: %s\n" "$tx_irq_count"
  echo

  # Convert all values to decimal for robust comparison
  # (busybox devmem may return 0x0, 0X00000000, 0x00000002, etc.)
  local ctrl_dec flags_dec irq_mask_dec xfer_done_dec irq_pend_dec irq_src_dec
  ctrl_dec="$(reg_to_dec "$ctrl")"
  flags_dec="$(reg_to_dec "$flags")"
  irq_mask_dec="$(reg_to_dec "$irq_mask")"
  xfer_done_dec="$(reg_to_dec "$xfer_done")"
  irq_pend_dec="$(reg_to_dec "$irq_pend")"
  irq_src_dec="$(reg_to_dec "$irq_src")"

  # Check 1: DMA enabled?
  if [[ "$ctrl_dec" -eq 0 ]]; then
    echo "[FAIL] CTRL=0 — TX DMA not enabled."
    echo "  openwifi_start() or tx_dma channel setup failed."
    echo "  Check dmesg for 'tx_dma_mm2s' errors."
    return
  fi
  echo "[OK] CTRL=$ctrl — DMA enabled"

  # Check 2: CYCLIC bit? (bit 0 of FLAGS)
  if [[ $((flags_dec & 1)) -ne 0 ]]; then
    echo "[FAIL] FLAGS=$flags — CYCLIC bit is SET."
    echo "  When CYCLIC=1, EOT (end-of-transfer) is hardwired to 0 in RTL."
    echo "  TX-done interrupt can NEVER fire. This silently stalls all TX."
    echo "  Fix: set CONFIG.CYCLIC=0 in axi_dmac IP config before synthesis."
    return
  fi
  echo "[OK] FLAGS=$flags — CYCLIC not set"

  # Check 3: IRQs unmasked?
  if [[ "$irq_mask_dec" -ne 0 ]]; then
    echo "[WARN] IRQ_MASK=$irq_mask — some TX DMA IRQs still masked."
    echo "  Driver may not have re-probed after FPGA reload."
  else
    echo "[OK] IRQ_MASK=0 — all IRQs unmasked"
  fi

  # Check 4: Transfers completing?
  if [[ "$xfer_done_dec" -eq 0 ]]; then
    echo "[WARN] XFER_DONE=0 — no TX DMA transfers completed yet."
    echo "  If interface is up and scan was attempted, this means data never left DDR."
    echo "  Check: is sdr.c calling dmaengine_submit()? Is CUR_SRC advancing?"
  else
    echo "[OK] XFER_DONE=$xfer_done — transfers completing"
  fi

  # Check 5: IRQ delivery?
  if [[ "$tx_irq_count" == "0" ]] && [[ "$xfer_done_dec" -ne 0 ]]; then
    echo "[FAIL] XFER_DONE>0 but IRQ count=0 — transfers complete but no interrupt reaches CPU."
    if [[ "$irq_pend_dec" -ne 0 ]] || [[ "$irq_src_dec" -ne 0 ]]; then
      echo "  IRQ_PEND=$irq_pend IRQ_SRC=$irq_src — IRQ fired in hardware but PLIC didn't deliver."
      echo "  Check: PLIC source 61 mapping in DTS, interrupt-parent, trigger type."
    else
      echo "  IRQ never fired in hardware. Check FPGA TX stream connection."
    fi
  elif [[ "$tx_irq_count" != "0" ]]; then
    echo "[OK] TX DMA IRQ count=$tx_irq_count — interrupts reaching CPU"
    echo "  TX DMA layer is healthy. Auth failure is above DMA — check mac80211/XPU/CSMA."
  fi

  echo
  echo "DMA sysfs stall counters:"
  for attr in tx_dma_stall_enter_count tx_dma_error_count tx_dma_timeout_count; do
    val="$(cat /sys/devices/platform/soc/soc:sdr/${attr} 2>/dev/null || \
           cat /sys/devices/platform/sdr/${attr} 2>/dev/null || \
           cat /sys/devices/platform/soc/sdr/${attr} 2>/dev/null || echo 'n/a')"
    printf "  %-35s %s\n" "${attr}:" "$val"
    if [[ "$val" != "0" ]] && [[ "$val" != "n/a" ]]; then
      echo "  ^^^ NONZERO — TX DMA is faulting. Packets may be dropped before radio."
    fi
  done
}

#==============================================================================
# Main
#==============================================================================
MODE="${1:-full}"
DURATION="${2:-20}"

case "$MODE" in
  snapshot)
    print_full_snapshot "SNAPSHOT"
    ;;
  monitor)
    run_monitor "$DURATION"
    ;;
  irqstep)
    run_irqstep "$DURATION"
    ;;
  decision)
    run_decision_tree
    ;;
  full)
    print_full_snapshot "INITIAL"
    run_monitor "$DURATION"
    run_irqstep 10
    print_full_snapshot "FINAL"
    ;;
  *)
    echo "Usage: $0 [snapshot|monitor|irqstep|decision|full] [duration_sec]"
    echo ""
    echo "  snapshot  — one-shot register dump of all 4 DMA instances + context"
    echo "  monitor   — per-second TX/RX DMA counters for <duration> seconds"
    echo "  irqstep   — before/after snapshot with <duration>s wait (trigger auth in between)"
    echo "  decision  — automated TX DMA health decision tree (checks 5 failure modes)"
    echo "  full      — snapshot + monitor + irqstep + final snapshot (default)"
    exit 1
    ;;
esac
