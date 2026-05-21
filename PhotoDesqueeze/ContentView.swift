import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            folderSection
            settingsSection
            processingSection
            resultsSection
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 560)
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

                    Toggle("Scan subfolders", isOn: $model.scanSubfolders)
                    Toggle("Preserve folders", isOn: $model.preserveSubfolders)
                    Toggle("Overwrite", isOn: $model.overwriteExistingFiles)
                }
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
                List(model.results) { result in
                    ResultRow(result: result)
                }
                .listStyle(.plain)
            }
        }
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.status.symbolName)
                .foregroundStyle(result.status.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.sourceName)
                    .font(.callout)
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.vertical, 4)
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
        }
    }
}
