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

DEVICE_ID="${DEVICE_ID:-$(xcrun devicectl list devices 2>/dev/null | grep -E 'iPhone' | grep -E 'connected|available' | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)}"
if [[ -z "$DEVICE_ID" ]]; then
  echo "No paired iPhone found. Plug it in (or be on the same Wi-Fi), unlock it, and trust this Mac." >&2
  exit 1
fi

# Xcode reuses a cached profile even when it is about to expire, so the
# "renewed" app can die hours later. Drop ours if it has < 3 days left.
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
for f in "$PROFILES"/*.mobileprovision; do
  [[ -f "$f" ]] || continue
  plist="$(security cms -D -i "$f" 2>/dev/null)" || continue
  [[ "$(plutil -extract Name raw -o - - <<<"$plist" 2>/dev/null)" == *com.marienaq.strongbabeclub* ]] || continue
  exp="$(plutil -extract ExpirationDate raw -o - - <<<"$plist")"
  if (( $(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$exp" +%s) - $(date +%s) < 3 * 86400 )); then
    echo "Profile expires $exp; removing it so Xcode makes a fresh one."
    rm -f "$f"
  fi
done

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
EXP="$(security cms -D -i "$APP/embedded.mobileprovision" | plutil -extract ExpirationDate raw -o - -)"
echo "App expires $(date -j -f "%s" "$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$EXP" +%s)" "+%a %b %-d, %-I:%M %p"). Re-run this script before then."
echo "Installed. First time only: on the iPhone go to Settings → General → VPN & Device Management → trust your developer app."
