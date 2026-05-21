# PhotoDesqueeze

PhotoDesqueeze is a native macOS SwiftUI app for batch anamorphic desqueeze.
It reads a folder of RAW or rendered images, stretches width by the selected
lens factor, and writes practical editing masters as 16-bit TIFF files.

The intended workflow is:

1. Keep original RAW files untouched.
2. Select the source folder in PhotoDesqueeze.
3. Select an output folder.
4. Choose the lens factor, usually `1.33x`, `1.55x`, `1.60x`, `1.80x`, or `2.00x`.
5. Process to 16-bit TIFF.
6. Edit the TIFFs in Photomator, Pixelmator Pro, Lightroom, Capture One, or another editor.

## Why TIFF, not RAW?

An anamorphic desqueeze changes the rendered geometry of an image. After that
operation the result is no longer the camera's original RAW sensor data. This
app keeps RAW originals untouched and creates high-quality 16-bit TIFF files as
editable masters.

## Features

- Native macOS SwiftUI app target.
- Folder input and folder output.
- RAW-first loading through Apple's Core Image RAW pipeline.
- Fallback support for common rendered formats supported by macOS, including TIFF, JPEG, PNG, HEIC/HEIF, and WebP.
- Batch processing with progress, cancellation, and per-file results.
- Built-in anamorphic presets plus custom factors.
- Automatic horizontal/vertical desqueeze axis selection with manual overrides.
- 16-bit/channel TIFF export.
- Display P3 or sRGB output color space.
- Optional recursive folder scanning.
- Optional preservation of input subfolder structure.
- Optional overwrite protection with automatic `-2`, `-3`, etc. filenames.

## Build

Requirements:

- macOS with Xcode 26 or newer installed.
- Xcode command line tools selected with `xcode-select`.

Open the project:

```bash
open PhotoDesqueeze.xcodeproj
```

Run tests from Terminal:

```bash
xcodebuild test \
  -project PhotoDesqueeze.xcodeproj \
  -scheme PhotoDesqueeze \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/PhotoDesqueezeDerivedData
```

## Implementation Notes

The processing path is intentionally simple and native:

- `NSOpenPanel` selects input and output folders.
- App Sandbox uses user-selected read/write file access.
- `UTType` and fallback RAW extensions identify candidate images.
- `CIRAWFilter` opens RAW files supported by macOS.
- `CIImage(contentsOf:options:)` opens rendered image formats and applies orientation metadata.
- `CILanczosScaleTransform` performs high-quality scaling. Landscape files are stretched horizontally; 90-degree rotated or portrait files can be stretched vertically.
- `CIContext.writeTIFFRepresentation` writes the rendered output as `.RGBA16` TIFF in the selected RGB color space.

More detail is in [Docs/Research.md](Docs/Research.md).

## Current Limitations

- RAW support depends on Apple's RAW decoders and the camera models supported by the installed macOS version.
- Output is a rendered 16-bit TIFF, not a new RAW file.
- Metadata copying is minimal in this first version.
- Automatic axis detection uses orientation metadata first, then image dimensions as a fallback.
- Processing is sequential to avoid memory spikes with large RAW batches.

## References

- Apple Image I/O overview: https://developer.apple.com/documentation/imageio
- Apple `CIRAWFilter`: https://developer.apple.com/documentation/coreimage/cirawfilter
- Apple `CIContext.writeTIFFRepresentation`: https://developer.apple.com/documentation/coreimage/cicontext/1642213-writetiffrepresentation
- Apple `CILanczosScaleTransform`: https://developer.apple.com/documentation/coreimage/cifilter/3228344-lanczosscaletransform
- Apple App Sandbox file access: https://developer.apple.com/documentation/security/app_sandbox/accessing_files_from_the_macos_app_sandbox
