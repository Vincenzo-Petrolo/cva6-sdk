#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"

# RTL slv_reg57: TRX status word (RSSI, ch_idle, demod_ongoing, tx_ongoing)
# Source: driver/hw_def.h XPU_REG_TRX_STATUS_ADDR = (57*4)
XPU_REG_TRX_STATUS_IDX=57
RSSI_HALF_DB_MASK=2047              # 0x7FF — bits [10:0] of TRX_STATUS

rssi_raw=$(sdrctl dev "$OPENWIFI_IFACE" get reg xpu "$XPU_REG_TRX_STATUS_IDX")
echo "$rssi_raw"

# Extract last 8 hex chars (32-bit register word)
rssi_raw="${rssi_raw: -8}"
echo "$rssi_raw"

# Convert hex to decimal
rssi_raw_dec=$((16#${rssi_raw#0x}))
echo "$rssi_raw_dec"

# The low 11 bits are rssi_half_db (signed RSSI in half-dB units)
rssi_half_db=$((rssi_raw_dec & RSSI_HALF_DB_MASK))
echo "$rssi_half_db"
