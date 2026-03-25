#!/usr/bin/env bash

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"
home_dir=$(pwd)

# CSMA feature index for XPU_REG_FORCE_IDLE_MISC (idx_from_msb=1 → bit 30)
CSMA_IDX_DIFS_DISABLE=1

openwifi_cd_sdr_sysfs

set -x
if [[ -n "${1:-}" ]]; then
  echo "${CSMA_IDX_DIFS_DISABLE}${1}" > csma_cfg0
fi

# show
cat csma_cfg0
set +x

cd "$home_dir"
