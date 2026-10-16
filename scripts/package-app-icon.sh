#!/usr/bin/env bash
# The approved public icon is copied exactly; no SVG regeneration or fallback.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# == 1 ]] || { echo "Usage: $0 <app Resources directory>" >&2; exit 2; }
ICON_SOURCE="$ROOT/Support/AppIcon.icns"
ICON_CHECKSUM="$ROOT/Support/AppIcon.sha256"
[[ -f "$ICON_SOURCE" && -f "$ICON_CHECKSUM" ]] || {
    echo "Error: approved app icon or checksum is missing; packaging stopped." >&2
    exit 1
}
EXPECTED="$(tr -d '[:space:]' < "$ICON_CHECKSUM")"
ACTUAL="$(shasum -a 256 "$ICON_SOURCE" | awk '{print $1}')"
[[ "$EXPECTED" =~ ^[a-f0-9]{64}$ && "$ACTUAL" == "$EXPECTED" ]] || {
    echo "Error: approved app icon checksum mismatch; packaging stopped." >&2
    exit 1
}
cp "$ICON_SOURCE" "$1/AppIcon.icns"
cmp -s "$ICON_SOURCE" "$1/AppIcon.icns" || {
    echo "Error: packaged app icon differs from the approved icon." >&2
    exit 1
}
