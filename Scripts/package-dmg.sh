#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-"$(cd "$SCRIPT_DIR/.." && pwd)"}"
APP_PATH="${1:-}"
VERSION="${2:-${VERSION:-}}"
RELEASE_DIR="${RELEASE_DIR:-"$ROOT_DIR/build/release"}"
APP_NAME="${APP_NAME:-PhotoDesqueeze}"
DMG_CODE_SIGN_IDENTITY="${DMG_CODE_SIGN_IDENTITY:-Developer ID Application}"
CODESIGN_WITH_TIMEOUT="${CODESIGN_WITH_TIMEOUT:-"$ROOT_DIR/Scripts/codesign-with-timeout.sh"}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ -n "$APP_PATH" ]] || die "Usage: Scripts/package-dmg.sh path/to/PhotoDesqueeze.app VERSION"
[[ -d "$APP_PATH" ]] || die "App not found at $APP_PATH"
[[ -n "$VERSION" ]] || die "VERSION is required"
[[ -f "$CODESIGN_WITH_TIMEOUT" ]] || die "codesign timeout helper not found at $CODESIGN_WITH_TIMEOUT"

mkdir -p "$RELEASE_DIR"

ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.zip"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"
DMG_STAGING="$RELEASE_DIR/dmg-staging"

rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$DMG_CODE_SIGN_IDENTITY" != "-" ]]; then
  KEYCHAIN_ARGS=()
  if [[ -n "${SIGNING_KEYCHAIN_PATH:-}" ]]; then
    KEYCHAIN_ARGS=(--keychain "$SIGNING_KEYCHAIN_PATH")
  fi

  "$CODESIGN_WITH_TIMEOUT" \
    codesign \
    --force \
    --sign "$DMG_CODE_SIGN_IDENTITY" \
    "${KEYCHAIN_ARGS[@]}" \
    --timestamp \
    "$DMG_PATH"

  codesign --verify --verbose=2 "$DMG_PATH" >&2
  if ! codesign -dvv "$DMG_PATH" 2>&1 | grep -q '^Timestamp='; then
    die "Expected DMG signature to include a secure timestamp"
  fi
fi

printf '%s\n%s\n' "$ZIP_PATH" "$DMG_PATH"
