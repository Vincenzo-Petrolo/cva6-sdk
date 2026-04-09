#!/usr/bin/env bash
#==============================================================================
# csi_fuzzer_scan.sh — CSI coefficient sweep (4 scan modes)
#
# Usage: ./csi_fuzzer_scan.sh <1|2|3|4>
#   1 = scan tap1, 2 = scan tap2, 3 = tap1 after tap2, 4 = tap2 after tap1
#
# Author: Xianjun Jiao
# Author: Andreas T. Kristensen (ZCU104 port)
# SPDX-FileCopyrightText: 2021 UGent
# SPDX-FileCopyrightText: 2026 EPFL-TCL
# SPDX-License-Identifier: AGPL-3.0-or-later
#==============================================================================

# set -uo pipefail only (not -euo): scan tolerates individual csi_fuzzer.sh failures via || true
set -uo pipefail
. "$(dirname "$0")/openwifi_common.sh"

if [[ "$#" -lt 1 ]]; then
    echo "You must enter 1 argument: 1, 2, 3 or 4. For scan c1, c2, c2&c1 or c1&c2," >&2
    exit 1
fi

SCAN_OPTION=$1

# csi_fuzzer.sh args: c1_rot90_en c1_raw c2_rot90_en c2_raw
# Coefficient range: -64..63 (7-bit signed, offset-binary encoded)
#
# Options 1&2: single-tap scan (coeff=-64..63, one tap at a time)
#   NOTE: upstream had a spurious outer for-j loop where j was never used,
#   causing 128x redundant repetitions.  Removed in POSIX rewrite.
# Options 3&4: two-tap scan (c_outer and c_inner both -64..63)

if [[ "$SCAN_OPTION" == "1" ]]; then
    echo "Scan tap1:"
    for ((coeff = -64; coeff <= 63; coeff++)); do
        ./csi_fuzzer.sh 0 "$coeff" 0 0 || true
        sleep 0.01
    done
    for ((coeff = -64; coeff <= 63; coeff++)); do
        ./csi_fuzzer.sh 1 "$coeff" 0 0 || true
        sleep 0.01
    done
    exit 0
fi

if [[ "$SCAN_OPTION" == "2" ]]; then
    echo "Scan tap2:"
    for ((coeff = -64; coeff <= 63; coeff++)); do
        ./csi_fuzzer.sh 0 0 0 "$coeff" || true
        sleep 0.01
    done
    for ((coeff = -64; coeff <= 63; coeff++)); do
        ./csi_fuzzer.sh 0 0 1 "$coeff" || true
        sleep 0.01
    done
    exit 0
fi

if [[ "$SCAN_OPTION" == "3" ]]; then
    echo "Scan tap1 after tap2:"
    for ((c_outer = -64; c_outer <= 63; c_outer++)); do
        for ((c_inner = -64; c_inner <= 63; c_inner++)); do
            ./csi_fuzzer.sh 0 "$c_outer" 0 "$c_inner" || true
        done
        for ((c_inner = -64; c_inner <= 63; c_inner++)); do
            ./csi_fuzzer.sh 0 "$c_outer" 1 "$c_inner" || true
        done
    done
    for ((c_outer = -64; c_outer <= 63; c_outer++)); do
        for ((c_inner = -64; c_inner <= 63; c_inner++)); do
            ./csi_fuzzer.sh 1 "$c_outer" 0 "$c_inner" || true
        done
        for ((c_inner = -64; c_inner <= 63; c_inner++)); do
            ./csi_fuzzer.sh 1 "$c_outer" 1 "$c_inner" || true
        done
    done
    exit 0
fi

if [[ "$SCAN_OPTION" == "4" ]]; then
    echo "Scan tap2 after tap1:"
    for ((c_outer = -64; c_outer <= 63; c_outer++)); do
        for ((c_inner = -64; c_inner <= 63; c_inner++)); do
            ./csi_fuzzer.sh 0 "$c_inner" 0 "$c_outer" || true
        done
        for ((c_inner = -64; c_inner <= 63; c_inner++)); do
            ./csi_fuzzer.sh 1 "$c_inner" 0 "$c_outer" || true
        done
    done
    for ((c_outer = -64; c_outer <= 63; c_outer++)); do
        for ((c_inner = -64; c_inner <= 63; c_inner++)); do
            ./csi_fuzzer.sh 0 "$c_inner" 1 "$c_outer" || true
        done
        for ((c_inner = -64; c_inner <= 63; c_inner++)); do
            ./csi_fuzzer.sh 1 "$c_inner" 1 "$c_outer" || true
        done
    done
    exit 0
fi
