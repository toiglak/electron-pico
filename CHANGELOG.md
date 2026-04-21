# CHANGELOG: Electron Pico Build Optimization

This document tracks changes and optimizations made to the Electron Pico build process.

## [Latest] - 2026-04-21

### Infrastructure Scaling
- **Runner Upgrade**: Switched from `macos-latest` to the high-capacity `macos-26-intel` runner.
- **RAM Pressure Mitigation**: Added `concurrent_links=1` to GN arguments via the workflow initialization.
- **Reasoning**: The ThinLTO linking stage is extremely memory-intensive. Doubling the available RAM and serializing the linkers ensures the build can complete without OOM crashes during the final link phase.

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
