import AppKit

enum WatchFolderPicker {
    @MainActor
    static func present(startingAt directory: URL) -> URL? {
        present(
            startingAt: directory,
            prompt: "Choose",
            message: "Choose the folder Intake should watch."
        )
    }
}

enum DestinationFolderPicker {
    @MainActor
    static func present(startingAt directory: URL) -> URL? {
        present(
            startingAt: directory,
            prompt: "File Away",
            message: "Choose a folder to file this item into."
        )
    }
}

@MainActor
private func present(startingAt directory: URL, prompt: String, message: String) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.directoryURL = directory
    panel.prompt = prompt
    panel.message = message
    guard panel.runModal() == .OK else { return nil }
    return panel.url
}
