import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension CIImageRepresentationOption {
    static let properties = CIImageRepresentationOption(rawValue: "CIImageRepresentationProperties")
}

struct ImageFileScanner {
    private static let fallbackImageExtensions: Set<String> = [
        "3fr", "ari", "arw", "bay", "cr2", "cr3", "crw", "dcr", "dng", "erf",
        "fff", "heic", "heif", "iiq", "jpeg", "jpg", "k25", "kdc", "mef", "mos",
        "mrw", "nef", "nrw", "orf", "pef", "png", "raf", "raw", "rw2", "rwl",
        "sr2", "srf", "tif", "tiff", "webp", "x3f"
    ]

    static func imageFiles(in folder: URL, recursive: Bool, fileManager: FileManager = .default) throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isHiddenKey]
        let options: FileManager.DirectoryEnumerationOptions = recursive
            ? [.skipsHiddenFiles, .skipsPackageDescendants]
            : [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]

        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else { continue }
            guard isSupportedImage(url) else { continue }
            files.append(url)
        }

        return files.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    static func isSupportedImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return false }

        if let type = UTType(filenameExtension: ext),
           type.conforms(to: .image) || type.conforms(to: .rawImage) {
            return true
        }

        return fallbackImageExtensions.contains(ext)
    }

    static func isLikelyRAW(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()

        if let type = UTType(filenameExtension: ext), type.conforms(to: .rawImage) {
            return true
        }

        return fallbackImageExtensions.contains(ext)
            && !["heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp"].contains(ext)
    }
}

enum OutputPlan: Equatable {
    case write(URL)
    case skip(URL)

    var url: URL {
        switch self {
        case .write(let url), .skip(let url):
            return url
        }
    }
}

struct OutputPlanner {
    static func outputPlan(
        for sourceURL: URL,
        inputFolder: URL,
        outputFolder: URL,
        options: ProcessingOptions,
        fileManager: FileManager = .default
    ) throws -> OutputPlan {
        let destinationFolder = outputDirectory(
            for: sourceURL,
            inputFolder: inputFolder,
            outputFolder: outputFolder,
            preserveSubfolders: options.preserveSubfolders
        )

        try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let suffix = "_desqueezed_\(factorLabel(options.factor))"
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let preferredURL = destinationFolder
            .appendingPathComponent("\(baseName)\(suffix).\(options.outputFormat.fileExtension)")

        guard fileManager.fileExists(atPath: preferredURL.path) else {
            return .write(preferredURL)
        }

        switch options.collisionMode {
        case .overwrite:
            return .write(preferredURL)
        case .skipExisting:
            return .skip(preferredURL)
        case .autoRename:
            return .write(firstAvailableURL(preferredURL, fileManager: fileManager))
        }
    }

    static func outputURL(
        for sourceURL: URL,
        inputFolder: URL,
        outputFolder: URL,
        options: ProcessingOptions,
        fileManager: FileManager = .default
    ) throws -> URL {
        try outputPlan(
            for: sourceURL,
            inputFolder: inputFolder,
            outputFolder: outputFolder,
            options: options,
            fileManager: fileManager
        ).url
    }

    static func outputDirectory(
        for sourceURL: URL,
        inputFolder: URL,
        outputFolder: URL,
        preserveSubfolders: Bool
    ) -> URL {
        guard preserveSubfolders else { return outputFolder }

        let inputPath = inputFolder.standardizedFileURL.path
        let sourceDirectoryPath = sourceURL.deletingLastPathComponent().standardizedFileURL.path
        guard sourceDirectoryPath.hasPrefix(inputPath) else { return outputFolder }

        let relativePath = sourceDirectoryPath
            .dropFirst(inputPath.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !relativePath.isEmpty else { return outputFolder }
        return outputFolder.appendingPathComponent(relativePath, isDirectory: true)
    }

    static func factorLabel(_ factor: Double) -> String {
        String(format: "%.2fx", factor).replacingOccurrences(of: ".", with: "_")
    }

    private static func firstAvailableURL(_ preferredURL: URL, fileManager: FileManager) -> URL {
        guard fileManager.fileExists(atPath: preferredURL.path) else { return preferredURL }

        let directory = preferredURL.deletingLastPathComponent()
        let baseName = preferredURL.deletingPathExtension().lastPathComponent
        let ext = preferredURL.pathExtension

        for index in 2...999 {
            let candidate = directory.appendingPathComponent("\(baseName)-\(index).\(ext)")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory.appendingPathComponent("\(baseName)-\(UUID().uuidString).\(ext)")
    }
}

enum OutputManifestWriter {
    static let manifestFileName = "PhotoDesqueeze manifest.csv"

    static func write(
        results: [ProcessedImageResult],
        to outputFolder: URL,
        fileManager: FileManager = .default
    ) throws {
        guard !results.isEmpty else { return }

        let url = outputFolder.appendingPathComponent(manifestFileName)
        var rows = [
            [
                "source_path",
                "output_path",
                "status",
                "selected_axis",
                "resolved_axis",
                "source_dimensions",
                "output_dimensions",
                "duration_seconds",
                "camera_make",
                "camera_model",
                "lens_model",
                "capture_date",
                "error"
            ]
        ]

        rows.append(contentsOf: results.map { result in
            [
                result.sourceURL.path,
                result.outputURL?.path ?? "",
                result.status.rawValue,
                result.axisMode?.rawValue ?? "",
                result.resolvedAxis?.rawValue ?? "",
                result.sourceDimensions?.label ?? "",
                result.outputDimensions?.label ?? "",
                result.duration.map { String(format: "%.3f", $0) } ?? "",
                result.metadata?.cameraMake ?? "",
                result.metadata?.cameraModel ?? "",
                result.metadata?.lensModel ?? "",
                result.metadata?.captureDate ?? "",
                result.failureReason ?? ""
            ]
        })

        let csv = rows
            .map { row in row.map(escapeCSVField).joined(separator: ",") }
            .joined(separator: "\n") + "\n"

        try fileManager.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
}

actor ImageBatchProcessor {
    private let context = CIContext(options: [
        .cacheIntermediates: false,
        .name: "PhotoDesqueeze"
    ])
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func processBatch(
        inputFolder: URL,
        outputFolder: URL,
        options: ProcessingOptions,
        progress: @escaping @MainActor (BatchProgress) -> Void
    ) async -> [ProcessedImageResult] {
        let inputAccess = inputFolder.startAccessingSecurityScopedResource()
        let outputAccess = outputFolder.startAccessingSecurityScopedResource()
        defer {
            if inputAccess { inputFolder.stopAccessingSecurityScopedResource() }
            if outputAccess { outputFolder.stopAccessingSecurityScopedResource() }
        }

        do {
            guard options.factor > 0 else { throw PhotoDesqueezeError.invalidFactor }
            try fileManager.createDirectory(at: outputFolder, withIntermediateDirectories: true)

            let files = try ImageFileScanner.imageFiles(
                in: inputFolder,
                recursive: options.recursive,
                fileManager: fileManager
            )
            guard !files.isEmpty else { throw PhotoDesqueezeError.noImageFiles(inputFolder) }

            var batchProgress = BatchProgress(totalCount: files.count)
            await progress(batchProgress)

            for (index, file) in files.enumerated() {
                if Task.isCancelled {
                    for cancelledFile in files[index...] {
                        batchProgress.completedCount += 1
                        batchProgress.results.append(
                            ProcessedImageResult(
                                sourceURL: cancelledFile,
                                outputURL: nil,
                                status: .cancelled,
                                axisMode: options.axis,
                                failureReason: "Cancelled"
                            )
                        )
                    }
                    await progress(batchProgress)
                    break
                }

                batchProgress.currentFileName = file.lastPathComponent
                await progress(batchProgress)

                let result = processOne(
                    sourceURL: file,
                    inputFolder: inputFolder,
                    outputFolder: outputFolder,
                    options: options
                )

                batchProgress.completedCount += 1
                batchProgress.results.append(result)
                await progress(batchProgress)
            }

            batchProgress.currentFileName = nil
            try? OutputManifestWriter.write(
                results: batchProgress.results,
                to: outputFolder,
                fileManager: fileManager
            )
            await progress(batchProgress)
            return batchProgress.results
        } catch {
            let result = ProcessedImageResult(
                sourceURL: inputFolder,
                outputURL: nil,
                status: .failed,
                failureReason: error.localizedDescription
            )
            await progress(BatchProgress(completedCount: 0, totalCount: 0, results: [result]))
            return [result]
        }
    }

    func renderPreview(
        inputFolder: URL,
        options: ProcessingOptions
    ) async throws -> PreviewResult {
        guard options.factor > 0 else { throw PhotoDesqueezeError.invalidFactor }

        let inputAccess = inputFolder.startAccessingSecurityScopedResource()
        defer {
            if inputAccess { inputFolder.stopAccessingSecurityScopedResource() }
        }

        let files = try ImageFileScanner.imageFiles(
            in: inputFolder,
            recursive: options.recursive,
            fileManager: fileManager
        )
        guard let sourceURL = files.first else {
            throw PhotoDesqueezeError.noImageFiles(inputFolder)
        }

        let orientation = imageOrientation(for: sourceURL)
        let image = try loadImage(from: sourceURL, orientation: orientation)
        let normalized = normalizedImage(image)
        let axis = options.axis.resolved(orientation: orientation, imageExtent: normalized.extent)
        let desqueezed = desqueeze(normalized, factor: options.normalizedFactor, axis: axis)

        return PreviewResult(
            sourceURL: sourceURL,
            sourceDimensions: ImageDimensions(extent: normalized.extent),
            outputDimensions: ImageDimensions(extent: desqueezed.extent),
            resolvedAxis: axis,
            originalPNGData: try previewPNGData(for: normalized),
            desqueezedPNGData: try previewPNGData(for: desqueezed)
        )
    }

    private func processOne(
        sourceURL: URL,
        inputFolder: URL,
        outputFolder: URL,
        options: ProcessingOptions
    ) -> ProcessedImageResult {
        let startedAt = Date()
        do {
            let plan = try OutputPlanner.outputPlan(
                for: sourceURL,
                inputFolder: inputFolder,
                outputFolder: outputFolder,
                options: options,
                fileManager: fileManager
            )

            if case .skip(let skippedURL) = plan {
                return ProcessedImageResult(
                    sourceURL: sourceURL,
                    outputURL: skippedURL,
                    status: .skipped,
                    axisMode: options.axis,
                    duration: Date().timeIntervalSince(startedAt)
                )
            }

            let orientation = imageOrientation(for: sourceURL)
            let metadata = imageMetadata(for: sourceURL)
            let image = try loadImage(from: sourceURL, orientation: orientation)
            let normalized = normalizedImage(image)
            let axis = options.axis.resolved(orientation: orientation, imageExtent: normalized.extent)
            let desqueezed = desqueeze(
                normalized,
                factor: options.normalizedFactor,
                axis: axis
            )
            let colorSpace = try makeColorSpace(options.colorSpace)

            guard !Task.isCancelled else {
                return ProcessedImageResult(
                    sourceURL: sourceURL,
                    outputURL: nil,
                    status: .cancelled,
                    sourceDimensions: ImageDimensions(extent: normalized.extent),
                    outputDimensions: ImageDimensions(extent: desqueezed.extent),
                    axisMode: options.axis,
                    resolvedAxis: axis,
                    duration: Date().timeIntervalSince(startedAt),
                    metadata: metadata,
                    failureReason: "Cancelled"
                )
            }

            let outputURL = plan.url
            try writeTIFFAtomically(
                image: desqueezed,
                to: outputURL,
                colorSpace: colorSpace,
                metadata: metadata,
                overwrite: options.collisionMode == .overwrite
            )

            return ProcessedImageResult(
                sourceURL: sourceURL,
                outputURL: outputURL,
                status: .succeeded,
                sourceDimensions: ImageDimensions(extent: normalized.extent),
                outputDimensions: ImageDimensions(extent: desqueezed.extent),
                axisMode: options.axis,
                resolvedAxis: axis,
                duration: Date().timeIntervalSince(startedAt),
                metadata: metadata
            )
        } catch {
            return ProcessedImageResult(
                sourceURL: sourceURL,
                outputURL: nil,
                status: .failed,
                axisMode: options.axis,
                duration: Date().timeIntervalSince(startedAt),
                failureReason: error.localizedDescription
            )
        }
    }

    private func loadImage(
        from url: URL,
        orientation: CGImagePropertyOrientation?
    ) throws -> CIImage {
        if ImageFileScanner.isLikelyRAW(url),
           let rawFilter = CIRAWFilter(imageURL: url) {
            if let orientation {
                rawFilter.orientation = orientation
            }
            if let outputImage = rawFilter.outputImage {
                return outputImage
            }
        }

        if let image = CIImage(
            contentsOf: url,
            options: [.applyOrientationProperty: true]
        ) {
            return image
        }

        throw PhotoDesqueezeError.cannotCreateImage(url)
    }

    private func normalizedImage(_ image: CIImage) -> CIImage {
        image.transformed(
            by: CGAffineTransform(
                translationX: -image.extent.origin.x,
                y: -image.extent.origin.y
            )
        )
    }

    private func desqueeze(
        _ image: CIImage,
        factor: CGFloat,
        axis: DesqueezeAxis
    ) -> CIImage {
        let normalized = normalizedImage(image)
        let targetWidth: CGFloat
        let targetHeight: CGFloat
        let scale: CGFloat
        let aspectRatio: CGFloat

        switch axis {
        case .horizontal, .automatic:
            targetWidth = max(1, (normalized.extent.width * factor).rounded())
            targetHeight = max(1, normalized.extent.height.rounded())
            scale = 1.0
            aspectRatio = factor
        case .vertical:
            targetWidth = max(1, normalized.extent.width.rounded())
            targetHeight = max(1, (normalized.extent.height * factor).rounded())
            scale = factor
            aspectRatio = 1.0 / factor
        }

        return normalized
            .applyingFilter(
                "CILanczosScaleTransform",
                parameters: [
                    kCIInputScaleKey: scale,
                    kCIInputAspectRatioKey: aspectRatio
                ]
            )
            .cropped(to: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    }

    private func previewPNGData(for image: CIImage) throws -> Data {
        let maxDimension: CGFloat = 900
        let extent = image.extent
        let scale = min(1, maxDimension / max(extent.width, extent.height))
        let previewImage = scale < 1
            ? image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale])
            : image

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let cgImage = context.createCGImage(previewImage, from: previewImage.extent) else {
            throw PhotoDesqueezeError.cannotCreateImage(URL(fileURLWithPath: "preview"))
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw PhotoDesqueezeError.cannotCreateImage(URL(fileURLWithPath: "preview"))
        }

        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationEmbedThumbnail: false,
            kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB,
            kCGImagePropertyProfileName: colorSpace.name ?? CGColorSpace.sRGB
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw PhotoDesqueezeError.cannotCreateImage(URL(fileURLWithPath: "preview"))
        }
        return data as Data
    }

    private func writeTIFFAtomically(
        image: CIImage,
        to outputURL: URL,
        colorSpace: CGColorSpace,
        metadata: ImageMetadata,
        overwrite: Bool
    ) throws {
        let folder = outputURL.deletingLastPathComponent()
        let temporaryURL = folder.appendingPathComponent(
            ".\(outputURL.deletingPathExtension().lastPathComponent).\(UUID().uuidString).tmp.tiff"
        )

        do {
            try context.writeTIFFRepresentation(
                of: image,
                to: temporaryURL,
                format: .RGBA16,
                colorSpace: colorSpace,
                options: [.properties: metadata.safeDestinationProperties]
            )

            if fileManager.fileExists(atPath: outputURL.path) {
                if overwrite {
                    try fileManager.removeItem(at: outputURL)
                } else {
                    throw CocoaError(.fileWriteFileExists)
                }
            }

            try fileManager.moveItem(at: temporaryURL, to: outputURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func imageOrientation(for url: URL) -> CGImagePropertyOrientation? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawOrientation = properties[kCGImagePropertyOrientation] as? UInt32 else {
            return nil
        }

        return CGImagePropertyOrientation(rawValue: rawOrientation)
    }

    private func imageMetadata(for url: URL) -> ImageMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .empty
        }

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]

        var safeTIFF = tiff
        safeTIFF.removeValue(forKey: kCGImagePropertyTIFFOrientation)
        safeTIFF[kCGImagePropertyTIFFSoftware] = "PhotoDesqueeze"

        var safeExif = exif
        safeExif.removeValue(forKey: kCGImagePropertyOrientation)

        var destinationProperties: [CFString: Any] = [:]
        if !safeTIFF.isEmpty {
            destinationProperties[kCGImagePropertyTIFFDictionary] = safeTIFF
        }
        if !safeExif.isEmpty {
            destinationProperties[kCGImagePropertyExifDictionary] = safeExif
        }

        return ImageMetadata(
            cameraMake: stringValue(tiff[kCGImagePropertyTIFFMake]),
            cameraModel: stringValue(tiff[kCGImagePropertyTIFFModel]),
            lensModel: stringValue(exif[kCGImagePropertyExifLensModel]),
            captureDate: stringValue(exif[kCGImagePropertyExifDateTimeOriginal])
                ?? stringValue(tiff[kCGImagePropertyTIFFDateTime]),
            iso: stringValue(exif[kCGImagePropertyExifISOSpeedRatings]),
            exposureTime: stringValue(exif[kCGImagePropertyExifExposureTime]),
            aperture: stringValue(exif[kCGImagePropertyExifFNumber]),
            focalLength: stringValue(exif[kCGImagePropertyExifFocalLength]),
            safeDestinationProperties: destinationProperties
        )
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let numbers as [NSNumber]:
            return numbers.map(\.stringValue).joined(separator: ";")
        case let strings as [String]:
            return strings.joined(separator: ";")
        default:
            return nil
        }
    }

    private func makeColorSpace(_ outputColorSpace: OutputColorSpace) throws -> CGColorSpace {
        guard let colorSpace = CGColorSpace(name: outputColorSpace.cgColorSpaceName) else {
            throw PhotoDesqueezeError.cannotCreateColorSpace(outputColorSpace)
        }
        return colorSpace
    }
}
