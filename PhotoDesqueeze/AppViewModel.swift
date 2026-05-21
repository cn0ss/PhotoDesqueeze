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
    @Published var preview: PreviewResult?
    @Published var previewMessage = "Select an input folder to preview."
    @Published var progress = BatchProgress()
    @Published var statusMessage = "Select folders to begin."

    private let processor = ImageBatchProcessor()
    private let bookmarkStore = SecurityScopedFolderBookmarkStore()
    private var processingTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?

    init() {
        inputFolder = bookmarkStore.restore(.inputFolder)
        outputFolder = bookmarkStore.restore(.outputFolder)
        if inputFolder != nil {
            refreshPreview()
        }
    }

    var factor: Double {
        if let presetFactor = selectedPreset.factor {
            return presetFactor
        }
        return Double(customFactorText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var canStart: Bool {
        inputFolder != nil && outputFolder != nil && factor > 0 && !isProcessing
    }

    var results: [ProcessedImageResult] {
        progress.results
    }

    func chooseInputFolder() {
        guard !isProcessing else { return }
        guard let url = FolderPanel.chooseFolder(title: "Choose Input Folder", prompt: "Choose") else { return }
        inputFolder = url
        bookmarkStore.save(url, for: .inputFolder)
        refreshPreview()
    }

    func chooseOutputFolder() {
        guard !isProcessing else { return }
        guard let url = FolderPanel.chooseFolder(title: "Choose Output Folder", prompt: "Choose") else { return }
        outputFolder = url
        bookmarkStore.save(url, for: .outputFolder)
    }

    func startProcessing() {
        guard let inputFolder, let outputFolder, canStart else { return }

        previewTask?.cancel()
        isProcessing = true
        statusMessage = "Scanning images..."
        progress = BatchProgress()

        let options = ProcessingOptions(
            factor: factor,
            axis: desqueezeAxis,
            colorSpace: outputColorSpace,
            outputFormat: outputFormat,
            collisionMode: collisionMode,
            recursive: scanSubfolders,
            preserveSubfolders: preserveSubfolders
        )

        processingTask = Task { [processor] in
            let finalResults = await processor.processBatch(
                inputFolder: inputFolder,
                outputFolder: outputFolder,
                options: options
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
        }
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

        guard factor > 0 else {
            previewMessage = "Enter a factor greater than zero."
            isRenderingPreview = false
            return
        }

        isRenderingPreview = true
        previewMessage = "Rendering preview..."

        let options = ProcessingOptions(
            factor: factor,
            axis: desqueezeAxis,
            colorSpace: outputColorSpace,
            outputFormat: outputFormat,
            collisionMode: collisionMode,
            recursive: scanSubfolders,
            preserveSubfolders: preserveSubfolders
        )

        previewTask = Task { [processor] in
            do {
                let result = try await processor.renderPreview(
                    inputFolder: inputFolder,
                    options: options
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

    func revealOutputFolder() {
        guard let outputFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputFolder])
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
