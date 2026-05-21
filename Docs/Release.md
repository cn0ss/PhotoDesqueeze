# Release Process

PhotoDesqueeze ships direct releases first through GitHub Releases using
Developer ID signing and notarization. Mac App Store distribution is a later
stage.

## Developer ID Release

1. Confirm the tree is clean.

   ```bash
   git status --short
   ```

2. Run tests.

   ```bash
   xcodebuild test \
     -project PhotoDesqueeze.xcodeproj \
     -scheme PhotoDesqueeze \
     -destination 'platform=macOS' \
     -derivedDataPath /private/tmp/PhotoDesqueezeDerivedData
   ```

3. Confirm `MARKETING_VERSION` matches the release version.

   ```bash
   rg 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' PhotoDesqueeze.xcodeproj/project.pbxproj
   ```

4. Run the sensitive-file scan.

   ```bash
   find . -path './.git' -prune -o \
     -path '*/xcuserdata/*' -o \
     -name '.DS_Store' -o \
     -name '*.xcuserstate' -o \
     -name '*.mobileprovision' -o \
     -name '*.p12' -o \
     -name '*.cer' -o \
     -name '*.pem' -o \
     -name '*.key' -o \
     -name '.env' -print
   ```

5. Tag the release.

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

6. GitHub Actions runs `.github/workflows/release.yml`.

   A full Developer ID release can take tens of minutes because it runs macOS
   tests, archives the app, notarizes the app, creates the DMG, notarizes the
   DMG, verifies Gatekeeper, and only then publishes the GitHub Release. The
   workflow has explicit step timeouts so stalled Apple or Xcode operations fail
   instead of waiting indefinitely.

7. If a tagged run was canceled before publishing, re-run the release from the
   Actions tab with `workflow_dispatch` and the same version number. For
   example, use `0.1.1` for tag `v0.1.1`; the workflow will verify the tag
   exists, check it out, and publish the assets for that tag.

8. Download the `.zip` and `.dmg` from GitHub Releases.

9. Verify on a clean macOS user account:

   - The app launches without Gatekeeper warnings beyond the normal first-run
     confirmation.
   - Folder selection works.
   - A small TIFF fixture can be previewed and processed.

## Local Developer ID Release

Use this only when the signing certificate and notarization API key are already
available locally.

```bash
export APPLE_TEAM_ID="TEAMID1234"
export APPLE_NOTARY_KEY_ID="ABC123DEFG"
export APPLE_NOTARY_ISSUER_ID="00000000-0000-0000-0000-000000000000"
export APPLE_NOTARY_KEY_PATH="$HOME/AuthKey_ABC123DEFG.p8"
export RELEASE_DIR="$PWD/build/release"

APP_PATH="$(Scripts/build-release.sh X.Y.Z)"
ditto -c -k --keepParent "$APP_PATH" "$RELEASE_DIR/PhotoDesqueeze-notary.zip"
Scripts/notarize.sh "$RELEASE_DIR/PhotoDesqueeze-notary.zip"
xcrun stapler staple "$APP_PATH"
Scripts/package-dmg.sh "$APP_PATH" X.Y.Z
Scripts/notarize.sh "$RELEASE_DIR/PhotoDesqueeze-X.Y.Z.dmg"
xcrun stapler staple "$RELEASE_DIR/PhotoDesqueeze-X.Y.Z.dmg"
Scripts/verify-release.sh "$APP_PATH" "$RELEASE_DIR/PhotoDesqueeze-X.Y.Z.dmg"
```

## Release Artifacts

The Developer ID release produces:

- `PhotoDesqueeze-VERSION.zip`
- `PhotoDesqueeze-VERSION.dmg`

The app inside both artifacts is Developer ID signed, notarized, and stapled.
The DMG is notarized and stapled as well.

## If Notarization Fails

1. Open the failed GitHub Actions run.
2. Find the `notarytool` submission ID in the logs.
3. Run locally with the same API key:

   ```bash
   xcrun notarytool log SUBMISSION_ID \
     --key "$APPLE_NOTARY_KEY_PATH" \
     --key-id "$APPLE_NOTARY_KEY_ID" \
     --issuer "$APPLE_NOTARY_ISSUER_ID"
   ```

4. Fix signing or entitlement problems.
5. Re-tag only if the release commit changes.

## Mac App Store Stage

After Developer ID releases are stable:

- Add `Config/ExportOptions-AppStore.plist`.
- Add an `app-store-release` workflow.
- Prepare App Store Connect metadata:
  - Name: PhotoDesqueeze
  - Category: Photography
  - Bundle ID: `dev.niklasschmidt.PhotoDesqueeze`
  - Support URL: `https://niklasschmidt.dev`
  - Privacy policy URL: `https://niklasschmidt.dev`
- Prepare screenshots of folder selection, preflight, preview, and results.
- Keep sandbox entitlements limited to user-selected read/write file access.
