import AppKit
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var inputFolder: URL?
    @Published var outputFolder: URL?
    @Published var selectedPreset: DesqueezePreset = .x133
    @Published var customFactorText = "1.33"
    @Published var desqueezeAxis: DesqueezeAxis = .automatic
    @Published var outputColorSpace: OutputColorSpace = .displayP3
    @Published var outputFormat: OutputFormat = .tiff16
    @Published var collisionMode: CollisionMode = .autoRename
    @Published var scanSubfolders = true
    @Published var preserveSubfolders = true
    @Published var isProcessing = false
    @Published var isRenderingPreview = false
    @Published var isRefreshingPreflight = false
    @Published var preview: PreviewResult?
    @Published var previewSelection = PreviewSelection()
    @Published var previewMessage = "Select an input folder to preview."
    @Published var preflight: BatchPreflight?
    @Published var preflightMessage = "Select folders to scan."
    @Published var resultFilter: ResultFilter = .all
    @Published var showOverwriteConfirmation = false
    @Published var overwriteConfirmationMessage = ""
    @Published var progress = BatchProgress()
    @Published var statusMessage = "Select folders to begin."

    private let processor = ImageBatchProcessor()
    private let bookmarkStore = SecurityScopedFolderBookmarkStore()
    private let settingsStore = ProcessingSettingsStore()
    private var processingTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var preflightTask: Task<Void, Never>?
    private var pendingSourceURLs: [URL]?
    private var pendingProcessingLabel = "batch"

    init() {
        restoreSettings()
        inputFolder = bookmarkStore.restore(.inputFolder)
        outputFolder = bookmarkStore.restore(.outputFolder)
        if inputFolder != nil {
            refreshConfiguration(resetPreview: true)
        }
    }

    var factorValidation: FactorValidation {
        if let presetFactor = selectedPreset.factor {
            return .valid(presetFactor)
        }
        return FactorInputParser.validate(customFactorText)
    }

    var factor: Double {
        factorValidation.factor ?? 0
    }

    var canStart: Bool {
        inputFolder != nil
            && outputFolder != nil
            && factorValidation.isValid
            && !isProcessing
            && (preflight?.totalFiles ?? 0) > 0
    }

    var canRetryFailed: Bool {
        !retryFailedSources.isEmpty
            && inputFolder != nil
            && outputFolder != nil
            && factorValidation.isValid
            && !isProcessing
    }

    var results: [ProcessedImageResult] {
        progress.results
    }

    var filteredResults: [ProcessedImageResult] {
        results.filter { resultFilter.includes($0) }
    }

    var retryFailedSources: [URL] {
        ResultRetrySelection.sources(from: results)
    }

    var factorValidationMessage: String? {
        factorValidation.message
    }

    func chooseInputFolder() {
        guard !isProcessing else { return }
        guard let url = FolderPanel.chooseFolder(title: "Choose Input Folder", prompt: "Choose") else { return }
        inputFolder = url
        bookmarkStore.save(url, for: .inputFolder)
        refreshConfiguration(resetPreview: true)
    }

    func chooseOutputFolder() {
        guard !isProcessing else { return }
        guard let url = FolderPanel.chooseFolder(title: "Choose Output Folder", prompt: "Choose") else { return }
        outputFolder = url
        bookmarkStore.save(url, for: .outputFolder)
        refreshConfiguration(resetPreview: false)
    }

    func refreshConfiguration(resetPreview: Bool = false) {
        saveSettings()
        preflightTask?.cancel()

        guard let inputFolder else {
            preflight = nil
            previewSelection.replaceFiles([], resetIndex: true)
            preview = nil
            previewMessage = "Select an input folder to preview."
            preflightMessage = "Select folders to scan."
            isRefreshingPreflight = false
            return
        }

        guard factorValidation.isValid else {
            preflight = nil
            previewSelection.replaceFiles([], resetIndex: true)
            preview = nil
            previewMessage = factorValidation.message ?? "Enter a valid factor."
            preflightMessage = factorValidation.message ?? "Enter a valid factor."
            isRefreshingPreflight = false
            return
        }

        isRefreshingPreflight = true
        preflightMessage = outputFolder == nil ? "Scanning input folder..." : "Checking outputs..."

        let options = processingOptions()
        let outputFolder = outputFolder

        preflightTask = Task { [processor] in
            do {
                if let outputFolder {
                    let result = try await processor.preflight(
                        inputFolder: inputFolder,
                        outputFolder: outputFolder,
                        options: options
                    )
                    guard !Task.isCancelled else { return }
                    preflight = result
                    previewSelection.replaceFiles(result.sourceURLs, resetIndex: resetPreview)
                    preflightMessage = result.summary
                } else {
                    let files = try await processor.scanImages(
                        inputFolder: inputFolder,
                        recursive: options.recursive
                    )
                    guard !Task.isCancelled else { return }
                    preflight = nil
                    previewSelection.replaceFiles(files, resetIndex: resetPreview)
                    preflightMessage = "\(files.count) supported file\(files.count == 1 ? "" : "s"). Select an output folder for preflight."
                }
                isRefreshingPreflight = false
                refreshPreview()
            } catch {
                guard !Task.isCancelled else { return }
                preflight = nil
                previewSelection.replaceFiles([], resetIndex: true)
                preview = nil
                previewMessage = error.localizedDescription
                preflightMessage = error.localizedDescription
                isRefreshingPreflight = false
            }
        }
    }

    func startProcessing() {
        guard canStart else { return }
        beginProcessing(
            sourceURLs: preflight?.sourceURLs,
            label: "batch",
            confirmedOverwrite: false
        )
    }

    func retryFailedOnly() {
        guard canRetryFailed else { return }
        beginProcessing(
            sourceURLs: retryFailedSources,
            label: "failed files",
            confirmedOverwrite: false
        )
    }

    func confirmOverwriteAndStart() {
        let sourceURLs = pendingSourceURLs
        let label = pendingProcessingLabel
        pendingSourceURLs = nil
        pendingProcessingLabel = "batch"
        showOverwriteConfirmation = false
        beginProcessing(
            sourceURLs: sourceURLs,
            label: label,
            confirmedOverwrite: true
        )
    }

    func cancelOverwriteConfirmation() {
        pendingSourceURLs = nil
        pendingProcessingLabel = "batch"
        showOverwriteConfirmation = false
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        statusMessage = "Cancelled."
    }

    func refreshPreview() {
        previewTask?.cancel()
        preview = nil

        guard let inputFolder else {
            previewMessage = "Select an input folder to preview."
            isRenderingPreview = false
            return
        }

        guard factorValidation.isValid else {
            previewMessage = factorValidation.message ?? "Enter a valid factor."
            isRenderingPreview = false
            return
        }

        guard let sourceURL = previewSelection.selectedURL else {
            previewMessage = "No supported image selected."
            isRenderingPreview = false
            return
        }

        isRenderingPreview = true
        previewMessage = "Rendering preview..."

        let options = processingOptions()
        let sourceIndex = previewSelection.selectedIndex
        let totalSources = previewSelection.totalCount

        previewTask = Task { [processor] in
            do {
                let result = try await processor.renderPreview(
                    sourceURL: sourceURL,
                    inputFolder: inputFolder,
                    options: options,
                    sourceIndex: sourceIndex,
                    totalSources: totalSources
                )
                guard !Task.isCancelled else { return }
                preview = result
                previewMessage = result.summary
            } catch {
                guard !Task.isCancelled else { return }
                preview = nil
                previewMessage = error.localizedDescription
            }
            isRenderingPreview = false
        }
    }

    func selectPreviousPreview() {
        previewSelection.move(by: -1)
        refreshPreview()
    }

    func selectNextPreview() {
        previewSelection.move(by: 1)
        refreshPreview()
    }

    func resetSettings() {
        selectedPreset = .x133
        customFactorText = "1.33"
        desqueezeAxis = .automatic
        outputColorSpace = .displayP3
        outputFormat = .tiff16
        collisionMode = .autoRename
        scanSubfolders = true
        preserveSubfolders = true
        resultFilter = .all
        refreshConfiguration(resetPreview: false)
    }

    func revealOutputFolder() {
        guard let outputFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputFolder])
    }

    func copyError(for result: ProcessedImageResult) {
        guard let failureReason = result.failureReason, !failureReason.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(failureReason, forType: .string)
    }

    private func beginProcessing(
        sourceURLs: [URL]?,
        label: String,
        confirmedOverwrite: Bool
    ) {
        guard let inputFolder, let outputFolder, factorValidation.isValid, !isProcessing else { return }

        if collisionMode == .overwrite && !confirmedOverwrite {
            pendingSourceURLs = sourceURLs
            pendingProcessingLabel = label
            overwriteConfirmationMessage = "Overwrite existing output files for this \(label)?"
            showOverwriteConfirmation = true
            return
        }

        previewTask?.cancel()
        preflightTask?.cancel()
        isProcessing = true
        statusMessage = label == "batch" ? "Scanning images..." : "Retrying failed files..."
        progress = BatchProgress()

        let options = processingOptions()

        processingTask = Task { [processor] in
            let finalResults = await processor.processBatch(
                inputFolder: inputFolder,
                outputFolder: outputFolder,
                options: options,
                sourceURLs: sourceURLs
            ) { [weak self] progress in
                self?.progress = progress
                if let currentFileName = progress.currentFileName {
                    self?.statusMessage = "Processing \(currentFileName)"
                } else if progress.totalCount > 0 {
                    self?.statusMessage = "\(progress.completedCount) of \(progress.totalCount) images processed."
                } else {
                    self?.statusMessage = progress.results.first?.message ?? "No images processed."
                }
            }

            progress = BatchProgress(
                completedCount: finalResults.count,
                totalCount: max(progress.totalCount, finalResults.count),
                results: finalResults
            )
            isProcessing = false
            processingTask = nil

            let failedCount = finalResults.filter { $0.status == .failed }.count
            let succeededCount = finalResults.filter { $0.status == .succeeded }.count
            let skippedCount = finalResults.filter { $0.status == .skipped }.count
            let cancelledCount = finalResults.filter { $0.status == .cancelled }.count
            statusMessage = "Finished \(succeededCount) done, \(skippedCount) skipped, \(failedCount) failed, \(cancelledCount) cancelled."
            refreshConfiguration(resetPreview: false)
        }
    }

    private func processingOptions() -> ProcessingOptions {
        ProcessingOptions(
            factor: factor,
            axis: desqueezeAxis,
            colorSpace: outputColorSpace,
            outputFormat: outputFormat,
            collisionMode: collisionMode,
            recursive: scanSubfolders,
            preserveSubfolders: preserveSubfolders
        )
    }

    private func restoreSettings() {
        let settings = settingsStore.restore()
        selectedPreset = settings.selectedPreset
        customFactorText = settings.customFactorText
        desqueezeAxis = settings.desqueezeAxis
        outputColorSpace = settings.outputColorSpace
        outputFormat = settings.outputFormat
        collisionMode = settings.collisionMode
        scanSubfolders = settings.scanSubfolders
        preserveSubfolders = settings.preserveSubfolders
    }

    private func saveSettings() {
        settingsStore.save(
            ProcessingSettingsSnapshot(
                selectedPreset: selectedPreset,
                customFactorText: customFactorText,
                desqueezeAxis: desqueezeAxis,
                outputColorSpace: outputColorSpace,
                outputFormat: outputFormat,
                collisionMode: collisionMode,
                scanSubfolders: scanSubfolders,
                preserveSubfolders: preserveSubfolders
            )
        )
    }
}

struct ProcessingSettingsSnapshot {
    var selectedPreset: DesqueezePreset = .x133
    var customFactorText: String = "1.33"
    var desqueezeAxis: DesqueezeAxis = .automatic
    var outputColorSpace: OutputColorSpace = .displayP3
    var outputFormat: OutputFormat = .tiff16
    var collisionMode: CollisionMode = .autoRename
    var scanSubfolders: Bool = true
    var preserveSubfolders: Bool = true
}

final class ProcessingSettingsStore {
    private enum Key {
        static let selectedPreset = "PhotoDesqueeze.selectedPreset"
        static let customFactorText = "PhotoDesqueeze.customFactorText"
        static let desqueezeAxis = "PhotoDesqueeze.desqueezeAxis"
        static let outputColorSpace = "PhotoDesqueeze.outputColorSpace"
        static let outputFormat = "PhotoDesqueeze.outputFormat"
        static let collisionMode = "PhotoDesqueeze.collisionMode"
        static let scanSubfolders = "PhotoDesqueeze.scanSubfolders"
        static let preserveSubfolders = "PhotoDesqueeze.preserveSubfolders"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restore() -> ProcessingSettingsSnapshot {
        ProcessingSettingsSnapshot(
            selectedPreset: enumValue(DesqueezePreset.self, for: Key.selectedPreset, default: .x133),
            customFactorText: defaults.string(forKey: Key.customFactorText) ?? "1.33",
            desqueezeAxis: enumValue(DesqueezeAxis.self, for: Key.desqueezeAxis, default: .automatic),
            outputColorSpace: enumValue(OutputColorSpace.self, for: Key.outputColorSpace, default: .displayP3),
            outputFormat: enumValue(OutputFormat.self, for: Key.outputFormat, default: .tiff16),
            collisionMode: enumValue(CollisionMode.self, for: Key.collisionMode, default: .autoRename),
            scanSubfolders: defaults.object(forKey: Key.scanSubfolders) as? Bool ?? true,
            preserveSubfolders: defaults.object(forKey: Key.preserveSubfolders) as? Bool ?? true
        )
    }

    func save(_ settings: ProcessingSettingsSnapshot) {
        defaults.set(settings.selectedPreset.rawValue, forKey: Key.selectedPreset)
        defaults.set(settings.customFactorText, forKey: Key.customFactorText)
        defaults.set(settings.desqueezeAxis.rawValue, forKey: Key.desqueezeAxis)
        defaults.set(settings.outputColorSpace.rawValue, forKey: Key.outputColorSpace)
        defaults.set(settings.outputFormat.rawValue, forKey: Key.outputFormat)
        defaults.set(settings.collisionMode.rawValue, forKey: Key.collisionMode)
        defaults.set(settings.scanSubfolders, forKey: Key.scanSubfolders)
        defaults.set(settings.preserveSubfolders, forKey: Key.preserveSubfolders)
    }

    private func enumValue<T: RawRepresentable>(
        _ type: T.Type,
        for key: String,
        default defaultValue: T
    ) -> T where T.RawValue == String {
        guard let rawValue = defaults.string(forKey: key),
              let value = T(rawValue: rawValue) else {
            return defaultValue
        }
        return value
    }
}

final class SecurityScopedFolderBookmarkStore {
    enum BookmarkKey: String {
        case inputFolder = "PhotoDesqueeze.inputFolderBookmark"
        case outputFolder = "PhotoDesqueeze.outputFolderBookmark"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ url: URL, for key: BookmarkKey) {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(data, forKey: key.rawValue)
        } catch {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    func restore(_ key: BookmarkKey) -> URL? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                save(url, for: key)
            }
            return url
        } catch {
            defaults.removeObject(forKey: key.rawValue)
            return nil
        }
    }
}
