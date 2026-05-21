import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            folderSection
            settingsSection
            preflightSection
            previewSection
            processingSection
            resultsSection
        }
        .padding(24)
        .frame(minWidth: 980, minHeight: 820)
        .onChange(of: model.selectedPreset) { _, _ in model.refreshConfiguration() }
        .onChange(of: model.customFactorText) { _, _ in model.refreshConfiguration() }
        .onChange(of: model.desqueezeAxis) { _, _ in model.refreshConfiguration() }
        .onChange(of: model.outputColorSpace) { _, _ in model.refreshConfiguration() }
        .onChange(of: model.collisionMode) { _, _ in model.refreshConfiguration() }
        .onChange(of: model.scanSubfolders) { _, _ in model.refreshConfiguration(resetPreview: true) }
        .onChange(of: model.preserveSubfolders) { _, _ in model.refreshConfiguration() }
        .alert("Confirm Overwrite", isPresented: $model.showOverwriteConfirmation) {
            Button("Cancel", role: .cancel) {
                model.cancelOverwriteConfirmation()
            }
            Button("Overwrite", role: .destructive) {
                model.confirmOverwriteAndStart()
            }
        } message: {
            Text(model.overwriteConfirmationMessage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PhotoDesqueeze")
                .font(.system(size: 28, weight: .semibold))
            Text("Batch anamorphic desqueeze to 16-bit TIFF.")
                .foregroundStyle(.secondary)
        }
    }

    private var folderSection: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
            FolderRow(
                title: "Input",
                url: model.inputFolder,
                buttonTitle: "Choose Input",
                systemImage: "folder"
            ) {
                model.chooseInputFolder()
            }

            FolderRow(
                title: "Output",
                url: model.outputFolder,
                buttonTitle: "Choose Output",
                systemImage: "folder.badge.plus"
            ) {
                model.chooseOutputFolder()
            }
        }
    }

    private var settingsSection: some View {
        GroupBox("Processing") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Picker("Lens", selection: $model.selectedPreset) {
                        ForEach(DesqueezePreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    if model.selectedPreset == .custom {
                        TextField("Factor", text: $model.customFactorText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 82)
                    }

                    if let message = model.factorValidationMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 12) {
                    Picker("Axis", selection: $model.desqueezeAxis) {
                        ForEach(DesqueezeAxis.allCases) { axis in
                            Text(axis.rawValue).tag(axis)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)

                    Spacer()
                }

                HStack(spacing: 18) {
                    Picker("Color", selection: $model.outputColorSpace) {
                        ForEach(OutputColorSpace.allCases) { colorSpace in
                            Text(colorSpace.rawValue).tag(colorSpace)
                        }
                    }
                    .frame(width: 220)

                    Picker("Existing", selection: $model.collisionMode) {
                        ForEach(CollisionMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .frame(width: 230)

                    Toggle("Scan subfolders", isOn: $model.scanSubfolders)
                    Toggle("Preserve folders", isOn: $model.preserveSubfolders)

                    Spacer()

                    Button {
                        model.resetSettings()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var preflightSection: some View {
        GroupBox("Scan") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(model.preflightMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    if model.isRefreshingPreflight {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let preflight = model.preflight {
                    HStack(spacing: 8) {
                        CountBadge(title: "Files", value: preflight.totalFiles)
                        CountBadge(title: "RAW", value: preflight.rawFiles)
                        CountBadge(title: "Rendered", value: preflight.renderedFiles)
                        CountBadge(title: "Write", value: preflight.plannedWrites)
                        CountBadge(title: "Rename", value: preflight.plannedAutoRenames)
                        CountBadge(title: "Overwrite", value: preflight.plannedOverwrites)
                        CountBadge(title: "Skip", value: preflight.plannedSkips)
                    }

                    ForEach(preflight.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var previewSection: some View {
        GroupBox("Preview") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        model.selectPreviousPreview()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!model.previewSelection.canMovePrevious || model.isProcessing)
                    .help("Previous preview")

                    Text(model.preview?.positionLabel ?? model.previewSelection.positionLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button {
                        model.selectNextPreview()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!model.previewSelection.canMoveNext || model.isProcessing)
                    .help("Next preview")

                    Text(model.previewMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    if model.isRenderingPreview {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        model.refreshPreview()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.previewSelection.selectedURL == nil || model.isProcessing)
                }

                if let preview = model.preview {
                    HStack(spacing: 8) {
                        InfoPill(text: preview.sourceKind.rawValue)
                        InfoPill(text: "\(preview.sourceDimensions.label) -> \(preview.outputDimensions.label)")
                        InfoPill(text: "\(preview.selectedAxis.rawValue) -> \(preview.resolvedAxis.rawValue)")
                    }
                    if let warning = preview.axisWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 12) {
                    PreviewImageView(title: "Original", data: model.preview?.originalPNGData)
                    PreviewImageView(title: "Desqueezed", data: model.preview?.desqueezedPNGData)
                }
                .frame(height: 180)
            }
            .padding(.vertical, 4)
        }
    }

    private var processingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    model.startProcessing()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStart)

                Button {
                    model.retryFailedOnly()
                } label: {
                    Label("Retry Failed", systemImage: "arrow.clockwise")
                }
                .disabled(!model.canRetryFailed)

                Button {
                    model.cancelProcessing()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .disabled(!model.isProcessing)

                Button {
                    model.revealOutputFolder()
                } label: {
                    Label("Reveal Output", systemImage: "arrow.up.forward.app")
                }
                .disabled(model.outputFolder == nil)

                Spacer()

                Text(model.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ProgressView(value: model.progress.fractionCompleted)
                .opacity(model.isProcessing || model.progress.totalCount > 0 ? 1 : 0.35)
        }
    }

    private var resultsSection: some View {
        GroupBox("Results") {
            if model.results.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "photo.stack",
                    description: Text("Processed files will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Filter", selection: $model.resultFilter) {
                        ForEach(ResultFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 440)

                    List(model.filteredResults) { result in
                        ResultRow(result: result) {
                            model.copyError(for: result)
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }
}

private struct CountBadge: View {
    var title: String
    var value: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct InfoPill: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct FolderRow: View {
    var title: String
    var url: URL?
    var buttonTitle: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        GridRow {
            Text(title)
                .font(.headline)

            Text(url?.path ?? "Not selected")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(url == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: action) {
                Label(buttonTitle, systemImage: systemImage)
            }
        }
    }
}

private struct ResultRow: View {
    var result: ProcessedImageResult
    var copyError: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.status.symbolName)
                .foregroundStyle(result.status.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.sourceName)
                    .font(.callout)
                Text("\(result.status.rawValue) | \(result.message) | \(result.dimensionsLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let duration = result.duration {
                Text(String(format: "%.2fs", duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([result.sourceURL])
            } label: {
                Image(systemName: "doc")
            }
            .buttonStyle(.borderless)
            .help("Reveal source")

            if result.failureReason != nil {
                Button {
                    copyError()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy error")
            }

            if let outputURL = result.outputURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Reveal output")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PreviewImageView: View {
    var title: String
    var data: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack {
                Rectangle()
                    .fill(.quaternary.opacity(0.4))

                if let data, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private extension ProcessingStatus {
    var symbolName: String {
        switch self {
        case .succeeded:
            return "checkmark.circle.fill"
        case .skipped:
            return "minus.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .succeeded:
            return .green
        case .skipped:
            return .secondary
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }
}
