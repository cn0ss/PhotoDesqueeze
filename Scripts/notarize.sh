#!/usr/bin/env bash
set -euo pipefail

ARTIFACT="${1:-}"
TEMP_KEY_PATH=""
NOTARY_WAIT_TIMEOUT="${NOTARY_WAIT_TIMEOUT:-45m}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$TEMP_KEY_PATH" && -f "$TEMP_KEY_PATH" ]]; then
    rm -f "$TEMP_KEY_PATH"
  fi
}
trap cleanup EXIT

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "$name is required"
}

[[ -n "$ARTIFACT" ]] || die "Usage: Scripts/notarize.sh artifact.zip-or-dmg"
[[ -f "$ARTIFACT" ]] || die "Artifact not found at $ARTIFACT"

require_env APPLE_NOTARY_KEY_ID
require_env APPLE_NOTARY_ISSUER_ID

if [[ -n "${APPLE_NOTARY_KEY_PATH:-}" ]]; then
  KEY_PATH="$APPLE_NOTARY_KEY_PATH"
elif [[ -n "${APPLE_NOTARY_KEY_BASE64:-}" ]]; then
  TEMP_KEY_PATH="$(mktemp "${TMPDIR:-/tmp}/notary-key.XXXXXX.p8")"
  printf '%s' "$APPLE_NOTARY_KEY_BASE64" | base64 -D > "$TEMP_KEY_PATH"
  chmod 600 "$TEMP_KEY_PATH"
  KEY_PATH="$TEMP_KEY_PATH"
else
  die "APPLE_NOTARY_KEY_PATH or APPLE_NOTARY_KEY_BASE64 is required"
fi

[[ -f "$KEY_PATH" ]] || die "Notary key not found at $KEY_PATH"

printf 'Submitting %s to Apple notarization service; wait timeout: %s\n' "$ARTIFACT" "$NOTARY_WAIT_TIMEOUT" >&2

xcrun notarytool submit "$ARTIFACT" \
  --key "$KEY_PATH" \
  --key-id "$APPLE_NOTARY_KEY_ID" \
  --issuer "$APPLE_NOTARY_ISSUER_ID" \
  --wait \
  --timeout "$NOTARY_WAIT_TIMEOUT"
