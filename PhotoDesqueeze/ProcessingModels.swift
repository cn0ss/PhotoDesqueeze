import CoreGraphics
import Foundation
import ImageIO

enum DesqueezePreset: String, CaseIterable, Identifiable {
    case x133 = "1.33x"
    case x155 = "1.55x"
    case x160 = "1.60x"
    case x180 = "1.80x"
    case x200 = "2.00x"
    case custom = "Custom"

    var id: String { rawValue }

    var factor: Double? {
        switch self {
        case .x133:
            return 1.33
        case .x155:
            return 1.55
        case .x160:
            return 1.60
        case .x180:
            return 1.80
        case .x200:
            return 2.00
        case .custom:
            return nil
        }
    }
}

enum OutputColorSpace: String, CaseIterable, Identifiable {
    case displayP3 = "Display P3"
    case sRGB = "sRGB"

    var id: String { rawValue }

    var cgColorSpaceName: CFString {
        switch self {
        case .displayP3:
            return CGColorSpace.displayP3
        case .sRGB:
            return CGColorSpace.sRGB
        }
    }
}

enum DesqueezeAxis: String, CaseIterable, Identifiable {
    case automatic = "Auto"
    case horizontal = "Horizontal"
    case vertical = "Vertical"

    var id: String { rawValue }

    func resolved(orientation: CGImagePropertyOrientation?, imageExtent: CGRect) -> DesqueezeAxis {
        switch self {
        case .horizontal, .vertical:
            return self
        case .automatic:
            if orientation?.hasQuarterTurn == true {
                return .vertical
            }
            return imageExtent.height > imageExtent.width ? .vertical : .horizontal
        }
    }
}

struct ProcessingOptions: Equatable {
    var factor: Double
    var axis: DesqueezeAxis
    var colorSpace: OutputColorSpace
    var recursive: Bool
    var preserveSubfolders: Bool
    var overwriteExistingFiles: Bool

    var normalizedFactor: CGFloat {
        CGFloat(max(0.01, factor))
    }
}

private extension CGImagePropertyOrientation {
    var hasQuarterTurn: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored:
            return true
        case .up, .upMirrored, .down, .downMirrored:
            return false
        }
    }
}

enum ProcessingStatus: String {
    case succeeded = "Done"
    case skipped = "Skipped"
    case failed = "Failed"
}

struct ProcessedImageResult: Identifiable, Equatable {
    let id = UUID()
    var sourceURL: URL
    var outputURL: URL?
    var status: ProcessingStatus
    var message: String

    var sourceName: String {
        sourceURL.lastPathComponent
    }
}

struct BatchProgress: Equatable {
    var completedCount: Int = 0
    var totalCount: Int = 0
    var currentFileName: String?
    var results: [ProcessedImageResult] = []

    var fractionCompleted: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
}

enum PhotoDesqueezeError: LocalizedError {
    case invalidFactor
    case noImageFiles(URL)
    case cannotCreateImage(URL)
    case cannotCreateColorSpace(OutputColorSpace)
    case missingOutputFolder(URL)

    var errorDescription: String? {
        switch self {
        case .invalidFactor:
            return "The desqueeze factor must be greater than zero."
        case .noImageFiles(let folder):
            return "No supported image files were found in \(folder.path)."
        case .cannotCreateImage(let url):
            return "Could not decode \(url.lastPathComponent)."
        case .cannotCreateColorSpace(let colorSpace):
            return "Could not create the \(colorSpace.rawValue) output color space."
        case .missingOutputFolder(let url):
            return "The output folder does not exist and could not be created: \(url.path)"
        }
    }
}
