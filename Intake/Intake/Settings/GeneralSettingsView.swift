import SwiftUI
import IntakeCore

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
            Section {
                Button(OrganizeExistingCopy.menuTitle) {
                    model.requestOrganizeExisting()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isOrganizingExisting || model.watchFolderBookmarkLost)
                Button("Activity") {
                    model.openActivity()
                }
            } header: {
                Text("Catch up")
            } footer: {
                Text("Rename and file loose items already in the watch folder root. Files in category folders are left alone. Allowed when Automatic organizing is off; does not turn watching back on.")
            }
            Section {
                Toggle(
                    "Automatic organizing",
                    isOn: Binding(
                        get: { model.automaticOrganizing },
                        set: { model.setAutomaticOrganizing($0) }
                    )
                )
                Picker("Wait before organizing", selection: Binding(
                    get: { model.organizingWait },
                    set: { model.setOrganizingWait($0) }
                )) {
                    ForEach(OrganizingWait.allCases) { wait in
                        Text(wait.title).tag(wait)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!model.automaticOrganizing)
                Toggle("Open at login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                ))
            } header: {
                Text("Organizing")
            } footer: {
                Text("New downloads stay in the folder until this time has passed, so you can open them before Intake files them.")
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
                Text("Keep Intake in the Dock so it’s easy to open Settings. The menu bar shows status without opening a window.")
            }
        }
        .formStyle(.grouped)
    }
}
