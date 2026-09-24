import SwiftUI
import IntakeCore

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    /// Which watch folder the Organizing section edits.
    @State private var editingProfileID: String?
    @State private var pendingRemoval: WatchFolderProfile?

    var body: some View {
        Form {
            Section {
                ForEach(model.watchFolderControllers, id: \.profileID) { controller in
                    WatchFolderRow(controller: controller) {
                        pendingRemoval = controller.profile
                    }
                }
                AddWatchFolderControl()
            } header: {
                Text(model.hasMultipleWatchFolders ? "Watch folders" : "Watch folder")
            } footer: {
                Text("Renames a stable download in place, then files it into a typed folder created only when needed. Up to \(WatchFolderProfile.softCap) folders, and they can’t overlap.")
            }
            Section {
                OrganizeExistingMenu()
                    .buttonStyle(.borderedProminent)
                Button("Activity") {
                    model.openActivity()
                }
            } header: {
                Text("Catch up")
            } footer: {
                Text("Rename and file loose items already in the watch folder root. Files in category folders are left alone. Allowed when Automatic organizing is off; does not turn watching back on.")
            }
            if let profile = editingProfile {
                organizingSection(for: profile)
            }
            notificationsSection
            startupSection
            appearanceSection
        }
        .formStyle(.grouped)
        .alert(
            "Can’t use this folder",
            isPresented: Binding(
                get: { model.watchFolderAlertMessage != nil },
                set: { if !$0 { model.watchFolderAlertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.watchFolderAlertMessage ?? "")
        }
        .confirmationDialog(
            "Stop watching “\(pendingRemoval?.displayName ?? "")”?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Stop Watching", role: .destructive) {
                if let id = pendingRemoval?.id {
                    model.removeWatchFolder(id: id)
                    if editingProfileID == id {
                        editingProfileID = nil
                    }
                }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            Text("Files already filed stay where they are. Rules that only apply to this folder are turned off.")
        }
    }

    private var editingProfile: WatchFolderProfile? {
        editingProfileID.flatMap(model.watchFolderProfile(id:)) ?? model.watchFolderProfiles.first
    }

    @ViewBuilder
    private func organizingSection(for profile: WatchFolderProfile) -> some View {
        Section {
            if model.hasMultipleWatchFolders {
                Picker("Folder", selection: Binding(
                    get: { profile.id },
                    set: { editingProfileID = $0 }
                )) {
                    ForEach(model.watchFolderProfiles) { candidate in
                        Text(candidate.displayName).tag(candidate.id)
                    }
                }
                .pickerStyle(.menu)
                WatchFolderNameField(profile: profile)
                    .id(profile.id)
            }
            Toggle(
                "Automatic organizing",
                isOn: Binding(
                    get: { profile.isOrganizing },
                    set: { model.setAutomaticOrganizing($0, for: profile.id) }
                )
            )
            Toggle(
                RenameOnStableCopy.toggleTitle,
                isOn: Binding(
                    get: { profile.renameWhenDownloadFinishes },
                    set: { model.setRenameWhenDownloadFinishes($0, for: profile.id) }
                )
            )
            Picker("Wait before organizing", selection: Binding(
                get: { profile.organizingWait },
                set: { model.setOrganizingWait($0, for: profile.id) }
            )) {
                ForEach(OrganizingWait.allCases) { wait in
                    Text(wait.title).tag(wait)
                }
            }
            .pickerStyle(.menu)
            .disabled(!profile.isOrganizing)
        } header: {
            Text("Organizing")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(RenameOnStableCopy.footer)
                Text("New downloads stay in the folder until this time has passed, so you can open them before Intake files them.")
                if model.hasMultipleWatchFolders {
                    Text("Each watch folder has its own settings.")
                }
            }
        }
    }

    private var startupSection: some View {
        Section {
            Toggle("Open at login", isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: { model.setLaunchAtLogin($0) }
            ))
        } header: {
            Text("Startup")
        } footer: {
            Text("Opens Intake in the background when you log in.")
        }
    }

    private var notificationsSection: some View {
        Section {
            Toggle(
                "Notifications",
                isOn: Binding(
                    get: { model.notificationsEnabled },
                    set: { model.notificationsEnabled = $0 }
                )
            )
            Toggle("Filed", isOn: Binding(
                get: { model.notifyOnFiled },
                set: { model.notifyOnFiled = $0 }
            ))
            .disabled(!model.notificationsEnabled)
            Toggle("Errors", isOn: Binding(
                get: { model.notifyOnErrors },
                set: { model.notifyOnErrors = $0 }
            ))
            .disabled(!model.notificationsEnabled)
            Toggle("Cleanup", isOn: Binding(
                get: { model.notifyOnCleanup },
                set: { model.notifyOnCleanup = $0 }
            ))
            .disabled(!model.notificationsEnabled)
        } header: {
            Text("Notifications")
        } footer: {
            Text("Off by default. When on, Intake asks for notification permission and sends a digest for what it filed, any errors, and new Cleanup items — never one notification per file. Errors are sent on their own, at most once a minute. Focus and system notification settings still apply.")
        }
    }

    private var appearanceSection: some View {
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
}

/// One watch folder: name, path, status, and a menu of per-folder actions.
/// Lost access shows inline with a Grant Access action.
private struct WatchFolderRow: View {
    @Environment(AppModel.self) private var model
    var controller: WatchFolderController
    var onRemove: () -> Void

    var body: some View {
        let profile = controller.profile
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: controller.accessLost ? "exclamationmark.triangle.fill" : "folder")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(controller.accessLost ? AnyShapeStyle(IntakeColor.warning) : AnyShapeStyle(.secondary))
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                    Text(controller.folder.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Text(statusText(for: profile))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Menu {
                    Button("Show in Finder") {
                        model.revealWatchFolder(id: controller.profileID)
                    }
                    Button("Change Folder…") {
                        model.changeWatchFolder(id: controller.profileID)
                    }
                    Button(profile.isPaused ? "Resume" : "Pause") {
                        model.setWatchFolderPaused(!profile.isPaused, for: controller.profileID)
                    }
                    Divider()
                    Button("Remove…", role: .destructive) {
                        onRemove()
                    }
                    .disabled(!model.hasMultipleWatchFolders)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Actions for \(profile.displayName)")
            }
            if controller.accessLost {
                HStack {
                    Text("Intake can’t see this folder")
                        .foregroundStyle(IntakeColor.warning)
                    Spacer()
                    Button("Grant Access…") {
                        model.changeWatchFolder(id: controller.profileID)
                    }
                }
                .font(.callout)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func statusText(for profile: WatchFolderProfile) -> String {
        if controller.accessLost {
            return "Needs access"
        }
        // Paused (the per-folder menu / menu bar Pause-Resume) and Automatic
        // organizing being off are two different states — don't collapse them
        // into one "Paused" label.
        if profile.isPaused {
            return "Paused"
        }
        return profile.automaticOrganizing ? "Watching" : "Organizing off"
    }
}

/// Add Folder… with a one-click suggestion for the screenshot location
/// (or Desktop). The folder picker still grants sandbox access.
private struct AddWatchFolderControl: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            if let suggestion = model.screenshotFolderSuggestion {
                Menu("Add Folder…") {
                    Button("Screenshots (\(suggestion.lastPathComponent))…") {
                        model.addWatchFolder(startingAt: suggestion)
                    }
                    Button("Choose Folder…") {
                        model.addWatchFolder()
                    }
                }
                .fixedSize()
            } else {
                Button("Add Folder…") {
                    model.addWatchFolder()
                }
                .disabled(!model.canAddWatchFolder)
            }
            Spacer()
        }
    }
}

/// Display name for one watch folder. Commits on Return or when the field
/// loses focus; an empty name keeps the previous one.
private struct WatchFolderNameField: View {
    @Environment(AppModel.self) private var model
    var profile: WatchFolderProfile
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text)
            .focused($focused)
            .onAppear { text = profile.displayName }
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
    }

    private func commit() {
        model.renameWatchFolder(id: profile.id, to: text)
        text = model.watchFolderName(id: profile.id) ?? text
    }
}
