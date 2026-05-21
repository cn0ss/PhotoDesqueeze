# Research and Implementation Plan

This document captures the technical decisions behind the first PhotoDesqueeze
implementation.

## Product Goal

The app should make this workflow fast and repeatable:

`RAW originals -> batch desqueeze -> 16-bit TIFF masters -> photo editor`

The app does not attempt to write a new RAW file. RAW data is original sensor
data; after geometric scaling, the output is a rendered image. The practical
master format for this workflow is therefore TIFF with 16-bit color samples.

## Apple Framework Choices

### Folder Access

Use a standard macOS open panel for folder selection. `NSOpenPanel` supports
directory selection through `canChooseDirectories`, and Apple's sandbox
documentation states that standard open/save panels extend sandbox access to
user-selected files and folders. When the selected URL is a folder, the access
extends recursively to items inside that folder.

Implementation:

- `FolderPanel.chooseFolder(...)`
- `PhotoDesqueeze.entitlements`
- `com.apple.security.app-sandbox`
- `com.apple.security.files.user-selected.read-write`

Sources:

- https://developer.apple.com/documentation/appkit/nsopenpanel
- https://developer.apple.com/documentation/security/app_sandbox/accessing_files_from_the_macos_app_sandbox

### File Type Detection

Use `UniformTypeIdentifiers` first, because Apple publishes system-declared
types such as `UTType.rawImage`, `UTType.tiff`, and `UTType.folder`. Fall back
to a curated list of common camera RAW extensions because not every RAW-like
extension is guaranteed to resolve the same way on every macOS install.

Implementation:

- `ImageFileScanner.isSupportedImage(_:)`
- `ImageFileScanner.isLikelyRAW(_:)`

Sources:

- https://developer.apple.com/documentation/uniformtypeidentifiers
- https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct
- https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/tiff

### RAW Input

Use `CIRAWFilter` for likely RAW files. Apple describes it as a filter that
produces an image by manipulating RAW image sensor data and provides an
`init(imageURL:)` initializer. This keeps the app on Apple's camera RAW pipeline
instead of shelling out to ImageMagick or bundling a decoder.

Orientation is handled before reading `outputImage` by applying the
`CGImagePropertyOrientation` stored in Image I/O metadata when available.

Implementation:

- `ImageBatchProcessor.loadImage(from:)`
- `ImageBatchProcessor.imageOrientation(for:)`

Sources:

- https://developer.apple.com/documentation/coreimage/cirawfilter
- https://developer.apple.com/documentation/coreimage/cirawfilter/orientation
- https://developer.apple.com/documentation/imageio/cgimagepropertyorientation
- https://developer.apple.com/documentation/imageio/kcgimagepropertyorientation

### Rendered Image Input

For TIFF, JPEG, PNG, HEIC/HEIF, WebP, and other macOS-supported image files,
use `CIImage(contentsOf:options:)` with `.applyOrientationProperty`. Apple
documents that this option transforms the image according to orientation
metadata when the value is true.

Implementation:

- `CIImage(contentsOf: url, options: [.applyOrientationProperty: true])`

Source:

- https://developer.apple.com/documentation/coreimage/ciimageoption/applyorientationproperty

### Desqueeze Transform

An anamorphic desqueeze is a non-proportional scale. In normal landscape
capture, the correction stretches width. If the camera was rotated 90 degrees,
the image is usually displayed after orientation metadata is applied, so the
same lens correction needs to stretch height in the displayed image.

Core Image's Lanczos scale transform is a good fit because Apple documents it
as a high-quality scaler with an `aspectRatio` property that applies additional
horizontal scaling. Vertical stretching is represented as:

- `scale = factor`
- `aspectRatio = 1 / factor`

That keeps width stable while increasing height.

For a 1.33x lens:

- `scale = 1.0`
- `aspectRatio = 1.33`

That leaves height unchanged and stretches width.

The app defaults to `Auto` axis selection:

- EXIF/RAW orientation `.left`, `.right`, `.leftMirrored`, or `.rightMirrored` -> vertical.
- Otherwise, portrait pixel dimensions -> vertical.
- Otherwise -> horizontal.

Manual `Horizontal` and `Vertical` overrides are available for files whose
orientation metadata has already been baked in or stripped by another app.

Implementation:

- `DesqueezeAxis.resolved(orientation:imageExtent:)`
- `ImageBatchProcessor.desqueeze(_:factor:axis:)`
- Core Image filter name: `CILanczosScaleTransform`

Sources:

- https://developer.apple.com/documentation/coreimage/cifilter/3228344-lanczosscaletransform
- https://developer.apple.com/documentation/coreimage/cilanczosscaletransform

### TIFF Output

Use `CIContext.writeTIFFRepresentation(of:to:format:colorSpace:options:)`.
Apple documents this method as rendering a `CIImage` and exporting the result
as a TIFF file to a URL. The current implementation uses `.RGBA16`, which
produces a 16-bit/channel TIFF suitable as a master file for further editing.

Implementation:

- `CIContext.writeTIFFRepresentation(...)`
- `CIFormat.RGBA16`
- `CGColorSpace.displayP3` or `CGColorSpace.sRGB`

Source:

- https://developer.apple.com/documentation/coreimage/cicontext/1642213-writetiffrepresentation

## Batch Behavior

The app processes sequentially rather than concurrently. RAW files can be very
large, and running multiple decodes/renders at once can create memory pressure.
A later version can add configurable concurrency after measuring memory use on
large real-world batches.

Output naming:

- Source: `shot001.DNG`
- Factor: `1.33x`
- Output: `shot001_desqueezed_1_33x.tiff`

If overwrite protection is enabled and the output file exists, the app writes:

- `shot001_desqueezed_1_33x-2.tiff`
- `shot001_desqueezed_1_33x-3.tiff`

## Test Coverage

The first tests cover logic that can regress without needing sample proprietary
RAW files in the repository:

- Factor labels are filesystem-friendly.
- Output paths preserve relative folders.
- Output paths avoid overwrites.
- Scanner finds RAW and rendered image extensions recursively and non-recursively.
- Automatic axis selection handles rotated metadata and portrait dimensions.
- Generated TIFF fixtures validate horizontal and vertical 16-bit TIFF output.

Command:

```bash
xcodebuild test \
  -project PhotoDesqueeze.xcodeproj \
  -scheme PhotoDesqueeze \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/PhotoDesqueezeDerivedData
```

## Next Implementation Steps

Useful follow-ups after the first version:

- Add metadata copying from source to output TIFF where safe.
- Add a small preview pane for the selected factor.
- Add optional squeeze mode for workflows that need to reverse a prior desqueeze.
- Add saved security-scoped bookmarks for persistent input/output folders.
- Add a sample-image integration test using generated TIFF fixtures.
