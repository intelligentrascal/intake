import SwiftUI
import IntakeCore

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    /// Watch folders whose settings are expanded (only used with several folders).
    @State private var expandedFolderIDs: Set<String> = []
    @State private var pendingRemoval: WatchFolderProfile?

    var body: some View {
        Form {
            watchFoldersSection
            existingFilesSection
            notificationsSection
            startupAndAppearanceSection
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
                    expandedFolderIDs.remove(id)
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

    /// Each folder's organizing settings live with its row: inline with one
    /// folder, in a disclosure per folder with several — so the settings being
    /// edited always belong to the folder they sit under.
    private var watchFoldersSection: some View {
        Section {
            ForEach(model.watchFolderControllers, id: \.profileID) { controller in
                if model.hasMultipleWatchFolders {
                    DisclosureGroup(isExpanded: expansionBinding(for: controller.profileID)) {
                        WatchFolderNameField(profile: controller.profile)
                            .id(controller.profileID)
                        WatchFolderOrganizingControls(profile: controller.profile)
                    } label: {
                        WatchFolderRow(controller: controller, pathIsSelectable: false) {
                            pendingRemoval = controller.profile
                        }
                    }
                } else {
                    WatchFolderRow(controller: controller) {
                        pendingRemoval = controller.profile
                    }
                    WatchFolderOrganizingControls(profile: controller.profile)
                }
            }
            AddWatchFolderControl()
        } header: {
            Text(model.hasMultipleWatchFolders ? "Watch folders" : "Watch folder")
        } footer: {
            Text(watchFoldersFooter)
        }
    }

    private var watchFoldersFooter: String {
        let base = "Intake renames each finished download in place, then files it into a typed folder created only when needed. Up to \(WatchFolderProfile.softCap) folders, and they can’t overlap."
        return model.hasMultipleWatchFolders
            ? base + " Expand a folder to change its own settings."
            : base
    }

    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedFolderIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedFolderIDs.insert(id)
                } else {
                    expandedFolderIDs.remove(id)
                }
            }
        )
    }

    /// Organize Existing… is a one-shot catch-up for loose files already in a
    /// watch folder root (from before Intake watched it, or while it was off).
    private var existingFilesSection: some View {
        Section {
            LabeledContent {
                OrganizeExistingMenu()
                    .buttonStyle(.borderedProminent)
            } label: {
                Text("Files already in the folder")
                Text("Preview renames and moves for loose items in the root, then apply.")
            }
            Button("Open Activity") {
                model.openActivity()
            }
        } header: {
            Text("Existing files")
        } footer: {
            Text("Category folders are left alone. Works while Automatic organizing is off, without turning it back on.")
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
            Text("Intake asks for permission when you turn this on, then sends digests — never one notification per file. Errors arrive on their own, at most once a minute.")
        }
    }

    private var startupAndAppearanceSection: some View {
        Section {
            Toggle("Open at login", isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: { model.setLaunchAtLogin($0) }
            ))
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
            Text("Startup and appearance")
        } footer: {
            Text("Open at login starts Intake in the background. The menu bar shows status without opening a window; one of Dock or menu bar stays on so you can reopen Settings.")
        }
    }
}

/// One watch folder's own organizing settings. Pause / Resume stays in the
/// row's menu; Automatic organizing and Rename keep their separate meanings.
private struct WatchFolderOrganizingControls: View {
    @Environment(AppModel.self) private var model
    var profile: WatchFolderProfile

    var body: some View {
        Toggle(isOn: Binding(
            get: { profile.isOrganizing },
            set: { model.setAutomaticOrganizing($0, for: profile.id) }
        )) {
            Text("Automatic organizing")
            Text("Files new downloads into folders. Off: files stay where they land.")
        }
        Toggle(isOn: Binding(
            get: { profile.renameWhenDownloadFinishes },
            set: { model.setRenameWhenDownloadFinishes($0, for: profile.id) }
        )) {
            Text(RenameOnStableCopy.toggleTitle)
            Text("Renames on this Mac as soon as the download is stable, on its own — whether or not Automatic organizing is on.")
        }
        Picker(selection: Binding(
            get: { profile.organizingWait },
            set: { model.setOrganizingWait($0, for: profile.id) }
        )) {
            ForEach(OrganizingWait.allCases) { wait in
                Text(wait.title).tag(wait)
            }
        } label: {
            Text("Wait before organizing")
            Text("New downloads stay put this long so you can open them before they’re filed.")
        }
        .pickerStyle(.menu)
        .disabled(!profile.isOrganizing)
    }
}

/// One watch folder: name, path, status, and a menu of per-folder actions.
/// Lost access shows inline with a Grant Access action.
private struct WatchFolderRow: View {
    @Environment(AppModel.self) private var model
    var controller: WatchFolderController
    /// False when this row is the label of a DisclosureGroup (several
    /// folders): selectable text there would eat the click that's supposed
    /// to expand/collapse the row instead.
    var pathIsSelectable: Bool = true
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
                    Group {
                        if pathIsSelectable {
                            Text(controller.folder.path)
                                .textSelection(.enabled)
                        } else {
                            Text(controller.folder.path)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(statusText(for: profile))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help(statusHelp(for: profile))
                Menu {
                    Button("Show in Finder") {
                        model.revealWatchFolder(id: controller.profileID)
                    }
                    Button("Change Folder…") {
                        model.changeWatchFolder(id: controller.profileID)
                    }
                    Button(profile.isPaused ? "Resume Organizing" : "Pause Organizing") {
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

    private func statusHelp(for profile: WatchFolderProfile) -> String {
        if controller.accessLost {
            return "Intake lost access to this folder. Grant access again to resume."
        }
        if profile.isPaused {
            return "Paused from this folder’s menu — temporary, until you resume. Filing stops; renaming can still run."
        }
        if profile.automaticOrganizing {
            return "New downloads are filed into folders after Wait before organizing."
        }
        return "Automatic organizing is off for this folder. Files stay in place; renaming can still run."
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
