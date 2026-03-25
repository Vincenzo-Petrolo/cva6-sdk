#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"

home_dir=$(pwd)

set -x
openwifi_cd_sdr_sysfs

cat "${OPENWIFI_DATA_DIR}/iq_single_carrier_1000000Hz_512.bin" > tx_intf_iq_data
if command -v hexdump >/dev/null 2>&1; then
  hexdump -C tx_intf_iq_data | head -n 16 || true
elif command -v xxd >/dev/null 2>&1; then
  xxd -g 1 -l 256 tx_intf_iq_data
else
  echo "WARNING: hexdump/xxd not found; skipping binary readback preview"
fi

cd "$home_dir"
