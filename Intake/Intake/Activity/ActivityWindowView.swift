import AppKit
import SwiftUI
import IntakeCore

struct ActivityWindowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if !model.pendingAISuggestions.isEmpty {
                AISuggestionList()
            }
            ZStack(alignment: .bottom) {
                Group {
                    if model.activity.isEmpty {
                        ContentUnavailableView(
                            "No activity yet",
                            systemImage: "list.bullet.clipboard",
                            description: Text("When Intake renames or files a download, it shows up here.")
                        )
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(28)
                    } else {
                        ActivityListView()
                            .scrollContentBackground(.hidden)
                            .background(.ultraThinMaterial.opacity(0.55))
                    }
                }
                if let toast = model.undoToast {
                    UndoToastBar(toast: toast)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .background {
            AtmosphereActivityChrome(reduceMotion: reduceMotion)
        }
        .background(ActivityWindowConfigurator())
        .toolbar {
            if model.hasMultipleWatchFolders {
                ToolbarItem(placement: .automatic) {
                    ActivityFolderFilterPicker()
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(model.isPaused ? "Resume" : "Pause") {
                    model.togglePaused()
                }
            }
            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .animation(reduceMotion ? nil : .default, value: model.activity.count)
        .animation(reduceMotion ? nil : .default, value: model.undoToast?.actionID)
        .intakeOrganizeExistingChrome()
        .intakeFirstRunTip()
    }
}

/// Activity folder filter: All Folders, or one watch folder. Rows written
/// before multiple watch folders count as the first folder.
struct ActivityFolderFilterPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Picker("Folder", selection: Binding(
            get: { model.activityFolderFilter },
            set: { model.activityFolderFilter = $0 }
        )) {
            Text("All Folders").tag(String?.none)
            Divider()
            ForEach(model.watchFolderProfiles) { profile in
                Text(profile.displayName).tag(Optional(profile.id))
            }
        }
        .pickerStyle(.menu)
        .help("Show activity from one watch folder")
    }
}

private struct UndoToastBar: View {
    @Environment(AppModel.self) private var model
    var toast: UndoToastPresentation

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(.body)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if toast.showsUndoButton {
                Button(UndoCopy.undo) {
                    model.undoLastFromToast()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct AISuggestionList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.pendingAISuggestions) { suggestion in
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "sparkles")
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Move \(suggestion.fileName) to \(suggestion.proposedFolder)?")
                        Text(suggestion.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Accept") {
                        model.acceptAISuggestion(suggestion)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Dismiss") {
                        model.dismissAISuggestion(suggestion)
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
    }
}

struct ActivityListView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: ActivityEntry.ID?
    /// Only the standalone Activity window gets the toolbar Reveal button.
    /// Embedded in Settings, a toolbar item would add an NSToolbar to the
    /// Settings window while this pane is shown, growing the titlebar and
    /// shifting every pane's content on switch. Settings keeps Reveal via
    /// double-click and the context menu.
    var showsRevealToolbarItem = true

    var body: some View {
        if showsRevealToolbarItem {
            list.toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reveal in Finder") {
                        model.reveal(selectedEntry)
                    }
                    .disabled(!(selectedEntry?.hasRevealablePath ?? false))
                }
            }
        } else {
            list
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(model.filteredActivity) { entry in
                ActivityRow(entry: entry)
                    .tag(entry.id)
                    .listRowBackground(Color.clear)
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            selection = entry.id
                            model.reveal(entry)
                        }
                    )
                    .contextMenu {
                        Button("Reveal in Finder") {
                            model.reveal(entry)
                        }
                        .disabled(!entry.hasRevealablePath)
                        Button("Copy path") {
                            model.copyPath(entry.url)
                        }
                        .disabled(!entry.hasRevealablePath)
                        undoContextItems(for: entry)
                    }
                    .accessibilityAction(named: "Reveal in Finder") {
                        model.reveal(entry)
                    }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func undoContextItems(for entry: ActivityEntry) -> some View {
        let eligibility = model.undoEligibility(for: entry)
        if entry.kind == .renamed || entry.kind == .moved {
            Divider()
            Button(UndoCopy.undo) {
                model.undo(activityID: entry.id)
            }
            .disabled(eligibility != .eligible)
            .help(eligibility.reason ?? UndoCopy.undo)
        }
    }

    private var selectedEntry: ActivityEntry? {
        guard let selection else { return nil }
        return model.filteredActivity.first { $0.id == selection }
    }
}

struct ActivityRow: View {
    @Environment(AppModel.self) private var model
    var entry: ActivityEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: entry.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(symbolStyle)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fileName)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let folder = entry.destinationFolder {
                Text(folder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            undoControl
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.fileName), \(subtitle)")
    }

    @ViewBuilder
    private var undoControl: some View {
        if entry.kind == .renamed || entry.kind == .moved {
            let eligibility = model.undoEligibility(for: entry)
            Button(UndoCopy.undo) {
                model.undo(activityID: entry.id)
            }
            .buttonStyle(.borderless)
            .controlSize(.regular)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(eligibility != .eligible)
            .help(eligibility.reason ?? UndoCopy.undo)
            .accessibilityLabel(UndoCopy.undo)
            .accessibilityHint(eligibility.reason ?? "")
        }
    }

    private var symbolStyle: some ShapeStyle {
        switch entry.kind {
        case .error:
            IntakeColor.warning
        case .deleted:
            IntakeColor.danger
        case .moved, .folderRemoved:
            IntakeColor.success
        case .renamed, .skipped:
            IntakeColor.inkSecondary
        }
    }

    private var subtitle: String {
        let date = entry.date.formatted(date: .abbreviated, time: .shortened)
        // With several watch folders, name the one this change came from.
        let folder = model.hasMultipleWatchFolders
            ? model.watchFolderName(id: entry.effectiveWatchFolderID)
            : nil
        let when = folder.map { "\($0) · \(date)" } ?? date
        switch entry.kind {
        case .renamed:
            return "Renamed · \(when)"
        case .moved:
            let from = entry.sourceDomain.map { " · from \($0)" } ?? ""
            if let folder = entry.destinationFolder {
                return "Moved to \(folder)\(from) · \(when)"
            }
            return "Moved\(from) · \(when)"
        case .skipped:
            return "Skipped · \(when)"
        case .error:
            return "\(entry.detail) · \(when)"
        case .deleted:
            return "Deleted · \(when)"
        case .folderRemoved:
            return "Removed empty folder · \(when)"
        }
    }
}

/// Activity Paper Mesh wash + light scrim for list readability.
private struct AtmosphereActivityChrome: View {
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            AtmosphereBackground(surface: .activity, animated: !reduceMotion)
            Rectangle()
                .fill(.background.opacity(0.28))
        }
    }
}
