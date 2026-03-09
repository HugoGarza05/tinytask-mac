# TinyTaskMac Stable Release Checklist

Use this when moving from the current preview release to a real public macOS release.

## Target outcome

- Signed `TinyTaskMac.app`
- Signed and notarized `TinyTaskMac.dmg`
- Public GitHub Release with DMG, ZIP, and checksums
- Live website download pointing at the stable release

## One-time prerequisites

### 1. Install full Xcode

TinyTaskMac preview packaging works with Command Line Tools, but stable packaging depends on the Xcode app toolchain.

Verify:

```bash
xcodebuild -version
```

If that fails, install Xcode from the App Store and point the active developer directory at it:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### 2. Install local build tooling

```bash
brew install xcodegen
```

### 3. Apple Developer assets

You need:

- an Apple Developer account
- a `Developer ID Application` certificate in your login keychain
- an App Store Connect API key for notarization

The workflow and local scripts expect the bundle identifier in [Info.plist](/Users/hugogarza/Projects/gpt-5.4-projects/tinytask-mac/packaging/macos/AppHost/Info.plist) to remain `com.hugogarza.tinytaskmac`.

## Local stable-release setup

### 4. Confirm the Developer ID certificate is installed

List installed code-signing identities:

```bash
security find-identity -v -p codesigning
```

Set the exact identity name:

```bash
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

### 5. Store notarization credentials

Create an App Store Connect API key, then store it in `notarytool`:

```bash
xcrun notarytool store-credentials TinyTaskMacNotary \
  --key /absolute/path/AuthKey_KEYID.p8 \
  --key-id KEYID \
  --issuer ISSUER_ID
```

Set the profile for local packaging:

```bash
export NOTARYTOOL_KEYCHAIN_PROFILE="TinyTaskMacNotary"
```

### 6. Run the prereq check

```bash
./scripts/check_release_prereqs.sh HugoGarza05/tinytask-mac
```

That verifies:

- full Xcode
- local signing env vars
- local keychain signing identity
- required GitHub Actions secrets

## GitHub Actions secrets

Set these in the `HugoGarza05/tinytask-mac` repository settings.

### Netlify deploy

- `NETLIFY_AUTH_TOKEN`
- `NETLIFY_SITE_ID`

`NETLIFY_SITE_ID` is already known for this site:

```text
1f18ef56-7eea-4699-a979-6425703e1abe
```

### macOS signing and notarization

- `TINYTASKMAC_CODESIGN_IDENTITY`
- `TINYTASKMAC_DEVELOPER_ID_CERT_BASE64`
- `TINYTASKMAC_DEVELOPER_ID_CERT_PASSWORD`
- `TINYTASKMAC_KEYCHAIN_PASSWORD`
- `TINYTASKMAC_NOTARY_KEY_ID`
- `TINYTASKMAC_NOTARY_ISSUER_ID`
- `TINYTASKMAC_NOTARY_PRIVATE_KEY`

Notes:

- `TINYTASKMAC_DEVELOPER_ID_CERT_BASE64` should be the base64-encoded `.p12` certificate export.
- `TINYTASKMAC_DEVELOPER_ID_CERT_PASSWORD` is the password used when exporting the `.p12`.
- `TINYTASKMAC_KEYCHAIN_PASSWORD` can be any strong random password for the temporary CI keychain.
- `TINYTASKMAC_NOTARY_PRIVATE_KEY` should be the raw contents of the `.p8` file.

## Stable release flow

### 7. Validate locally

```bash
swift build
swift run TinyTaskMacSelfTest
./scripts/check_release_prereqs.sh HugoGarza05/tinytask-mac
```

### 8. Build and notarize locally, optional smoke test

```bash
./scripts/package_macos_release.sh 0.1.0 stable
```

Expected output:

- `.dist/releases/0.1.0/TinyTaskMac.dmg`
- `.dist/releases/0.1.0/TinyTaskMac.zip`
- `.dist/releases/0.1.0/SHA256SUMS.txt`

### 9. Publish through GitHub Actions

Run the `TinyTaskMac Release` workflow with:

- `version`: `0.1.0`
- `channel`: `stable`
- `publish_release`: `true`
- `deploy_site`: `true`

The workflow will:

- package the app
- sign and notarize if secrets are present
- upload release artifacts
- update `website/public/release-manifest.json`
- redeploy the website

## Acceptance checks

Verify on a clean Mac:

- the DMG opens without unsigned-app warnings
- the app launches by double-clicking
- first launch shows setup guidance if permissions are missing
- `.tmacro` and `.troutine` files open in TinyTaskMac
- the website `Download for macOS` button resolves to the stable GitHub release asset

## Current blocker summary

On this machine, the remaining blockers for a stable release are:

- full Xcode is not installed yet
- Apple signing credentials are not configured yet
- `NETLIFY_AUTH_TOKEN` still needs to be added to the GitHub repo
