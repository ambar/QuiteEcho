# Sparkle Integration

In-app update support via [Sparkle](https://github.com/sparkle-project/Sparkle) (v2.9.1). Replaces the previous browser-redirect approach with native download, install, and restart — all within the app.

## Architecture

Sparkle's `SPUStandardUpdaterController` handles the entire update lifecycle:

1. Checks the appcast feed (`SUFeedURL` in Info.plist) for new versions
2. Shows a native dialog with release notes when an update is found
3. Downloads the DMG, verifies the EdDSA signature, installs, and restarts

The app wires Sparkle into:
- **Settings tab** — "Check for Updates" button + auto-check toggle
- **Menu bar** — "Check for Updates..." menu item

## Setup (one-time)

### 1. Generate EdDSA key pair

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

This prints the public key and stores the private key in macOS Keychain.

### 2. Set the public key in Info.plist

Replace the `SUPublicEDKey` value with the generated public key.

### 3. Export the private key for CI

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x /tmp/sparkle_private_key
```

Add the contents as a GitHub repo secret: `SPARKLE_ED_PRIVATE_KEY`. Delete the local file after.

### 4. Enable GitHub Pages

In repo Settings > Pages, set Source to the `gh-pages` branch. The appcast will be served at `https://ambar.github.io/QuiteEcho/appcast.xml`.

## Release workflow

The CI pipeline (`.github/workflows/release.yml`) automatically:

1. Builds and notarizes the DMG
2. Signs the DMG with Sparkle's `sign_update` tool (using `SPARKLE_ED_PRIVATE_KEY`)
3. Creates the GitHub Release
4. Updates `appcast.xml` on the `gh-pages` branch with the new version entry

## DMG size impact

Adding Sparkle increases the DMG from ~14 MB to ~22 MB (+8 MB).

### App bundle composition (71 MB uncompressed)

| Component | Size | Description |
|-----------|------|-------------|
| QuiteEcho binary | 61 MB | Main executable (mlx-swift, mlx-audio statically linked) |
| mlx.metallib | 2.8 MB | Compiled Metal shaders |
| Sparkle.framework | 5.3 MB | Update framework (arm64 only) |
| Other (plist/icon/codesign) | ~2 MB | |

### Sparkle.framework breakdown (5.3 MB)

| Component | Size | Purpose |
|-----------|------|---------|
| Sparkle (main dylib) | 460 KB | Update checking, appcast parsing, UI coordination |
| Autoupdate | 328 KB | Background auto-update helper |
| Updater.app | 168 KB | Update UI (progress bar, release notes dialog) |
| XPCServices/ | 212 KB | Installer.xpc (116 KB) + Downloader.xpc (96 KB) |
| Resources/ | 408 KB | 36 localizations + nib files |
| Headers/ | 188 KB | ObjC/Swift headers |
| Other (codesign/modules) | ~32 KB | |

The x86_64 architecture is stripped during bundle assembly since QuiteEcho requires Apple Silicon (MLX). This reduces the framework from 8.8 MB to 5.3 MB.

## Files changed

| File | Change |
|------|--------|
| `Package.swift` | Added `sparkle-project/Sparkle` dependency |
| `Resources/Info.plist` | Added `SUFeedURL`, `SUPublicEDKey` |
| `Sources/QuiteEcho/AppDelegate.swift` | Replaced `UpdateChecker` with `SPUStandardUpdaterController` |
| `Sources/QuiteEcho/MainWindow.swift` | Simplified update UI to Sparkle callbacks |
| `Sources/QuiteEcho/StatusBar.swift` | Added "Check for Updates..." menu item |
| `Makefile` | Embeds Sparkle.framework, strips x86_64, sets rpath |
| `.github/workflows/release.yml` | Added DMG signing + appcast update steps |
| `Sources/QuiteEcho/UpdateChecker.swift` | Deleted |
