# CHANGELOG: Electron Pico Build Optimization

This document tracks changes and optimizations made to the Electron Pico build process.

## [Latest] - 2026-04-22

### GN Configuration Fixes
- **Rust Dependency**: Set `enable_rust = true`. Chromium 130+ (and recent toolchains) has made Rust a mandatory dependency for core libraries like `base`, and disabling it now triggers assertion failures.
- **Mac Compatibility**: Removed `enable_resource_allowlist_generation = true`. This flag is explicitly unsupported on macOS and causes GN to fail during the generation phase.
- **Stability Warnings**: Added cautionary notes to `pico.gn` regarding high-risk "minimalist" flags like `v8_enable_i18n_support = false`.

### Infrastructure & CI Resiliency
- **Source Caching**: Implemented a streaming Azure Blob Storage cache for the 140GB source tree. This will reduce sync times from ~3 hours to ~15 minutes after the first successful run.
- **Sync Reliability**:
  - Added a **5x retry loop** for `gclient sync` to handle transient network hangs (Error 128).
  - Reduced sync parallelism to **`-j 4`** to prevent connection rate-limiting on Intel Mac runners.
  - Increased `http.postBuffer` and `deltaBaseCacheLimit` for massive Git object transfers.
- **Dependency Fix**: Added explicit Azure CLI (`az`) installation via Homebrew to the runner environment.

### Build Target
- **Stable Tracking**: Shifted the default build target from `main` (development) to **`41-x-y`** (latest stable Electron release).
- **Variable Integration**: Fixed a bug where the `ELECTRON_BRANCH` variable was defined but unused; it is now correctly applied to both initialization and source synchronization.
- **Sync Optimization**: Throttled `gclient sync` to **`-j 4`** to prevent network connection drops on Intel runners, and removed the redundant `--force` flag.
- **Compiler Cache**: Integrated `sccache` with an **Azure Blob Storage** backend to support incremental builds across CI time-outs.


- **RAM Pressure Mitigation**: Serialized linking is now handled natively by ThinLTO logic rather than manual GN overrides.



---

## [2026-04-19]

### Hardened Resource Management
- **Reduced Parallelism**: Limited `gclient sync` to `-j 4`.
- **Disabled Git Auto-GC**: Set `git config --global gc.auto 0`.
- **Cleanup**: Added `--delete_unversioned_trees` to the sync command.
- **Reasoning**: Fixed "Lost communication with server" errors. These were caused by OOM (Out-of-Memory) starvation on 14GB RAM macOS runners when `gclient` attempted to run too many parallel git fetches and background GC processes.

---

## [Previous Optimizations]

### 1. Disk Space Management
- **Surgical Xcode Cleanup**: Avoids "scorched earth" deletions that could break the build. It identifies the active Xcode using `xcode-select -p` and only removes alternative versions.
- **ARM64 Specifics**: Added cleanup for `/opt/homebrew` and other M1-specific paths.
- **Aggressive Purging**: Explicitly removes large unused frameworks (Mono, Xamarin, Android SDKs) and the `obj/` directory immediately after the build to free ~30GB for packaging.

### 2. Hardened `gclient` Sync
- **Test Data Exclusion**: Uses a custom `.gclient` configuration with `custom_deps` to skip downloading multi-gigabyte test folders (e.g., `blink/web_tests`, `v8/test`). This saves bandwidth and avoids out-of-disk errors.
- **Correct CLI Commands**: Corrected the invalid `dtools` command to the official `e d` (alias for `depot-tools`).
- **YAML Robustness**: Uses `printf` to generate the `.gclient` file, avoiding Python dependencies and YAML indentation syntax errors.
- **Target OS Filter**: Added `target_os_only = True` to the `.gclient` config. This is a massive space saver as it forces `gclient` to ignore all non-macOS dependencies.

### 3. Sync Stability & Fetch Errors
- **Fixing Status 128**: Removed `--shallow` and `--no-history` from the sync command. These flags often cause fatal errors when fetching specific Chromium versions that are not at the tip of a branch.
- **Disabling Git Cache**: Explicitly set `GIT_CACHE_PATH=""`. This prevents `gclient` from trying to create a 16GB+ bare-repo cache, which is redundant on ephemeral CI runners and quickly exhausts disk space.
- **Git Hardening**: Increased `http.postBuffer` and disabled `gc.auto` to prevent silent hangs during large checkouts.

### 4. Build Configuration
- **Consistency**: Fixed the mismatch where `build-tools` used default out-dirs while the workflow expected `pico-release`. All steps now use `-o ${{ env.GN_OUT_DIR }}`.
- **Arm64 Robustness**: Explicitly targets `--target-cpu arm64` and installs Rosetta 2 as recommended by Electron documentation.

## GN Argument Refinement (`pico.gn`)
- **Extreme Size Reduction**: Added `v8_enable_webassembly = false` and `enable_cdm = false` to further strip the binary.
- **Cleanup**: Removed duplicate GN arguments and added `use_viz_debugger = false`.
- **Symbol Stripping**: Verified `symbol_level = 0` and `optimize_for_size = true` are correctly configured for minimum footprint.

---

## Important Gotchas
- **Shallow Clone Sensitivity**: Avoid `--shallow` on specific version tags in Chromium/Electron DEPS, as Google's mirrors often reject shallow fetches for non-tip references.
- **Git Cache Conflict**: Never enable `GIT_CACHE_PATH` on standard GitHub macOS runners; it will almost certainly exceed the 14GB free space limit.
