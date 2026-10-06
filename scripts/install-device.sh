#!/usr/bin/env bash
# Build Strong Babe and install it on a USB-connected iPhone.
#
# Needs a gitignored `.signing.local` at the repo root containing:
#   DEVELOPMENT_TEAM=<your team id>
# (Pick your team once in Xcode → target → Signing & Capabilities, then copy
# the ID from there.) Free "Personal Team" installs expire after 7 days; just
# re-run this script to renew. App data on the phone is kept.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .signing.local ]]; then
  echo "Missing .signing.local (DEVELOPMENT_TEAM=...). See the comment at the top of this script." >&2
  exit 1
fi
# shellcheck disable=SC1091
source .signing.local
: "${DEVELOPMENT_TEAM:?DEVELOPMENT_TEAM not set in .signing.local}"

DEVICE_ID="${DEVICE_ID:-$(xcrun devicectl list devices 2>/dev/null | grep -E 'connected' | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)}"
if [[ -z "$DEVICE_ID" ]]; then
  echo "No connected iPhone found. Plug it in, unlock it, and trust this Mac." >&2
  exit 1
fi

xcodegen generate >/dev/null
xcodebuild build \
  -project StrongBabeClub.xcodeproj \
  -scheme StrongBabeClub \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath build/DeviceData \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  | grep -E "error:|warning: .*signing|\*\* BUILD" || true

APP="build/DeviceData/Build/Products/Debug-iphoneos/StrongBabeClub.app"
[[ -d "$APP" ]] || { echo "Build failed; see output above." >&2; exit 1; }

xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
echo "Installed. First time only: on the iPhone go to Settings → General → VPN & Device Management → trust your developer app."
