import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            if model.watchFolderBookmarkLost {
                Section {
                    Label(
                        "Intake can’t see the watch folder",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(IntakeColor.warning)
                    Button("Choose…") {
                        model.chooseWatchFolder()
                    }
                }
            }
            Section {
                LabeledContent("Folder") {
                    Text(model.watchFolder.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Choose…") {
                        model.chooseWatchFolder()
                    }
                    Button("Show in Finder") {
                        model.revealWatchFolder()
                    }
                }
            } header: {
                Text("Watch folder")
            } footer: {
                Text("Intake waits until a download is stable, then renames it and files it into a typed folder. Folders appear only when needed.")
            }
            Section("Organizing") {
                Toggle("Pause organizing", isOn: Binding(
                    get: { model.isPaused },
                    set: { model.setPaused($0) }
                ))
                Toggle("Open at login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }
            Section {
                Toggle(
                    "Show in Dock",
                    isOn: Binding(
                        get: { model.showsInDock },
                        set: { model.setShowsInDock($0) }
                    )
                )
                Toggle(
                    "Show in menu bar",
                    isOn: Binding(
                        get: { model.showsInMenuBar },
                        set: { model.setShowsInMenuBar($0) }
                    )
                )
            } header: {
                Text("Appearance in macOS")
            } footer: {
                Text("Keep Intake in the Dock so it’s easy to open Settings, Activity, and Cleanup. The menu bar shows status and pause/resume without opening a window.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
