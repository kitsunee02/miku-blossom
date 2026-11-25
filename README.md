# HsinOS Android 15 — Redmi 9A (blossom) CI

A device-specific, staged GitHub Actions build setup adapted from `kilib1k/crdroid-ice` for the HsinOS Android 15 manifest and the supplied blossom local manifest.

## Source configuration

| Part | Source / revision |
|---|---|
| ROM manifest | `https://github.com/hsin-os/manifest.git` |
| ROM branch | `Moon_fox` |
| Android base | `android-15.0.0_r32` (AOSP build ID `BP1A.250505.005`) |
| Device tree | `kitsunee02/device_xiaomi_blossom`, `lineage-22.2` |
| Vendor blobs | `kitsunee02/proprietary_vendor_xiaomi_blossom`, `lineage-22.2` |
| MTK sepolicy | `Jayedkhan800/android_device_mediatek_sepolicy_vndr`, `lineage-22` |
| MTK HAL | `AsTechpro20/android_hardware_mediatek`, `lineage-22.2` |
| MIUI camera | `HaiKito18/vendor_xiaomi_miuicamera`, `main` |
| Via Browser | `HaiKito18/ViaBrowser`, `main` |
| Kernel/prebuilt bundle | `crdroidandroid/android_kernel_xiaomi_blossom`, `16.0` |

The local manifest is stored as `manifests/15.0/hsin.xml`, not `blossom.xml`, because Hsin's `vendor/hsin/build/tools/roomservice.py` looks specifically for `.repo/local_manifests/hsin.xml` when resolving a device and its `hsin.dependencies`.

The Hsin manifest's `default.xml` already includes `snippets/remove.xml`, `snippets/miku.xml`, `snippets/lineage.xml`, and `snippets/hsin.xml`. The CI therefore adds only the blossom manifest plus a small CI-only `remove.xml`; it does not duplicate the ROM's snippet files.

## Hsin product adapter

The public `lineage-22.2` blossom tree currently exposes `lineage_blossom.mk`, not `hsin_blossom.mk`, and its Lineage product inherits `vendor/lineage/config/common_full_phone.mk`. That vendor/lineage common product is not part of the supplied Hsin manifest.

To bridge that specific gap, `overrides/15.0/device/xiaomi/blossom/` supplies:

- `hsin_blossom.mk`, based on the current `lineage_blossom.mk` device/product settings, but inheriting `vendor/hsin/build/product/hsin_product.mk` instead of `vendor/lineage/config/common_full_phone.mk`.
- `AndroidProducts.mk`, registering the Hsin product and `bp1a` Android 15 lunch combinations.

These are CI-side overrides; they do not modify your GitHub device-tree repository. Review them alongside your device tree if you change its product configuration.

## Build

1. Push this directory's contents to a new GitHub repository.
2. Open **Actions → Build HsinOS Android 15 (blossom) → Run workflow**.
3. Defaults:
   - Hsin manifest branch: `Moon_fox`
   - Lunch: `hsin_blossom-bp1a-userdebug`
   - Build target: `hsin`
4. The workflow syncs sources, resolves Hsin roomservice dependencies, pins every project revision, applies the product overlay and device `vendorsetup.sh` hooks, then builds in up to eight stages.

The `bp1a` release selection corresponds to the supplied AOSP tag's build ID `BP1A.250505.005`. Change the workflow lunch input if your device/product branch uses another release configuration.

## Workflows

- `build.yml`: full staged ROM build, output artifact and GitHub Release.
- `stage.yml`: reusable stage; restores `out/`, syncs the pinned revisions, builds until its time budget expires, and hands `out/` to the next stage.
- `check.yml`: sync, apply patches, lunch and run `m nothing` without compiling the full ROM.
- `diag.yml`: report source and `.repo` disk usage.

## Why the stages work

Each GitHub-hosted runner is temporary. A later stage re-syncs the exact commits recorded in `pinned.xml`, restores the previous `out/`, sets source mtimes to a fixed old timestamp, then continues the same make target. The `out/` archive is compressed with zstd and split into 1.9 GB chunks before artifact upload.

`KEEP_GIT` defaults to false to save disk, matching the original project's strategy. Enable it in the workflow input if Hsin or device build steps need git object access; that uses considerably more disk.

## Device hooks and packages

The supplied blossom `vendorsetup.sh` invokes `patch_camera.sh` and `applyPatches.sh`. The CI installs `patchelf` and sources `build/envsetup.sh` before pruning `.repo` objects so those device patches can run. The camera patch is idempotent, and `applyPatches.sh` uses its `TMP_PATCHES` marker.

The collector looks for the final `*.zip` produced by Hsin's `m hsin` target (whose make rule renames the OTA package to `$(PROD_VERSION).zip`) and also collects selected images and checksums.

## Important limitations

- This is a CI configuration assembled from the supplied archives and the current public files on the referenced branches. It has **not** been executed against a full Android source checkout, and a successful ROM build is not guaranteed until the `check.yml` workflow passes.
- The product adapter is a best-effort conversion from the public Lineage blossom product to Hsin's product layout. If your local device tree has further Hsin-specific changes, update the override to match them.
- The workflow uses GitHub-hosted Ubuntu 24.04 runners and staged artifacts. Large source/output artifacts can hit runner disk, job-duration, or artifact-storage limits. A self-hosted runner with ample SSD space and RAM may be more reliable.
- Do not treat a successful `m nothing` check as proof that the ROM will boot. Test the generated ZIP carefully and keep backups of device-specific partitions.
