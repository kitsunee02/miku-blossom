# HsinOS Android 15 — Redmi 9A (blossom) CI

A device-specific, staged GitHub Actions build setup adapted from `kilib1k/crdroid-ice` for the HsinOS Android 15 manifest and the blossom local manifest.

## Source configuration

| Part | Source / revision |
|---|---|
| ROM manifest | `https://github.com/hsin-os/manifest.git` |
| ROM branch | `Moon_fox` |
| Android base | `android-15.0.0_r32` (AOSP build ID `BP1A.250505.005`) |
| Device tree | `kitsunee02/device_xiaomi_blossom`, `hsin` |
| Vendor blobs | `kitsunee02/proprietary_vendor_xiaomi_blossom` |
| MTK sepolicy | `Jayedkhan800/android_device_mediatek_sepolicy_vndr` |
| MTK HAL | `AsTechpro20/android_hardware_mediatek` |
| MIUI camera | `HaiKito18/vendor_xiaomi_miuicamera` |
| Via Browser | `HaiKito18/ViaBrowser` |
| Kernel/prebuilt bundle | `crdroidandroid/android_kernel_xiaomi_blossom` |

The local manifest is stored as `manifests/15.0/hsin.xml`, not `blossom.xml`, because Hsin's `vendor/hsin/build/tools/roomservice.py` looks specifically for `.repo/local_manifests/hsin.xml` when resolving a device and its `hsin.dependencies`.

The Hsin manifest's `default.xml` already includes `snippets/remove.xml`, `snippets/miku.xml`, `snippets/lineage.xml`, and `snippets/hsin.xml`. The CI therefore adds the blossom local manifest plus its CI-only `remove.xml`; it does not duplicate the ROM's snippet files.

## Device tree ownership

The CI does not generate, replace, or adapt any device-tree product files. The product makefiles, `AndroidProducts.mk`, lunch choices, and Hsin-specific device configuration must come from the device tree synced by `manifests/15.0/hsin.xml`.

The device tree is synced from the `hsin` branch. It exports `hsin_blossom-user`, `hsin_blossom-userdebug`, and `hsin_blossom-eng`; the CI defaults to `hsin_blossom-userdebug`. Change it in **Actions → Build HsinOS Android 15 (blossom) → Run workflow** to exactly match the lunch combo provided by your device tree. The CI will use that tree as checked out; it will not overlay a CI-made product definition on top of it.

## Build

1. Open **Actions → Build HsinOS Android 15 (blossom) → Run workflow**.
2. Defaults:
   - Hsin manifest branch: `Moon_fox`
   - Lunch: `hsin_blossom-userdebug`
   - Build target: `hsin`
3. The workflow syncs sources, resolves Hsin roomservice dependencies, re-syncs the expanded manifest, pins every project revision, applies optional CI patches/overrides, runs the device `vendorsetup.sh` hooks, then builds in up to eight stages.

Use the lunch input to select a combo actually exported by your device tree.

## Workflows

- `build.yml`: full staged ROM build, output artifact and GitHub Release.
- `stage.yml`: reusable stage; restores `out/`, syncs the pinned revisions, builds until its time budget expires, and hands `out/` to the next stage.
- `check.yml`: sync, apply patches, lunch and run `m nothing` without compiling the full ROM.
- `diag.yml`: report source and `.repo` disk usage.

## Why the stages work

Each GitHub-hosted runner is temporary. A later stage re-syncs the exact commits recorded in `pinned.xml`, restores the previous `out/`, sets source mtimes to a fixed old timestamp, then continues the same make target. The `out/` archive is compressed with zstd and split into 1.9 GB chunks before artifact upload.

`KEEP_GIT` defaults to false to save disk, matching the original project's strategy. Enable it in the workflow input if Hsin or device build steps need git object access; that uses considerably more disk.

## Device hooks and packages

The CI installs `patchelf` and sources `build/envsetup.sh` before pruning `.repo` objects so device `vendorsetup.sh` hooks can run while the repository metadata is still available. Keep any device-specific patch scripts and required host tools in your device tree; this CI does not edit those files.

The collector looks for the final `*.zip` produced by Hsin's `m hsin` target (whose make rule renames the OTA package to `$(PROD_VERSION).zip`) and also collects selected images and checksums.

## Private interactive terminal (optional)

The build and configuration-check workflows can expose a temporary SSH terminal on the runner through your private Tailscale network. It is disabled by default. It does not use the public tmate relay.

### One-time setup

1. In your Tailscale admin console, create the `tag:ci` tag.
2. Create a Tailscale OAuth client restricted to `tag:ci`, with **Devices: Core: Write** and **Keys: Auth Keys: Write** permissions. Store the client ID and secret only in GitHub Actions secrets.
3. Add a Tailscale access grant allowing your own Tailscale identity to reach `tag:ci` on **TCP port 22 only**. Do not grant general access to the whole tailnet just for this workflow.
4. On your computer, create a separate SSH key pair:

   ```bash
   ssh-keygen -t ed25519 -a 64 -f ~/.ssh/miku-blossom-ci -C miku-blossom-ci
   ```

5. In **GitHub → miku-blossom → Settings → Secrets and variables → Actions → New repository secret**, add:

   | Secret name | Value |
   |---|---|
   | `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client ID |
   | `TS_OAUTH_SECRET` | Tailscale OAuth client secret |
   | `CI_SSH_PUBLIC_KEY` | Contents of `~/.ssh/miku-blossom-ci.pub` |

   Never upload the private key (`~/.ssh/miku-blossom-ci` without `.pub`) to GitHub.

### Start a terminal

1. Start **Build HsinOS Android 15 (blossom)** or **Check HsinOS configuration (blossom)**.
2. Set **Enable private SSH terminal** to `true`.
3. Open the running stage job's **Summary**. The **Private interactive terminal** section shows its temporary Tailscale IP.
4. Make sure your computer is connected to the same tailnet, then connect:

   ```bash
   ssh -i ~/.ssh/miku-blossom-ci ci-debug@100.x.y.z
   ```

   Replace `100.x.y.z` with the address shown in that stage's Summary.

On Arch Linux, install and start Tailscale once with `sudo pacman -S tailscale`, `sudo systemctl enable --now tailscaled`, and `sudo tailscale up`.

The SSH account is intentionally separate from the Actions runner account: it has no sudo access and is not a member of the runner group. It can inspect world-readable workspace files but is not granted the runner account's group permissions. The SSH daemon listens only on the private Tailscale IPv4 address, with public-key authentication only.

Each build stage gets a fresh runner and a different temporary Tailscale address. The terminal stops when that stage ends. Keep the debug option off for normal runs. While compilation is running, use the terminal for inspection; do not manually change source files, touch build outputs, kill build processes, or run cleanup commands in the shared workspace.

## Important limitations

- The workflows and scripts are adapted from the current public `kilib1k/crdroid-ice` builder and Hsin's public build files. They have **not** been executed against a full Android source checkout, so a successful ROM build is not guaranteed until the `check.yml` workflow passes.
- The selected lunch combo must exist in the device tree. The CI deliberately does not supply or modify device product definitions.
- The workflow uses GitHub-hosted Ubuntu 24.04 runners and staged artifacts. Large source/output artifacts can hit runner disk, job-duration, or artifact-storage limits. A self-hosted runner with ample SSD space and RAM may be more reliable.
- Do not treat a successful `m nothing` check as proof that the ROM will boot. Test the generated ZIP carefully and keep backups of device-specific partitions.
