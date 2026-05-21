#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
DMG_PATH="${2:-}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ -n "$APP_PATH" ]] || die "Usage: Scripts/verify-release.sh path/to/PhotoDesqueeze.app [path/to/PhotoDesqueeze.dmg]"
[[ -d "$APP_PATH" ]] || die "App not found at $APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"

if [[ -n "$DMG_PATH" ]]; then
  [[ -f "$DMG_PATH" ]] || die "DMG not found at $DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
fi
