# TinyTaskMac Release Playbook

For the full stable-release checklist, including Apple certificate setup and GitHub secrets, see [stable-release-checklist.md](/Users/hugogarza/Projects/gpt-5.4-projects/tinytask-mac/docs/stable-release-checklist.md).

## Preview build

```bash
./scripts/package_macos_release.sh 0.1.0-preview preview
node ./scripts/update_release_manifest.mjs \
  --version 0.1.0-preview \
  --channel preview \
  --macosStatus preview \
  --releaseNotesUrl https://github.com/hugogarza/tinytask-mac/releases \
  --checksumUrl https://github.com/hugogarza/tinytask-mac/releases
```

## Stable notarized build

Set the signing and notarization environment first:

```bash
export CODESIGN_IDENTITY="Developer ID Application: ..."
export NOTARYTOOL_KEYCHAIN_PROFILE="TinyTaskMacNotary"
```

Then package the release and update the website manifest with the published URLs:

```bash
./scripts/package_macos_release.sh 0.1.0 stable
node ./scripts/update_release_manifest.mjs \
  --version 0.1.0 \
  --channel stable \
  --macosStatus stable \
  --dmgUrl https://github.com/hugogarza/tinytask-mac/releases/download/v0.1.0/TinyTaskMac.dmg \
  --zipUrl https://github.com/hugogarza/tinytask-mac/releases/download/v0.1.0/TinyTaskMac.zip \
  --checksumUrl https://github.com/hugogarza/tinytask-mac/releases/download/v0.1.0/SHA256SUMS.txt \
  --releaseNotesUrl https://github.com/hugogarza/tinytask-mac/releases/tag/v0.1.0
```

## Website publish

```bash
cd website
npm install
npm run build
```

Deploy `website/dist` through Netlify after the manifest has been updated.
