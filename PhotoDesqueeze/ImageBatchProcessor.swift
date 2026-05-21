import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

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

struct OutputPlanner {
    static func outputURL(
        for sourceURL: URL,
        inputFolder: URL,
        outputFolder: URL,
        options: ProcessingOptions,
        fileManager: FileManager = .default
    ) throws -> URL {
        let destinationFolder = outputDirectory(
            for: sourceURL,
            inputFolder: inputFolder,
            outputFolder: outputFolder,
            preserveSubfolders: options.preserveSubfolders
        )

        try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let suffix = "_desqueezed_\(factorLabel(options.factor))"
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let preferredURL = destinationFolder.appendingPathComponent("\(baseName)\(suffix).tiff")

        guard !options.overwriteExistingFiles else { return preferredURL }
        return firstAvailableURL(preferredURL, fileManager: fileManager)
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

            for file in files {
                if Task.isCancelled {
                    batchProgress.currentFileName = nil
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
            await progress(batchProgress)
            return batchProgress.results
        } catch {
            let result = ProcessedImageResult(
                sourceURL: inputFolder,
                outputURL: nil,
                status: .failed,
                message: error.localizedDescription
            )
            await progress(BatchProgress(completedCount: 0, totalCount: 0, results: [result]))
            return [result]
        }
    }

    private func processOne(
        sourceURL: URL,
        inputFolder: URL,
        outputFolder: URL,
        options: ProcessingOptions
    ) -> ProcessedImageResult {
        do {
            let outputURL = try OutputPlanner.outputURL(
                for: sourceURL,
                inputFolder: inputFolder,
                outputFolder: outputFolder,
                options: options,
                fileManager: fileManager
            )

            let orientation = imageOrientation(for: sourceURL)
            let image = try loadImage(from: sourceURL, orientation: orientation)
            let axis = options.axis.resolved(orientation: orientation, imageExtent: image.extent)
            let desqueezed = desqueeze(
                image,
                factor: options.normalizedFactor,
                axis: axis
            )
            let colorSpace = try makeColorSpace(options.colorSpace)

            try context.writeTIFFRepresentation(
                of: desqueezed,
                to: outputURL,
                format: .RGBA16,
                colorSpace: colorSpace
            )

            return ProcessedImageResult(
                sourceURL: sourceURL,
                outputURL: outputURL,
                status: .succeeded,
                message: "Wrote \(outputURL.lastPathComponent) (\(axis.rawValue.lowercased()))"
            )
        } catch {
            return ProcessedImageResult(
                sourceURL: sourceURL,
                outputURL: nil,
                status: .failed,
                message: error.localizedDescription
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

    private func desqueeze(
        _ image: CIImage,
        factor: CGFloat,
        axis: DesqueezeAxis
    ) -> CIImage {
        let normalized = image.transformed(
            by: CGAffineTransform(
                translationX: -image.extent.origin.x,
                y: -image.extent.origin.y
            )
        )
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

    private func imageOrientation(for url: URL) -> CGImagePropertyOrientation? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawOrientation = properties[kCGImagePropertyOrientation] as? UInt32 else {
            return nil
        }

        return CGImagePropertyOrientation(rawValue: rawOrientation)
    }

    private func makeColorSpace(_ outputColorSpace: OutputColorSpace) throws -> CGColorSpace {
        guard let colorSpace = CGColorSpace(name: outputColorSpace.cgColorSpaceName) else {
            throw PhotoDesqueezeError.cannotCreateColorSpace(outputColorSpace)
        }
        return colorSpace
    }
}
