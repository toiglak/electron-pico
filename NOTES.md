# electron-pico 🔬

**An extreme minimal Electron distribution for macOS.**

This project builds a stripped-down Electron binary with ~80+ features disabled. The output is a ZIP file formatted specifically for use with [electron-builder](https://www.electron.build/)'s [`electronDist`](https://www.electron.build/configuration/configuration#electrondist) setting.

## Target: electronDist

The CI workflow produces a zip named using the required pattern:
`electron-v${version}-darwin-arm64.zip`

You can use the output of this build in your app's `electron-builder` config:

```json
{
  "electronDist": "./path/to/extracted/artifacts"
}
```

## What's Disabled?

| Category | Features Removed |
|----------|-----------------|
| **Media** | Proprietary codecs, HLS, Widevine, media remoting, libvpx, speech recognition |
| **Network** | Safe Browsing, captive portal detection, mDNS, service discovery, reporting, tracing |
| **System** | Message center, background mode, identity client, offline pages, plugins |
| **UI** | PDF viewer, Extensions, Printing, Spellcheck, VR/XR, WebRTC, Vulkan, WebGPU |
| **Optimization**| `optimize_for_size = true`, ThinLTO, `symbol_level = 0`, no debug tables |

## Building

This project is designed to run on **GitHub Actions CI** with a macOS runner.

1.  **Push** this repo to GitHub.
2.  **Actions**: The workflow will run for up to 6 hours.
3.  **Artifacts**: Download the ZIP from the workflow run.

### Local Initialization (Configuration Only)

If you want to view the configuration locally:
```bash
npx @electron/build-tools init pico-release -i release --root ./electron --remote-build none --use-https
```

## Project Structure

- `pico.gn`: The GN args file containing the feature deny list.
- `.github/workflows/build.yml`: The macOS build pipeline that handles source sync, patching, and ZIP packaging.

## Requirements

- **CI**: Requires a GitHub account with enough minutes (Private repos) or a Public repo. 
- **Runner**: Uses `macos-latest` (Apple Silicon) by default.

## License

MIT
