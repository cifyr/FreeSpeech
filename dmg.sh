#!/bin/bash
# Build a distributable .dmg of FreeKit for the download / Homebrew cask.
# Run ./build.sh first (produces dist/FreeKit.app).
#   ./dmg.sh                 -> dist/FreeKit.dmg (app only; model self-downloads on first launch)
#   ./dmg.sh --model NAME    -> also bundle a speech model in the DMG (offline-ready)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/dist/FreeKit.app"
DMG="$ROOT/dist/FreeKit.dmg"
VOL="FreeKit"
MODEL_NAME=""
MODELS_SRC="$HOME/Library/Application Support/FreeKit/models"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model) MODEL_NAME="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[[ -d "$APP" ]] || { echo "error: $APP not found — run ./build.sh first" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging DMG contents"
cp -R "$APP" "$STAGE/FreeKit.app"
# Drag-to-install target.
ln -s /Applications "$STAGE/Applications"

if [[ -n "$MODEL_NAME" ]]; then
    MODEL_FILE="$MODELS_SRC/ggml-$MODEL_NAME.bin"
    [[ -f "$MODEL_FILE" ]] || { echo "error: model $MODEL_FILE not found — run ./build.sh --model $MODEL_NAME" >&2; exit 1; }
    mkdir -p "$STAGE/models"
    cp "$MODEL_FILE" "$STAGE/models/"
fi

echo "==> Building $DMG"
rm -f "$DMG"
# UDZO = read-only, zlib-compressed; the standard app-DMG format.
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null

SIZE="$(du -h "$DMG" | cut -f1)"
echo
echo "Done: $DMG ($SIZE)"
echo "The app is self-signed, not notarized — a downloaded copy is quarantined:"
echo "  - Homebrew cask installs it with --no-quarantine (no prompt)."
echo "  - Direct download: drag to Applications, then right-click > Open once."
echo "Attach $DMG to a GitHub release for the download link."
