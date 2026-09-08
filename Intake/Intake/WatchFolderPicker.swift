import AppKit

enum WatchFolderPicker {
    @MainActor
    static func present(startingAt directory: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = directory
        panel.prompt = "Choose"
        panel.message = "Choose the folder Intake should watch."
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
