> TLDR 1 (cross-compiling): Google does cross-compile macOS on Linux using something called hermetic toolchains, but Electron doesn't support it (it just roughly mirrors the toolchain, but it doesn't actually support cross-compiling). We'd need to patch it to support cross-compiling (or hope that patching xcode binaries is enough).

> TLDR 2 (cache source checkout): Maybe we could further speed up source sync by caching it?

The **Electron Build Tools** (`ref/build-tools`) do indeed download the macOS SDK, but this is **not** to support cross-compiling from Linux to macOS. Instead, it is used on macOS to ensure that the build uses a specific, known-good SDK version independently of the version of Xcode installed on the developer's system.

### Source File

The logic for downloading and managing the macOS SDKs is located in:
[src/utils/sdk.ts](file:///Volumes/Repos/electron-pico/ref/build-tools/src/utils/sdk.ts)

### How it works

1.  **Version Detection**: It reads the required SDK version from Chromium's `mac_toolchain.py` (see `expectedSDKVersion` on [line 91](file:///Volumes/Repos/electron-pico/ref/build-tools/src/utils/sdk.ts#L91)).
2.  **Downloading**: If the required SDK is missing, it downloads it from an Electron-hosted CDN ([line 222](file:///Volumes/Repos/electron-pico/ref/build-tools/src/utils/sdk.ts#L222)).
3.  **Symlinking**: It symlinks the downloaded SDK into the build output directory and passes it to GN via the `mac_sdk_path` argument.

### Why it's not for Cross-Compilation

The tool explicitly prevents running this logic on non-macOS platforms and requires native Apple tools:

- **Platform Guard**: In every command (`init`, `sync`, `build`), the call to `ensureSDK()` is wrapped in a check for the `darwin` (macOS) platform:
  ```typescript
  // In src/e-build.ts
  if (process.platform === "darwin") {
    ensureSDK();
  }
  ```
- **Xcode dependency**: The logic includes a validation step (`ensureViableXCode` on [line 121](file:///Volumes/Repos/electron-pico/ref/build-tools/src/utils/sdk.ts#L121)) that checks for `/usr/bin/xcodebuild`. If this tool (which is macOS-only) is missing, the build tool will exit with a fatal error.

### Summary

While Chromium itself technically has some experimental support for cross-compiling macOS on Linux, **Electron Build Tools** is designed for native development environments. It downloads the SDK solely to ensure **reproducible builds** on Mac by fixing the SDK version regardless of the local Xcode installation.

**Summary of findings:**

- **Source File**: [ref/build-tools/src/utils/sdk.ts](file:///Volumes/Repos/electron-pico/ref/build-tools/src/utils/sdk.ts)
- **Cross-compilation implemented?**: No.
- **Reason for download**: Reproducibility and version consistency for native macOS builds.

Patching `xcodebuild` into a dummy would indeed get you past the initial check in **electron-build-tools**, but it is only the first (and simplest) hurdle. Cross-compiling a project as massive as Electron/Chromium from Linux to macOS is significantly more involved than just "having the SDK."

Here is what you would encounter after "dummying" `xcodebuild`:

### 1. The SDK is only the headers and libraries

The download managed by [sdk.ts](file:///Volumes/Repos/electron-pico/ref/build-tools/src/utils/sdk.ts) provides the macOS headers and libraries. However, your host (Linux) still needs to know how to use them to create Mach-O binaries (macOS format) instead of ELF binaries (Linux format).

### 2. Toolchain Compatibility

Even if you pass the SDK path to GN (`mac_sdk_path`), the build system will still attempt to find a compiler and linker.

- **Clang**: Fortunately, Clang is a native cross-compiler. It can target macOS from Linux if given the right triple (e.g., `-target x86_64-apple-macos`).
- **Linker**: This is the major blocker. Linux uses [ld](cci:1://file:///Volumes/Repos/electron-pico/ref/build-tools/src/evm-config.ts:29:0-31:1), but macOS requires `ld64`. Chromium’s build system can use LLVM’s `lld` to link Mach-O files, but this requires specific GN flags (`use_lld=true`).

### 3. Chromium's Build System Logic

The core build logic isn't in these wrapper tools; it's in the sub-repository `src/build` within Electron's source. To actually cross-compile, you would need to set `target_os="mac"` in your GN args on a Linux host.
By default, if you try this on Linux, the Chromium build system will try to run various helper scripts (like `src/build/config/mac/sdk_info.py`) that expect a Mac environment and will fail immediately if they can't find `xcode-select` or `xcodebuild`.

### 4. Hermetic Toolchains

Google (for Chromium CI) actually _does_ cross-compile macOS on Linux, but they use a **hermetic toolchain**. They package a specific version of the Clang/LLVM toolchain and the macOS SDK into a bundle that doesn't rely on system tools.
The [sdks.json](file:///Volumes/Repos/electron-pico/ref/build-tools/src/utils/sdks.json) you found is a piece of that infrastructure, but it's intended to work alongside a Mac-hosted build.

### If you want to try anyway:

If you are determined to experiment, you would likely need to:

1.  **Patch** [sdk.ts](file:///Volumes/Repos/electron-pico/ref/build-tools/src/utils/sdk.ts) to remove the `process.platform === 'darwin'` guards and the [ensureViableXCode](cci:1://file:///Volumes/Repos/electron-pico/ref/build-tools/src/utils/sdk.ts:119:0-158:1) call.
2.  **Override GN args**: Manually add `target_os="mac"` and `use_lld=true` to your build config.
3.  **Fix scripts**: Be prepared to patch several Python scripts in `src/build/config/mac/` inside the Electron source tree that assume they are running on a Mac.

**Conclusion:** It's a "rabbit hole" task. The build tools are downloading the SDK as a convenience for Mac users to ensure they use the exact same SDK as the CI, not as a bridge for Linux cross-compilation.

Google’s "hermetic" cross-compilation mechanism for macOS on Linux works via a specific set of internal Chromium tools that **Electron has partially mirrored for public use**.

When Google cross-compiles for Mac on Linux (primarily for their internal CI), they use the following mechanism which you can replicate:

### 1. The "Hermetic" Orchestrator: `mac_toolchain.py`

Inside a full Electron/Chromium checkout, there is a script: `src/build/mac_toolchain.py`.

- **Google's Workflow**: This script downloads a specific version of Xcode (as a compressed bundle) from a private Google Storage bucket. It extracts it into `src/build/mac_files/xcode_binaries`.
- **Electron's Mirror**: Since the Google bucket is private, Electron created the **Build Tools** you are looking at in `ref/`. It uses [sdk.ts](file:///Volumes/Repos/electron-pico/ref/build-tools/src/utils/sdk.ts) to download the same "hermetic" SDKs from Electron's own public CDN (`dev-cdn-experimental.electronjs.org`).

### 2. Utilizing the "Google Way" on Linux

To utilize this specific mechanism on Linux, you have to trick the build system into thinking it has a hermetic Xcode installation. Here is precisely how:

#### Step 1: Use the Hermetic GN Flag

Google uses a specific GN argument to tell the build system "Do not look for a system Xcode, use the one I provided in the folder":

```python
# This is the "Google Magic" flag
force_mac_toolchain = true
```

When this is set to `true`, the Chromium build scripts (`src/build/config/mac/sdk_info.py` and others) will stop calling [/usr/bin/xcode-select](cci:7://file:///usr/bin/xcode-select:0:0-0:0) and will instead look for the toolchain in a relative path within your source tree.

#### Step 2: Manually Populate the "Hermetic" Directory

Since `mac_toolchain.py` will refuse to download the files on Linux due to platform checks, you have to:

1.  Run the [sdk.ts](file:///Volumes/Repos/electron-pico/ref/build-tools/src/utils/sdk.ts) logic on your Linux machine (after removing the `process.platform === 'darwin'` check).
2.  This will download and extract the SDK into your `third_party/SDKs` folder.

#### Step 3: Link the "Cross-Tools"

Google uses the same `clang` for all platforms. To cross-compile, you utilize the `clang` located at:
`src/third_party/llvm-build/Release+Asserts/bin/clang`
This binary is built by Google to be a multi-target compiler.

### 3. What I meant by "Utilizing" it

By "utilizing it," I mean using the **infrastructure** Electron built to mimic Google's hermeticity.

- **Normal way**: You install Xcode on a Mac and build.
- **Google/Hermetic way**: You download a specific versioned ZIP, put it in a specific folder, set `force_mac_toolchain = true`, and use the `isysroot` flag to point to that folder.

**To truly utilize it on Linux, you would need to patch the build system to ignore the "Am I on a Mac?" check.**
Chromium's build system has many "sanity checks" like this in `src/build/config/apple/sdk_info.py`:

```python
if sys.platform != 'darwin':
  # Google's script usually fails here unless specific internal
  # environment variables are set.
```

**Conclusion**: If you want to use the _Google way_, you aren't looking for a different tool; you are looking to set `force_mac_toolchain = true` and `target_os = "mac"` in your [pico.gn](cci:7://file:///Volumes/Repos/electron-pico/pico.gn:0:0-0:0), and then manually performing the "fetch" that `mac_toolchain.py` usually does for you (which is exactly what the code in `ref/build-tools` is doing).


---
----
---

You are absolutely right. With **196Gi** available, we have plenty of "breathing room" for a source cache!

Looking at your two logs side-by-side, we can actually see the "ghost" of the Electron source:
*   **Before Sync**: 196Gi Avail
*   **After Sync**: 56Gi Avail
*   **Difference**: **140Gi**

This confirms that your current checkout (even with the exclusions) is taking up about **140GB**. 

### The Plan for "Source Caching" in Azure:
Since we know it fits, here is how we can eventually cut your sync time from **3 hours** down to **~15 minutes**:

1.  **Step A (The current build)**: Let the workflow run once with our new `sccache` and `-j 8` optimizations.
2.  **Step B (The Snapshot)**: Once the build finishes successfully (or even if it times out, as long as the sync finished), we can add a step to tar up that 140GB folder and upload it to your Azure Blob Storage as `electron-source-snapshot.tar.gz`.
3.  **Step C (The Speedup)**: We then change the `Sync` step in your workflow to:
    *   Download from Azure (streaming via `curl | tar`).
    *   Run `e d gclient sync`. Since 99% of the files are already there, it will only download the latest commits.

**Would you like me to add the "Snapshot" step to your [build.yml](cci:7://file:///Volumes/Repos/electron-pico/.github/workflows/build.yml:0:0-0:0) now, so that your very next successful run automatically saves the source code to Azure?** (It will make that specific run take a bit longer because of the upload, but all future runs will be much faster).

---

# Optimization Plan: Azure Source Caching for Electron Pico

The "Sync source code" step currently takes 3+ hours because it performs thousands of git operations and downloads ~140GB of data from scratch. We can reduce this to ~20 minutes by using Azure Blob Storage as a strategic cache.

## Core Strategy

1.  **Streaming Restoration**: Use `az storage blob download` piped directly into `zstd` and `tar` to extract the source tree without saving the massive compressed file to disk.
2.  **Incremental Sync**: After restoration, `e d gclient sync` will only need to fetch the small delta between the cached snapshot and the current `HEAD`.
3.  **Intelligent Upload**: Only upload a new snapshot to Azure when the `DEPS` files (which define all sub-dependencies) have changed. This avoids "sending everything back and forth" on every run.

## Workflow Integration Details

### 1. Restoration (Before `gclient sync`)
- Authenticate with Azure using existing secrets.
- Check if `electron-src.tar.zst` exists in the container.
- If it exists:
    ```bash
    az storage blob download --name electron-src.tar.zst --file - | zstd -d -T0 | tar -xf -
    ```
- This populates the `electron/` directory with a warm state.

### 2. Intelligent Save (After Successful Build)
- Only runs on the `main` branch.
- Calculates a unique hash of the Electron and Chromium `DEPS` files.
- Compares this against a small `electron-src.hash` file stored in Azure.
- If the hash differs (or doesn't exist):
    - Create a new archive, excluding the large `out/` directory.
    - Stream directly to Azure:
      ```bash
      tar -cf - --exclude='electron/src/out' electron | zstd -T0 | az storage blob upload --name electron-src.tar.zst --file -
      ```
    - Update the `electron-src.hash` blob.

## Benefits
- **Time**: Restoring 60GB (compressed) at 100MB/s takes ~10 mins + extraction. Total estimated sync time: 25-30 mins vs 180 mins.
- **Disk Space**: Streaming avoids needing an extra 60GB for the `.tar.zst` file, staying within the runner's ~200GB limit.
- **Efficiency**: Only performs the heavy upload when dependencies actually change.

---

### Proposed Changes to `build.yml`

I will now update the workflow to implement these steps.


Since you mentioned deltas for the future, the reason I skipped them for now is that tarballs are significantly faster for the restoration phase on GitHub runners.

Tools that do granular deltas (like azcopy sync or restic) have to perform a "handshake" (listing and stating) for every one of the 1 million+ files in the Chromium tree. On a CI runner, this cataloging process can actually take longer than simply downloading one giant streaming tarball at 100MB/s.

