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
        resolution(orientation: orientation, imageExtent: imageExtent).resolvedAxis
    }

    func resolution(orientation: CGImagePropertyOrientation?, imageExtent: CGRect) -> AxisResolution {
        switch self {
        case .horizontal, .vertical:
            return AxisResolution(selectedAxis: self, resolvedAxis: self)
        case .automatic:
            if orientation?.hasQuarterTurn == true {
                return AxisResolution(selectedAxis: self, resolvedAxis: .vertical)
            }
            let resolvedAxis: DesqueezeAxis = imageExtent.height > imageExtent.width ? .vertical : .horizontal
            let warning = resolvedAxis == .vertical && orientation == nil
                ? "Auto chose vertical from portrait dimensions because no orientation metadata was found."
                : nil
            return AxisResolution(
                selectedAxis: self,
                resolvedAxis: resolvedAxis,
                warningMessage: warning
            )
        }
    }
}

struct AxisResolution: Equatable {
    var selectedAxis: DesqueezeAxis
    var resolvedAxis: DesqueezeAxis
    var warningMessage: String?
}

enum FactorValidation: Equatable {
    case valid(Double)
    case empty
    case notNumeric
    case nonPositive

    var factor: Double? {
        if case .valid(let factor) = self {
            return factor
        }
        return nil
    }

    var message: String? {
        switch self {
        case .valid:
            return nil
        case .empty:
            return "Enter a desqueeze factor."
        case .notNumeric:
            return "Factor must be a number."
        case .nonPositive:
            return "Factor must be greater than zero."
        }
    }

    var isValid: Bool {
        factor != nil
    }
}

enum FactorInputParser {
    static func validate(_ text: String) -> FactorValidation {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard !normalized.isEmpty else { return .empty }
        guard let value = Double(normalized) else { return .notNumeric }
        guard value > 0 else { return .nonPositive }
        return .valid(value)
    }
}

enum CollisionMode: String, CaseIterable, Identifiable {
    case autoRename = "Auto Rename"
    case overwrite = "Overwrite"
    case skipExisting = "Skip Existing"

    var id: String { rawValue }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case tiff16 = "16-bit TIFF"

    var id: String { rawValue }
    var fileExtension: String { "tiff" }
}

enum ImageSourceKind: String, Equatable {
    case raw = "RAW"
    case rendered = "Rendered"
}

enum PlannedOutputAction: String, Equatable {
    case write = "Write"
    case autoRename = "Auto Rename"
    case overwrite = "Overwrite"
    case skip = "Skip"
}

struct PreflightFilePlan: Equatable {
    var sourceURL: URL
    var outputURL: URL
    var sourceKind: ImageSourceKind
    var action: PlannedOutputAction
}

struct BatchPreflight: Equatable {
    var filePlans: [PreflightFilePlan]
    var warnings: [String] = []

    var sourceURLs: [URL] {
        filePlans.map(\.sourceURL)
    }

    var totalFiles: Int {
        filePlans.count
    }

    var rawFiles: Int {
        filePlans.filter { $0.sourceKind == .raw }.count
    }

    var renderedFiles: Int {
        filePlans.filter { $0.sourceKind == .rendered }.count
    }

    var plannedWrites: Int {
        count(.write)
    }

    var plannedAutoRenames: Int {
        count(.autoRename)
    }

    var plannedOverwrites: Int {
        count(.overwrite)
    }

    var plannedSkips: Int {
        count(.skip)
    }

    var summary: String {
        guard totalFiles > 0 else { return "No supported images found." }
        return "\(totalFiles) files: \(rawFiles) RAW, \(renderedFiles) rendered. \(plannedWrites) write, \(plannedAutoRenames) rename, \(plannedOverwrites) overwrite, \(plannedSkips) skip."
    }

    private func count(_ action: PlannedOutputAction) -> Int {
        filePlans.filter { $0.action == action }.count
    }
}

struct PreviewSelection: Equatable {
    private(set) var files: [URL] = []
    private(set) var selectedIndex: Int = 0

    var selectedURL: URL? {
        guard files.indices.contains(selectedIndex) else { return nil }
        return files[selectedIndex]
    }

    var totalCount: Int {
        files.count
    }

    var positionLabel: String {
        guard !files.isEmpty else { return "0 of 0" }
        return "\(selectedIndex + 1) of \(files.count)"
    }

    var canMovePrevious: Bool {
        selectedIndex > 0
    }

    var canMoveNext: Bool {
        selectedIndex + 1 < files.count
    }

    mutating func replaceFiles(_ newFiles: [URL], resetIndex: Bool) {
        files = newFiles
        if resetIndex {
            selectedIndex = 0
        } else {
            selectedIndex = min(selectedIndex, max(0, newFiles.count - 1))
        }
    }

    mutating func move(by delta: Int) {
        guard !files.isEmpty else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(0, selectedIndex + delta), files.count - 1)
    }
}

struct ImageDimensions: Equatable {
    var width: Int
    var height: Int

    init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
    }

    init(extent: CGRect) {
        self.init(
            width: Int(max(0, extent.width).rounded()),
            height: Int(max(0, extent.height).rounded())
        )
    }

    var label: String {
        guard width > 0 && height > 0 else { return "-" }
        return "\(width)x\(height)"
    }
}

struct ImageMetadata: Equatable, @unchecked Sendable {
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var captureDate: String?
    var iso: String?
    var exposureTime: String?
    var aperture: String?
    var focalLength: String?
    var safeDestinationProperties: [CFString: Any]

    static let empty = ImageMetadata(safeDestinationProperties: [:])

    init(
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        captureDate: String? = nil,
        iso: String? = nil,
        exposureTime: String? = nil,
        aperture: String? = nil,
        focalLength: String? = nil,
        safeDestinationProperties: [CFString: Any] = [:]
    ) {
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.captureDate = captureDate
        self.iso = iso
        self.exposureTime = exposureTime
        self.aperture = aperture
        self.focalLength = focalLength
        self.safeDestinationProperties = safeDestinationProperties
    }

    static func == (lhs: ImageMetadata, rhs: ImageMetadata) -> Bool {
        lhs.cameraMake == rhs.cameraMake
            && lhs.cameraModel == rhs.cameraModel
            && lhs.lensModel == rhs.lensModel
            && lhs.captureDate == rhs.captureDate
            && lhs.iso == rhs.iso
            && lhs.exposureTime == rhs.exposureTime
            && lhs.aperture == rhs.aperture
            && lhs.focalLength == rhs.focalLength
    }
}

struct ProcessingOptions: Equatable {
    var factor: Double
    var axis: DesqueezeAxis
    var colorSpace: OutputColorSpace
    var outputFormat: OutputFormat
    var collisionMode: CollisionMode
    var recursive: Bool
    var preserveSubfolders: Bool

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
    case cancelled = "Cancelled"
}

struct ProcessedImageResult: Identifiable, Equatable {
    let id = UUID()
    var sourceURL: URL
    var outputURL: URL?
    var status: ProcessingStatus
    var sourceDimensions: ImageDimensions?
    var outputDimensions: ImageDimensions?
    var axisMode: DesqueezeAxis?
    var resolvedAxis: DesqueezeAxis?
    var duration: TimeInterval?
    var metadata: ImageMetadata?
    var failureReason: String?

    var sourceName: String {
        sourceURL.lastPathComponent
    }

    var dimensionsLabel: String {
        guard let sourceDimensions else { return "-" }
        return "\(sourceDimensions.label) -> \(outputDimensions?.label ?? "-")"
    }

    var message: String {
        switch status {
        case .succeeded:
            let outputName = outputURL?.lastPathComponent ?? "output"
            let axis = resolvedAxis?.rawValue.lowercased() ?? "unknown"
            return "Wrote \(outputName) (\(axis))"
        case .skipped:
            return "Skipped existing file"
        case .failed:
            return failureReason ?? "Failed"
        case .cancelled:
            return "Cancelled"
        }
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

    var succeededCount: Int {
        results.filter { $0.status == .succeeded }.count
    }

    var failedCount: Int {
        results.filter { $0.status == .failed }.count
    }

    var skippedCount: Int {
        results.filter { $0.status == .skipped }.count
    }

    var cancelledCount: Int {
        results.filter { $0.status == .cancelled }.count
    }
}

struct PreviewResult: Equatable {
    var sourceURL: URL
    var sourceIndex: Int
    var totalSources: Int
    var sourceKind: ImageSourceKind
    var sourceDimensions: ImageDimensions
    var outputDimensions: ImageDimensions
    var selectedAxis: DesqueezeAxis
    var resolvedAxis: DesqueezeAxis
    var axisWarning: String?
    var originalPNGData: Data
    var desqueezedPNGData: Data

    var summary: String {
        "\(sourceURL.lastPathComponent): \(sourceDimensions.label) -> \(outputDimensions.label), \(resolvedAxis.rawValue.lowercased())"
    }

    var positionLabel: String {
        "\(sourceIndex + 1) of \(max(totalSources, 1))"
    }
}

enum ResultFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case succeeded = "Done"
    case skipped = "Skipped"
    case failed = "Failed"
    case cancelled = "Cancelled"

    var id: String { rawValue }

    func includes(_ result: ProcessedImageResult) -> Bool {
        switch self {
        case .all:
            return true
        case .succeeded:
            return result.status == .succeeded
        case .skipped:
            return result.status == .skipped
        case .failed:
            return result.status == .failed
        case .cancelled:
            return result.status == .cancelled
        }
    }
}

enum ResultRetrySelection {
    static func sources(from results: [ProcessedImageResult]) -> [URL] {
        results
            .filter { $0.status == .failed }
            .map(\.sourceURL)
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
