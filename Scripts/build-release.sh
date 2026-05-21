#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${PROJECT:-PhotoDesqueeze.xcodeproj}"
SCHEME="${SCHEME:-PhotoDesqueeze}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-PhotoDesqueeze}"
VERSION="${1:-${VERSION:-}}"
RELEASE_DIR="${RELEASE_DIR:-"$ROOT_DIR/build/release"}"
ARCHIVE_PATH="${ARCHIVE_PATH:-"$RELEASE_DIR/archive/$APP_NAME.xcarchive"}"
EXPORT_PATH="${EXPORT_PATH:-"$RELEASE_DIR/export"}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-"$RELEASE_DIR/DerivedData"}"
EXPORT_TEMPLATE="${EXPORT_TEMPLATE:-"$ROOT_DIR/Config/ExportOptions-DeveloperID.plist"}"
EXPORT_OPTIONS_PATH="${EXPORT_OPTIONS_PATH:-"$RELEASE_DIR/ExportOptions-DeveloperID.generated.plist"}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "$name is required"
}

project_version() {
  xcodebuild \
    -project "$ROOT_DIR/$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null |
    awk -F'= ' '/MARKETING_VERSION/ { print $2; exit }'
}

require_env APPLE_TEAM_ID

PROJECT_VERSION="$(project_version)"
[[ -n "$PROJECT_VERSION" ]] || die "Could not read MARKETING_VERSION from project"

if [[ -z "$VERSION" ]]; then
  VERSION="$PROJECT_VERSION"
fi

if [[ "$VERSION" != "$PROJECT_VERSION" ]]; then
  die "Release version $VERSION does not match project MARKETING_VERSION $PROJECT_VERSION"
fi

mkdir -p "$RELEASE_DIR/archive" "$EXPORT_PATH" "$DERIVED_DATA_PATH"
sed "s/__APPLE_TEAM_ID__/$APPLE_TEAM_ID/g" "$EXPORT_TEMPLATE" > "$EXPORT_OPTIONS_PATH"

xcodebuild archive \
  -project "$ROOT_DIR/$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" >&2

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PATH" >&2

APP_PATH="$EXPORT_PATH/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || die "Expected app was not exported at $APP_PATH"

printf '%s\n' "$APP_PATH"
