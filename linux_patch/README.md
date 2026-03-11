# Linux Patch Provenance For OpenWiFi And AD9361

This folder carries the Theshire-side Linux patch stack applied by the `cva6-sdk` build flow.

For the OpenWiFi and AD9361 patch space, the maintenance goal is to minimize local drift and use the external `openwifi` repo as the canonical source wherever that is practical.

## Contents

- `0009-*`: refreshed AD9361 base import
- `0010-*`: refreshed OpenWiFi driver import
- `0011-*`: external `openwifi`-derived `ad9361.c` overlay
- `0012-*`: external `openwifi`-derived `ad9361_private.h` overlay
- `0013-*`: external `openwifi`-derived `ad9361_conv.c` overlay
- `0014-*`: external `openwifi`-derived `dma-axi-dmac.c` overlay

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

### `0009-iio-adc-add-AD9361-driver-from-ADI-adi-5.10.0.patch`

This patch now includes the AD9361 base/header adjustments needed by the current external `openwifi` ADI overlay, including:

- `<linux/mutex.h>` include in `ad9361.h`
- `PL_INTF_CLK` in `enum ad9361_clocks`
- `struct mutex lock` in `struct ad9361_rf_phy`

That refresh is what allows the current external `openwifi` `ad9361.c` overlay to apply locally without keeping a separate compatibility crumb.

### `0010-openwifi.patch`

This is the base OpenWiFi import into the Theshire kernel tree.

When this patch is refreshed from the current external `openwifi` source, it must include the current file set, including:

- `openwifi/driver/sdr_utils.c`

The maintained regeneration inputs are:

- `0010-openwifi.manifest.tsv`
- `util/regen_openwifi_patch.sh`

That script does not copy the full Linux tree. It stages only the path set owned by `0010` from the pristine Linux tarball baseline, overlays the refreshed canonical OpenWiFi files from `OPENWIFI_SRC`, regenerates the Linux glue hunks, and emits a new `0010-openwifi.patch`. Set `THS_OPENWIFI_SRC` in `source_toolchains.user.sh`, then run `source source_toolchains.sh` before using the default command.

For deterministic regeneration, the script does not copy the build-generated helper headers verbatim:

- `git_rev.h` is emitted from the external `openwifi` repo HEAD
- `pre_def.h` is emitted from the canonical OpenWiFi top-level defaults (`ENABLE_DEBUG`, `ENABLE_RX_SCAN_ALL_SLOTS`)

### `0011-ad9361.patch`

This patch is the local numbered form of the external `openwifi` ADI overlay `ad9361.c`.

### `0012-ad9361_private.patch`

This patch is the local numbered form of the external `openwifi` ADI overlay `ad9361_private.h`.

### `0013-ad9361_conv.patch`

This patch is the local numbered form of the external `openwifi` ADI overlay `ad9361_conv.c`.

### `0014-dma-axi-dmac.patch`

This patch is the local numbered form of the external `openwifi` ADI overlay `dma-axi-dmac.c`.

The carried `ow_rx_force_flag_last` knob remains present with its upstream OpenWiFi default (`false`). The current Theshire flow does not add a separate runtime override yet. Treat that default as the baseline until board validation proves that strict packet-boundary forcing is required on the Theshire RX path.

### AD9361 binding-doc diff

The external `openwifi` overlay also carries:

- `openwifi/patches/adi-linux-64/diffs/Documentation/devicetree/bindings/iio/adc/adi,ad9361.txt.patch`

That documentation diff is not part of the active local Theshire patch stack today because the current local Linux 5.10.7 kernel tree does not carry the target `adi,ad9361.txt` file in the same form as the external ADI tree.

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
