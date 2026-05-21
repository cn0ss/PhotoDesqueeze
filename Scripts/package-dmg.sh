#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-}"
VERSION="${2:-${VERSION:-}}"
RELEASE_DIR="${RELEASE_DIR:-"$ROOT_DIR/build/release"}"
APP_NAME="${APP_NAME:-PhotoDesqueeze}"
DMG_CODE_SIGN_IDENTITY="${DMG_CODE_SIGN_IDENTITY:-Developer ID Application}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ -n "$APP_PATH" ]] || die "Usage: Scripts/package-dmg.sh path/to/PhotoDesqueeze.app VERSION"
[[ -d "$APP_PATH" ]] || die "App not found at $APP_PATH"
[[ -n "$VERSION" ]] || die "VERSION is required"

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
  codesign --force --sign "$DMG_CODE_SIGN_IDENTITY" --timestamp "$DMG_PATH"
fi

printf '%s\n%s\n' "$ZIP_PATH" "$DMG_PATH"
