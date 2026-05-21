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
    @Published var scanSubfolders = true
    @Published var preserveSubfolders = true
    @Published var overwriteExistingFiles = false
    @Published var isProcessing = false
    @Published var progress = BatchProgress()
    @Published var statusMessage = "Select folders to begin."

    private let processor = ImageBatchProcessor()
    private var processingTask: Task<Void, Never>?

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
        inputFolder = FolderPanel.chooseFolder(title: "Choose Input Folder", prompt: "Choose")
    }

    func chooseOutputFolder() {
        guard !isProcessing else { return }
        outputFolder = FolderPanel.chooseFolder(title: "Choose Output Folder", prompt: "Choose")
    }

    func startProcessing() {
        guard let inputFolder, let outputFolder, canStart else { return }

        isProcessing = true
        statusMessage = "Scanning images..."
        progress = BatchProgress()

        let options = ProcessingOptions(
            factor: factor,
            axis: desqueezeAxis,
            colorSpace: outputColorSpace,
            recursive: scanSubfolders,
            preserveSubfolders: preserveSubfolders,
            overwriteExistingFiles: overwriteExistingFiles
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
                completedCount: finalResults.filter { $0.status != .skipped }.count,
                totalCount: max(progress.totalCount, finalResults.count),
                results: finalResults
            )
            isProcessing = false
            processingTask = nil

            let failedCount = finalResults.filter { $0.status == .failed }.count
            let succeededCount = finalResults.filter { $0.status == .succeeded }.count
            statusMessage = failedCount == 0
                ? "Finished \(succeededCount) image\(succeededCount == 1 ? "" : "s")."
                : "Finished with \(failedCount) failure\(failedCount == 1 ? "" : "s")."
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        statusMessage = "Cancelled."
    }

    func revealOutputFolder() {
        guard let outputFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputFolder])
    }
}
