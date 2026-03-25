#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"

# drv_xpu index 0 = LBT RSSI threshold (dBm magnitude, negated internally)
# Source: driver/sdr.h DRV_XPU_REG_IDX_LBT_TH = 0
DRV_XPU_REG_IDX_LBT_TH=0

set -x
if [[ -n "${1:-}" ]]; then
  sdrctl dev "$OPENWIFI_IFACE" set reg drv_xpu "$DRV_XPU_REG_IDX_LBT_TH" "$1"
fi

# show current value
sdrctl dev "$OPENWIFI_IFACE" get reg drv_xpu "$DRV_XPU_REG_IDX_LBT_TH"
set +x
