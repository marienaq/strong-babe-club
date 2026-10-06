#!/usr/bin/env bash
# Type-checks the iOS app's Swift sources against the macOS SDK using only the
# Command Line Tools (no Xcode, no simulator). This catches most compile
# errors in views/stores before CI runs the real iOS build.
#
# Not covered: files that use SwiftData macros (@Model) — the macro plugin
# ships only with Xcode — and iOS-only code inside `#if os(iOS)`.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
pkg="$root/Packages/WorkoutCore"
# Own scratch path: never reuse a module built by a different compiler version.
scratch="$pkg/.build/typecheck"
(cd "$pkg" && swift build --scratch-path "$scratch" --product WorkoutCore >/dev/null)
bin="$(cd "$pkg" && swift build --scratch-path "$scratch" --show-bin-path)"

files=()
while IFS= read -r f; do files+=("$f"); done < <(
  find "$root/App/StrongBabeClub" -name '*.swift' \
    ! -path '*/Persistence/SwiftData*' \
    ! -name 'StrongBabeClubApp.swift' | sort)

echo "Type-checking ${#files[@]} app files against the macOS SDK..."
swiftc -typecheck -target arm64-apple-macos14 -swift-version 5 \
  -I "$bin" -I "$bin/Modules" "${files[@]}" "$@"
echo "OK"
