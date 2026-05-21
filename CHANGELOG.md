# Changelog

All notable PhotoDesqueeze changes are documented here.

## [0.1.1]

### Fixed

- Sign the DMG container before notarization so Gatekeeper accepts the
  downloaded disk image.
- Harden GitHub Actions permissions for CI and release publishing.

## [0.1.0]

### Added

- Native macOS SwiftUI app for batch anamorphic desqueeze.
- RAW and rendered image input through Apple's Core Image and Image I/O stack.
- 16-bit TIFF output for editing masters.
- Preflight scan summary with planned write, rename, overwrite, and skip counts.
- Preview navigation with automatic horizontal/vertical axis resolution.
- Retry failed files, result filtering, reveal actions, and CSV manifest output.
- GitHub CI for macOS tests.
- Developer ID release scripts and GitHub release workflow.

### Known Limitations

- RAW support depends on the camera models supported by the installed macOS version.
- Output is rendered TIFF, not a new camera RAW file.
- Processing is sequential to avoid large RAW memory spikes.
- Mac App Store packaging is planned after the direct Developer ID release path is stable.
