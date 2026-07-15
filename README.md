<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/assets/banner-dark.png">
  <source media="(prefers-color-scheme: light)" srcset=".github/assets/banner-light.png">
  <img alt="FreeKit — local macOS utility suite" src=".github/assets/banner-dark.png" width="100%">
</picture>

<br><br>

![Platform](https://img.shields.io/badge/macOS-26+-FF453A?style=flat-square)
![Chip](https://img.shields.io/badge/Apple_Silicon-only-FF453A?style=flat-square)
![Privacy](https://img.shields.io/badge/100%25-on--device-1D1D24?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-8E8E99?style=flat-square)

**One menu-bar app. A dozen native macOS utilities. Free, open source, and entirely on-device.**

</div>

---

FreeKit replaces a shelf of separate menu-bar apps with a single native Swift one. Media controls by
the notch, floating notes, one-tap file compression and conversion, system stats, a Caps Lock
remap, dictation — each is an independent tool you turn on from one Control Center. No cloud, no
account, no telemetry, nothing to subscribe to. The only time anything touches the network is the
optional one-time download of the dictation model.

## The tools

Enable only what you want — every tool is off until you switch it on.

| Tool | What it does |
|---|---|
| **Notch** | Now-playing controls (Spotify / Apple Music) and your next calendar event, docked beside the notch. |
| **Notebook** | Floating scratch notes on a global hotkey — searchable, styled, saved to disk. |
| **Simplify** | Automatic image, video, and PDF compression the moment you copy one. |
| **Convert** | Drag-and-drop conversion between image, audio, video, and document formats, on-device. |
| **Shelf** | Shake a drag to park files on a floating shelf, then drop them anywhere later. |
| **Stats** | Live CPU, memory, GPU, disk, network, and battery in the menu bar, with per-metric styles and colors. |
| **HyperKey** | Remap Caps Lock to a hyper key, Command, or tap-for-Escape. |
| **Tap** | Fixed-interval autoclicker at the cursor or a set point; supports recorded macros. |
| **AppCleaner** | Uninstall apps together with their leftover support files. |
| **Amphetamine** | Keep the Mac awake on a timer — including with the lid closed. |
| **Speech** | On-device dictation: hold a hotkey, speak, and text lands at the cursor in any app. |

*Coming soon:* **Ice** (menu-bar icon manager) · **Cotypist** (inline text prediction) · **LinearMouse** (per-device pointer tuning).

## Install

**Homebrew** (recommended):

```bash
brew tap cifyr/freekit
brew trust cifyr/freekit                        # Homebrew 6+ requires trusting a third-party tap
brew install --cask --no-quarantine freekit
```

`--no-quarantine` is needed because the app is self-signed rather than notarized — Gatekeeper would
otherwise block first launch. Upgrade with `brew upgrade --cask freekit`; remove everything with
`brew uninstall --zap --cask freekit`.

**Direct download:** grab **FreeKit.dmg** from the [latest release](https://github.com/cifyr/FreeKit/releases/latest),
open it, and drag **FreeKit** to **Applications**. Because it isn't notarized, the first launch needs a
**right-click → Open** (a plain double-click is blocked by Gatekeeper). Everything runs on-device from there.

## Requirements

- **Apple Silicon** Mac (M1 or newer)
- **macOS 26** or newer

## Build from source

Requires Xcode command-line tools and `cmake` (`brew install cmake`).

```bash
git clone https://github.com/cifyr/FreeKit.git && cd FreeKit
./build.sh                 # vendors whisper.cpp, runs tests, builds dist/FreeKit.app
open dist/FreeKit.app
./dmg.sh                   # optional: package dist/FreeKit.dmg for distribution
```

Native Swift throughout: `FreeKitCore` holds each tool's pure, unit-tested logic (state machines,
format plans, catalog data); the `FreeKit` app target wires it to AppKit, CoreAudio, and
ScreenCaptureKit. Dictation uses a vendored [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
with Metal acceleration, and optional on-device text rewrites use Apple's FoundationModels — so it
stays fully offline after the one model download.

---

<div align="center">
<sub>Runs entirely on your Mac · Apple Silicon · macOS 26+ · MIT</sub>
</div>
