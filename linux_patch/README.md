# Linux Patch Provenance For OpenWiFi And AD9361

This folder carries the Theshire-side Linux patch stack applied by the `cva6-sdk` build flow.

For the OpenWiFi and AD9361 patch space, the maintenance goal is to minimize local drift and use the external `openwifi` repo as the canonical source wherever that is practical.

## Contents

- `0009-adi-iio.patch`: ADI IIO drivers (AD9361 RF transceiver + cf_axi_adc HDL core driver). Imported from openwifi's patched `adi-linux-64` tree with vanilla-5.10.7 compatibility fixups. Regenerated via `util/regen_adi_iio_patch.sh`.
- `0010-openwifi.patch`: OpenWiFi driver import (sdr, tx_intf, rx_intf, xpu, etc.). Regenerated via `util/regen_openwifi_patch.sh`.
- `0011-dma-axi-dmac.patch`: ADI axi-dmac DMA driver with cyclic S2MM fixes for OpenWiFi RX + Kconfig RISCV + `of_reserved_mem_device_init` for CVA6 PMA NC DMA pool. Merged from former 0012 (Kconfig RISCV). Regenerated via `util/regen_dma_patch.sh`.
- `0012-gpio-mmio-opentitan.patch`: GPIO MMIO driver for OpenTitan. (Renumbered from 0013.)
- `0013-of-reserved-mem-debug.patch`: Downgrade `of_reserved_mem` assignment log from `dev_info` to `dev_dbg`.
- `0014-dma-coherent-memremap-wb.patch`: Change `MEMREMAP_WC` to `MEMREMAP_WB` in `dma_init_coherent_memory()` for CVA6 PMA NC region where LLC provides coherency.
- `0015-dma-axi-dmac-direct-theshire-nc-pool.patch`: Direct NC pool declaration via `dma_declare_coherent_memory()` on Theshire/CVA6, bypassing DTS `memory-region` phandle path. Gated by `of_machine_is_compatible("eth,cheshire-dev")`.
- The 3 openwifi-sourced patches (0009-0011) have regen scripts. `util/regen_all_patches.sh` regenerates all of them. Patches 0013-0015 are hand-maintained Theshire-local patches.

## Canonical external sources

For the AD9361 and DMAC patch space, the canonical reference is the external `openwifi` ADI overlay, not `openwifi/driver/*.c`:

- `openwifi/patches/adi-linux-64/files/drivers/iio/adc/ad9361_conv.c`
- `openwifi/patches/adi-linux-64/files/drivers/iio/adc/ad9361_private.h`
- `openwifi/patches/adi-linux-64/files/drivers/iio/adc/ad9361.c`
- `openwifi/patches/adi-linux-64/files/drivers/dma/dma-axi-dmac.c`

## Maintenance rule

Default direction:

- refresh from external `openwifi` first
- keep Theshire-local deltas only when there is a proven Theshire-specific reason

Valid reasons for a Theshire-local residual delta include:

- RISC-V or `cva6-sdk` integration specifics
- kernel-base mismatch between the Theshire AD9361 import and the newer external `openwifi` overlay
- a proven Theshire-only hardware or DTS requirement

Stale local divergence is not a valid reason.

## Patch policy

For the OpenWiFi/AD9361/DMAC patch space in this folder:

- external `openwifi` is the canonical source for the ADI overlay content
- this folder is the Theshire transport format for that content, not an independent source of truth
- do not preserve old numbered patch boundaries just because they already exist
- do not split one canonical external file into multiple local micro-patches unless a real Theshire-only reason forces that split
- do not hand-write large patch bodies
- always edit real source files first, then generate the local `.patch` files from those source edits

The intended maintenance hierarchy is:

1. refresh or inspect the canonical source in external `openwifi`
2. decide whether Theshire can take it directly
3. if yes, regenerate the corresponding numbered Theshire patch from that canonical source
4. if no, isolate the exact Theshire-specific residual and keep only that residual locally

The intended local patch hierarchy is:

1. refreshed base imports (`0009`, `0010`)
2. canonical ADI-kernel artifact patches copied from external `openwifi`
3. only after that, explicit Theshire-only residual patches

## Target patch structure

The external `openwifi` repo does not maintain this ADI kernel patch space as many tiny historical numbered patches. It maintains one `adi-linux-64` patch namespace with:

- 4 full-file overlays
- 1 small documentation diff

Those canonical artifacts are:

- `drivers/iio/adc/ad9361.c`
- `drivers/iio/adc/ad9361_private.h`
- `drivers/iio/adc/ad9361_conv.c`
- `drivers/dma/dma-axi-dmac.c`
- `Documentation/devicetree/bindings/iio/adc/adi,ad9361.txt.patch`

Theshire cannot consume that external directory layout directly with the current Buildroot kernel-patch setting because `BR2_LINUX_KERNEL_PATCH="../linux_patch/"` applies numbered `*.patch` files from this local folder.

So the correct Theshire-equivalent maintenance model is:

- keep the external `openwifi` ADI overlay as canonical source
- represent that same canonical artifact set as numbered Theshire kernel patches
- add further Theshire-local patches only when a real Theshire-specific residual delta remains

In other words, the goal is not to preserve the old `0015` / `0016` / `0017` split. The goal is to make the Theshire patch inventory mirror the same logical patch units that external `openwifi` already uses.

## Current stack

### `0009-adi-iio.patch`

ADI IIO drivers: AD9361 RF transceiver + cf_axi_adc AXI ADC/DAC HDL core driver.

**Source**: openwifi's patched `adi-linux-64` working tree (ADI upstream `2022_R2` branch + openwifi overlay from `patches/adi-linux-64/files/`).

**Regeneration**: `source source_toolchains.sh && bash util/regen_adi_iio_patch.sh`

The script copies files from the openwifi working tree, applies vanilla-5.10.7 compatibility fixups (IIO_CHAN_INFO_CALIBPHASE removal, DMA ring buffer stubbing, .read_label removal, IIO_VAL_INT_64 replacement, ADI_AXI_REG_ID guard), and diffs against the vanilla Kconfig/Makefile.

**Files included**: ad9361.c, ad9361_conv.c, ad9361_private.h, ad9361.h, ad9361_regs.h, ad9361_ext_band_ctrl.c, cf_axi_adc_core.c, cf_axi_adc.h, Kconfig, Makefile, dt-bindings headers, jesd204 headers, clkscale.h.

### `0010-openwifi.patch`

OpenWiFi driver import (sdr, tx_intf, rx_intf, xpu, openofdm_tx/rx, side_ch).

**Regeneration**: `source source_toolchains.sh && bash util/regen_openwifi_patch.sh`

Uses `0010-openwifi.manifest.tsv` as the import manifest. `git_rev.h` and `pre_def.h` are generated deterministically from the openwifi repo state.

### `0011-dma-axi-dmac.patch`

ADI axi-dmac DMA driver with OpenWiFi cyclic S2MM fixes + Kconfig RISCV +
`of_reserved_mem_device_init`/`release` for CVA6 PMA NC DMA pool binding.

**Merged from former 0012** (Kconfig RISCV glue). The Kconfig one-liner
(`|| RISCV` on AXI_DMAC depends) is now applied inline by the regen script.

**`of_reserved_mem_device_init()`**: Binds the DMA device to a DTS
`reserved-memory` pool if present (`memory-region` property). On CVA6/Theshire,
this directs `dma_alloc_coherent()` to allocate from the PMA non-cacheable
region, eliminating the need for FENCE.T L1 cache invalidation. On ARM/Zynq
(no `memory-region` in DTS), returns `-ENODEV` — no behavioral change.

**`ow_rx_force_flag_last` = REQUIRED (compiled-in default: `true`).**
`S80openwifi` also writes `Y` to the sysfs parameter as a safety net.
Without FLAG_LAST, FPGA TLAST triggers abort/consume cascade in ADI DMAC
data_mover.v → ~63 bogus completions per packet → IRQ storm. On CVA6
(100 MHz), this manifests as elevated `rx_dma_cb_full_count` (DMA callback
stall counter) rather than the full system hang seen on ARM. Root cause
confirmed on openwifi ARM (commit `68475b3`, 2026-03-26); suspected on CVA6
RISC-V — pending on-board verification.

**Regeneration**: `source source_toolchains.sh && bash util/regen_dma_patch.sh`

Canonical source: `openwifi/patches/adi-linux-64/files/drivers/dma/dma-axi-dmac.c`

### `0012-gpio-mmio-opentitan.patch`

GPIO MMIO driver for OpenTitan SPI GPIO controller. (Renumbered from 0013.)

## Future update workflow

When updating this OpenWiFi/ADI patch space in the future, use this order:

1. Check the current external canonical artifacts first:
   - `openwifi/patches/adi-linux-64/files/drivers/iio/adc/ad9361.c`
   - `openwifi/patches/adi-linux-64/files/drivers/iio/adc/ad9361_private.h`
   - `openwifi/patches/adi-linux-64/files/drivers/iio/adc/ad9361_conv.c`
   - `openwifi/patches/adi-linux-64/files/drivers/dma/dma-axi-dmac.c`
   - `openwifi/patches/adi-linux-64/diffs/Documentation/devicetree/bindings/iio/adc/adi,ad9361.txt.patch`
2. Check whether the current Theshire base imports still support taking those artifacts directly:
   - `0009-*` for AD9361 base/header compatibility
   - `0010-*` for OpenWiFi driver import compatibility
3. Refresh `0009` first if the external AD9361 overlay now depends on newer base/header infrastructure.
4. Refresh `0010` next so old OpenWiFi follow-on crumbs do not stay alive unnecessarily.
5. Regenerate the numbered Theshire patches so they mirror the external canonical artifact boundaries.
6. Only after that, decide whether any extra Theshire-local residual patch is still needed.
7. Rebuild and validate the kernel path after the patch-stack rewrite.

Current local note:

- the active local stack already mirrors the 4 canonical external file overlays
- the external AD9361 binding-doc diff remains a reference item rather than an active local patch because the target file is absent in the current local kernel base

## How to update the local numbered patches

Because this repo uses Buildroot's `BR2_LINUX_KERNEL_PATCH="../linux_patch/"` flow, the canonical external overlay artifacts have to be represented here as numbered `.patch` files.

The expected method is:

- apply the intended source change to a real source file first
- generate the local `.patch` from the real file diff
- do not manually compose large unified diffs

For the OpenWiFi/ADI alignment work, that usually means one of these patterns:

- base-import refresh:
  - compare the current Theshire imported kernel file against the newer desired source file
  - generate one numbered patch for that file replacement/update
- external-overlay mirroring:
  - compare the current Theshire kernel-tree file against the canonical external `openwifi` file
  - generate one numbered patch per canonical external artifact
- Theshire-only residual:
  - once the canonical external content is mirrored, generate one additional local patch for the residual delta only

Patch-generation rule:

- use git-style diff generation from real source files
- do not hand-edit hunk headers, offsets, or line counts

## Decision rule before adding a new local patch

Before adding any new numbered patch in this area, answer these questions in order:

1. Does the needed change already exist in external `openwifi`?
2. If yes, why is Theshire not taking it directly?
3. Is the reason a real Theshire-specific constraint, or just stale local drift?
4. Can the constraint be solved by refreshing `0009` or `0010` instead of adding another residual patch?

If the answer to question 3 is "stale local drift", do not add the patch. Refresh from canonical source instead.
