#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator (newest iOS runtime first).
set -euo pipefail
xcrun simctl list devices available --json | python3 -c '
import json, re, sys
data = json.load(sys.stdin)["devices"]
def ver(runtime):
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
for runtime in sorted((r for r in data if "iOS" in r), key=ver, reverse=True):
    phones = [d for d in data[runtime] if d.get("isAvailable") and d["name"].startswith("iPhone")]
    if phones and ver(runtime) >= (17, 0):
        print(phones[0]["udid"])
        sys.exit(0)
sys.exit("no iPhone simulator with iOS 17+ found")
'
