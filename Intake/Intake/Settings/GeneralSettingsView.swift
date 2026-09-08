import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Watch folder") {
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
                Text("Intake waits until a download is stable, then renames it and files it into a typed folder. Folders are created only when the first matching file needs them.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
