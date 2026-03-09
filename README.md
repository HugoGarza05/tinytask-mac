# TinyTaskMac

Precision-first TinyTask-style macro recorder for macOS.

## What is implemented

- Native `AppKit` floating toolbar with `Record`, `Play`, `Open`, `Save`, `Prefs`
- Global hotkeys via Carbon
- Global input capture via `CGEventTap`
- Guided first-run setup window for `Accessibility` and `Input Monitoring`
- Strict target-window validation and refocus guard
- Binary `.tmacro` save/load format
- Finder-open support for `.tmacro` and `.troutine` files
- Playback engine with strict/scaled timing modes and repeat support
- Preferred playback app selection and focus-lock preference
- Timed interrupt routine scheduler with `.troutine` files
- Menu bar fallback and hotkey preferences window
- In-repo Vite/Tailwind marketing website under `website/`
- Preview app bundle and release packaging scripts under `scripts/`

## Build

```bash
swift build
```

## Run

```bash
swift run TinyTaskMac
```

On first launch, TinyTaskMac opens a dedicated setup window for `Accessibility` and `Input Monitoring`. Recording, playback, and routine start stay disabled until both permissions are granted.

## Website

```bash
cd website
npm install
npm run dev
```

The site reads release data from [`website/public/release-manifest.json`](/Users/hugogarza/Projects/gpt-5.4-projects/tinytask-mac/website/public/release-manifest.json) and uses Netlify headers/redirects from the same directory.

## Preview App Bundle

Build a double-clickable preview app bundle and packaged artifacts without Xcode:

```bash
./scripts/build_macos_app_bundle.sh
./scripts/package_macos_release.sh 0.1.0-preview preview
```

That writes `.app`, `.zip`, `.dmg`, and `SHA256SUMS.txt` under `.dist/releases/`.

## Xcode App Target

The distribution app target is defined via XcodeGen:

```bash
cd packaging/xcodegen
xcodegen generate
```

See [`packaging/README.md`](/Users/hugogarza/Projects/gpt-5.4-projects/tinytask-mac/packaging/README.md) and [`docs/release-playbook.md`](/Users/hugogarza/Projects/gpt-5.4-projects/tinytask-mac/docs/release-playbook.md) for packaging and release flow details.

## Troubleshooting

If `swift run TinyTaskMac` fails with a `PCH was compiled with module cache path ...` error after moving or renaming the repo directory, clear SwiftPM's build cache and rebuild:

```bash
swift package clean
swift run TinyTaskMac
```

## Verification

```bash
swift run TinyTaskMacSelfTest
```

That self-test verifies macro and routine roundtrips plus scheduler behavior.
