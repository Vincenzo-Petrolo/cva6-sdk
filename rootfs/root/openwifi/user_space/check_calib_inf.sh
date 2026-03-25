#!/usr/bin/env bash

#==============================================================================
# check_calib_inf.sh — Background AD9361 TX quadrature calibration monitor
#
# Usage: ./check_calib_inf.sh
# Runs calibration check in background; kills previous instance if running.
#
# SPDX-FileCopyrightText: 2026 EPFL-ESL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

set -euo pipefail
. "$(dirname "$0")/openwifi_common.sh"

# Guard against running twice — kill previous instance if still alive.
# NOTE: kill -0 only checks PID existence, not process identity.  On a
# long-running system PID reuse could theoretically hit an unrelated
# process.  Acceptable on a dedicated embedded board that reboots often.
if [[ -f /tmp/check_calib_inf.pid ]]; then
  old_pid=$(cat /tmp/check_calib_inf.pid)
  if kill -0 "$old_pid" 2>/dev/null; then
    kill "$old_pid" 2>/dev/null || true
    echo "Killed previous calibration checker (PID $old_pid)" >&2
  fi
fi

# AD9361 register 0x0A7: TX Quadrature Calibration status
AD9361_REG_TX_QUAD_CAL=0x0A7
AD9361_TX_QUAD_CAL_FAILED=0xFF      # all bits set = calibration failed
CALIB_POLL_INTERVAL_SEC=5

openwifi_cd_iio_device direct_reg_access
device_path=$(pwd)/

# Background calibration checker — set +e inside so transient sysfs
# errors don't kill the loop (it should keep retrying)
(
  set +e
  while true; do
    echo "$AD9361_REG_TX_QUAD_CAL" > "${device_path}direct_reg_access"
    status=$(cat "${device_path}direct_reg_access")
    if [[ "${status,,}" == "${AD9361_TX_QUAD_CAL_FAILED,,}" ]]; then
      echo "WARNING: Tx Quadrature Calibration failed." >&2
    fi
    sleep "$CALIB_POLL_INTERVAL_SEC"
  done
) &
echo $! > /tmp/check_calib_inf.pid
