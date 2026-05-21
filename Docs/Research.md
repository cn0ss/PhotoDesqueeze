# Research and Implementation Plan

This document captures the technical decisions behind the PhotoDesqueeze
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
- `SecurityScopedFolderBookmarkStore`
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

For a 1.33x lens in horizontal mode:

- `scale = 1.0`
- `aspectRatio = 1.33`

That leaves height unchanged and stretches width.

The app defaults to `Auto` axis selection:

- EXIF/RAW orientation `.left`, `.right`, `.leftMirrored`, or `.rightMirrored` -> vertical.
- Otherwise, portrait pixel dimensions -> vertical.
- Otherwise -> horizontal.

Manual `Horizontal` and `Vertical` overrides are available for files whose
orientation metadata has already been baked in or stripped by another app.
The preview pane renders a selected file from the scanned list with the same
automatic/manual axis resolution, so a wrong axis choice is visible before
starting a batch. If Auto falls back to portrait dimensions because orientation
metadata is missing, the UI shows a warning.

Implementation:

- `DesqueezeAxis.resolution(orientation:imageExtent:)`
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
- Atomic temporary-file write followed by `FileManager.moveItem(...)`
- Conservative TIFF/EXIF properties passed through Image I/O options

Source:

- https://developer.apple.com/documentation/coreimage/cicontext/1642213-writetiffrepresentation

### Metadata

The app reads Image I/O properties from the source image and keeps a small
structured summary in each result and in the CSV manifest:

- camera make
- camera model
- lens model
- capture date
- ISO, exposure time, aperture, and focal length when available

For output files, only conservative TIFF/EXIF dictionaries are copied. Orientation
fields are removed because the desqueeze result is already rendered into its new
geometry, and preserving stale orientation metadata would risk incorrect display
in downstream editors.

The app intentionally does not copy GPS metadata in this version.

## Batch Behavior

The app processes sequentially rather than concurrently. RAW files can be very
large, and running multiple decodes/renders at once can create memory pressure.
A later version can add configurable concurrency after measuring memory use on
large real-world batches.

Output naming:

- Source: `shot001.DNG`
- Factor: `1.33x`
- Output: `shot001_desqueezed_1_33x.tiff`

Existing-file behavior is controlled by `CollisionMode`:

- `Auto Rename`: write `shot001_desqueezed_1_33x-2.tiff`,
  `shot001_desqueezed_1_33x-3.tiff`, and so on.
- `Overwrite`: replace the existing destination only after the new TIFF render
  succeeds.
- `Skip Existing`: leave the existing destination untouched and record a skipped
  result.

After a batch, the app writes `PhotoDesqueeze manifest.csv` into the output
folder. The manifest records source path, output path, status, selected axis,
resolved axis, dimensions, duration, camera fields, and error text.

Before processing, the app runs a non-rendering preflight that scans supported
images and plans each output path. The preflight reports:

- total files
- RAW files
- rendered files
- normal writes
- auto-renamed outputs
- overwrites
- skipped existing outputs

Overwrite mode requires user confirmation before processing starts.

## App UI

The SwiftUI interface is a practical batch tool rather than a landing page:

- input and output folder rows
- lens preset/custom factor controls
- axis, color space, and existing-file controls
- recursive scanning and folder-preservation toggles
- preflight scan summary
- side-by-side original/desqueezed preview with previous/next navigation
- progress, cancellation, retry-failed, output reveal, source reveal, and copy-error actions
- result filters for all statuses
- saved processing settings plus reset to defaults

The target bundle identifier is `dev.niklasschmidt.PhotoDesqueeze`. Signing is
manual, and no team ID, certificate, profile, or private key is committed.

## Test Coverage

The tests cover logic that can regress without needing sample proprietary
RAW files in the repository:

- Factor labels are filesystem-friendly.
- Output paths preserve relative folders.
- Output paths avoid overwrites or skip existing destinations according to the
  selected collision mode.
- Preflight counts write, auto-rename, overwrite, and skip output plans.
- Scanner finds RAW and rendered image extensions recursively and non-recursively.
- Automatic axis selection handles rotated metadata and portrait dimensions.
- Factor parsing handles dot/comma decimals and invalid input.
- Preview selection clamps navigation bounds.
- Retry selection includes failed results only.
- Generated TIFF fixtures validate horizontal and vertical 16-bit TIFF output.
- Generated TIFF fixtures validate manifest creation, including cancelled rows.

Command:

```bash
xcodebuild test \
  -project PhotoDesqueeze.xcodeproj \
  -scheme PhotoDesqueeze \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/PhotoDesqueezeDerivedData
```

## Next Implementation Steps

Useful follow-ups after the current version:

- Add a searchable per-file preview picker for very large folders.
- Add optional squeeze mode for workflows that need to reverse a prior desqueeze.
- Add configurable RAW development controls such as exposure bias, white balance,
  and highlight recovery if Core Image exposes the needed data for a file.
- Add configurable output naming templates.
- Add optional concurrency with a low default and memory-pressure testing.
- Add a notarized release workflow once signing credentials are handled outside
  the repository.
