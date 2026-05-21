# Signing

PhotoDesqueeze keeps signing configuration local or in GitHub Actions secrets.
Do not commit certificates, private keys, provisioning profiles, team IDs, or
local Xcode user state.

## Current Project Defaults

- Bundle identifier: `dev.niklasschmidt.PhotoDesqueeze`
- Test bundle identifier: `dev.niklasschmidt.PhotoDesqueezeTests`
- Hardened runtime: enabled
- Signing style in the project: manual
- Committed team ID: none

Local debug builds can continue using ad-hoc signing or a local Xcode team.
Release builds use Developer ID signing in CI.

## GitHub Secrets

Configure these secrets in the GitHub repository before running the release
workflow:

- `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64`
- `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `APPLE_KEYCHAIN_PASSWORD`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_KEY_BASE64`
- `APPLE_TEAM_ID`

`APPLE_DEVELOPER_ID_CERTIFICATE_BASE64` is a base64-encoded `.p12` containing
the Developer ID Application certificate and private key.

`APPLE_NOTARY_KEY_BASE64` is a base64-encoded App Store Connect API `.p8` key
used by `xcrun notarytool`.

## Local Release Environment

For a local Developer ID release, install the Developer ID Application
certificate in your login keychain or provide a temporary keychain yourself,
then export:

```bash
export APPLE_TEAM_ID="TEAMID1234"
export APPLE_NOTARY_KEY_ID="ABC123DEFG"
export APPLE_NOTARY_ISSUER_ID="00000000-0000-0000-0000-000000000000"
export APPLE_NOTARY_KEY_PATH="$HOME/AuthKey_ABC123DEFG.p8"
```

Then use the release scripts in `Docs/Release.md`.

## Rules

- Never commit `.p12`, `.cer`, `.pem`, `.key`, `.mobileprovision`, `.env`, or
  App Store Connect API keys.
- Never commit `DEVELOPMENT_TEAM` to `project.pbxproj`.
- Keep the GitHub workflow reading signing material from secrets only.
- Use `notarytool`; do not add `altool` notarization.

References:

- Apple notarization: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Apple distribution signing: https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac
