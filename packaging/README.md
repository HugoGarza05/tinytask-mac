# TinyTaskMac Packaging

This directory contains the macOS app bundle metadata and the XcodeGen spec for a distributable TinyTaskMac app.

## Generate an Xcode project

```bash
cd packaging/xcodegen
xcodegen generate
```

The generated project depends on the local Swift package and produces a standard macOS application bundle with:

- bundle identifier `com.hugogarza.tinytaskmac`
- `.tmacro` and `.troutine` document associations
- version/build metadata
- asset catalog and Info.plist wiring

## Build preview artifacts without Xcode

```bash
./scripts/build_macos_app_bundle.sh
./scripts/package_macos_release.sh 0.1.0-preview preview
```

Those scripts create an unsigned `.app`, `.zip`, `.dmg`, and `SHA256SUMS.txt` under `.dist/`.

## Stable release readiness

Run the release prerequisite checker before attempting a signed build:

```bash
./scripts/check_release_prereqs.sh HugoGarza05/tinytask-mac
```

See [docs/stable-release-checklist.md](/Users/hugogarza/Projects/gpt-5.4-projects/tinytask-mac/docs/stable-release-checklist.md) for the full signing and notarization setup.
