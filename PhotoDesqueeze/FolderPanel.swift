import AppKit
import Foundation

enum FolderPanel {
    @MainActor
    static func chooseFolder(title: String, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.resolvesAliases = true

        return panel.runModal() == .OK ? panel.url : nil
    }
}
