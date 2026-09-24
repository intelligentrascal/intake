import SwiftUI
import AppKit
import QuickLook
import IntakeCore

struct CleanupSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var thresholdDraft: Int = 1
    @FocusState private var thresholdFieldFocused: Bool

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                if model.hasMultipleWatchFolders {
                    Picker("Watch folder", selection: $model.cleanupFolderScope) {
                        Text("All Folders").tag(String?.none)
                        Divider()
                        ForEach(model.watchFolderProfiles) { profile in
                            Text(profile.displayName).tag(Optional(profile.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
                HStack {
                    Stepper(value: $model.cleanupThresholdDays, in: 1...365) {
                        Text("Unused for \(model.cleanupThresholdDays) days")
                    }
                    Spacer()
                    TextField(
                        "Days",
                        value: $thresholdDraft,
                        format: .number
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .accessibilityLabel("Unused-for threshold in days")
                    .focused($thresholdFieldFocused)
                    .onAppear { thresholdDraft = model.cleanupThresholdDays }
                    .onChange(of: model.cleanupThresholdDays) { _, newValue in
                        thresholdDraft = newValue
                    }
                    .onSubmit { commitThresholdDraft() }
                    .onChange(of: thresholdFieldFocused) { wasFocused, isFocused in
                        if wasFocused, !isFocused {
                            commitThresholdDraft()
                        }
                    }
                }
                Toggle(
                    "Include loose files still in the watch folder",
                    isOn: $model.includeWatchRootInCleanup
                )
            } header: {
                Text("Threshold")
            } footer: {
                Text("Cleanup lists files that have not been opened or modified for this long.")
            }
            Section {
                if model.cleanupCandidates.isEmpty {
                    ContentUnavailableView(
                        "No cleanup candidates",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Files not opened or modified for \(model.cleanupThresholdDays) days will show up here.")
                    )
                    .frame(minHeight: 180)
                } else {
                    CleanupQueueTable()
                }
            } header: {
                Text("Queue")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.scanCleanupCandidates()
        }
    }

    private func commitThresholdDraft() {
        let clamped = min(365, max(1, thresholdDraft))
        model.cleanupThresholdDays = clamped
        thresholdDraft = clamped
    }
}

private struct CleanupQueueTable: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<URL> = []
    @State private var confirmDelete = false
    @State private var pendingDeleteCandidates: [CleanupCandidate] = []
    @State private var quickLookURL: URL?
    @State private var quickLookURLs: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Table(model.cleanupCandidates, selection: $selection) {
                TableColumn("Name") { candidate in
                    Text(candidate.url.lastPathComponent)
                }
                TableColumn("Reason") { candidate in
                    reasonText(for: candidate)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                TableColumn("Age") { candidate in
                    Text(candidate.lastUsed, style: .relative)
                }
                TableColumn("Size") { candidate in
                    Text(byteCount(candidate.byteCount))
                }
                TableColumn("Path") { candidate in
                    Text(candidate.url.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(minHeight: 160)
            .contextMenu(forSelectionType: URL.self) { urls in
                contextMenuItems(for: urls)
            } primaryAction: { urls in
                quickLook(urls)
            }
            .onDeleteCommand {
                guard !selectedCandidates.isEmpty else { return }
                pendingDeleteCandidates = selectedCandidates
                confirmDelete = true
            }
            .quickLookPreview($quickLookURL, in: quickLookURLs)
            HStack {
                Button(fileAwayLabel) {
                    let candidates = selectedCandidates
                    guard !candidates.isEmpty else { return }
                    model.fileAway(candidates)
                    selection = []
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCandidates.isEmpty)
                .accessibilityLabel(fileAwayLabel)
                Button(keepLabel) {
                    let candidates = selectedCandidates
                    guard !candidates.isEmpty else { return }
                    model.keep(candidates)
                    selection = []
                }
                .disabled(selectedCandidates.isEmpty)
                .accessibilityLabel(keepLabel)
                Button(deleteLabel, role: .destructive) {
                    pendingDeleteCandidates = selectedCandidates
                    confirmDelete = true
                }
                .disabled(selectedCandidates.isEmpty)
                .foregroundStyle(IntakeColor.danger)
                .accessibilityLabel(deleteLabel)
            }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard !pendingDeleteCandidates.isEmpty else { return }
                model.delete(pendingDeleteCandidates)
                selection = []
                pendingDeleteCandidates = []
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteCandidates = []
            }
        } message: {
            Text(deleteMessage)
        }
    }

    @ViewBuilder
    private func contextMenuItems(for urls: Set<URL>) -> some View {
        Button("Quick Look") {
            quickLook(urls)
        }
        Button("Reveal in Finder") {
            reveal(urls)
        }
        Divider()
        Button("File Away") {
            let chosen = candidates(for: urls)
            guard !chosen.isEmpty else { return }
            model.fileAway(chosen)
            selection = []
        }
        Button("Keep") {
            let chosen = candidates(for: urls)
            guard !chosen.isEmpty else { return }
            model.keep(chosen)
            selection = []
        }
        Divider()
        Button("Delete…", role: .destructive) {
            pendingDeleteCandidates = candidates(for: urls)
            confirmDelete = true
        }
    }

    private var selectedCandidates: [CleanupCandidate] {
        candidates(for: selection)
    }

    /// Candidates matching `urls`, in table order.
    private func candidates(for urls: Set<URL>) -> [CleanupCandidate] {
        model.cleanupCandidates.filter { urls.contains($0.url) }
    }

    private var fileAwayLabel: String {
        selectedCandidates.count > 1 ? "File Away \(selectedCandidates.count) Items" : "File Away"
    }

    private var keepLabel: String {
        selectedCandidates.count > 1 ? "Keep \(selectedCandidates.count) Items" : "Keep"
    }

    private var deleteLabel: String {
        selectedCandidates.count > 1 ? "Delete \(selectedCandidates.count) Items…" : "Delete…"
    }

    private var deleteTitle: String {
        if pendingDeleteCandidates.count == 1, let name = pendingDeleteCandidates.first?.url.lastPathComponent {
            return "Delete “\(name)”?"
        }
        return "Delete \(pendingDeleteCandidates.count) Items?"
    }

    private var deleteMessage: String {
        pendingDeleteCandidates.count == 1
            ? "Intake moves it to Trash."
            : "Intake moves them to Trash."
    }

    private func quickLook(_ urls: Set<URL>) {
        let ordered = model.cleanupCandidates.map(\.url).filter { urls.contains($0) }
        guard !ordered.isEmpty else { return }
        quickLookURLs = ordered
        quickLookURL = ordered.first
    }

    private func reveal(_ urls: Set<URL>) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(Array(urls))
    }

    private func byteCount(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func reasonText(for candidate: CleanupCandidate) -> Text {
        switch candidate.reason {
        case .stale:
            return Text(candidate.reason.label)
        case .duplicate(let original):
            return Text("Duplicate of \(original.lastPathComponent)")
        case .abandonedDownload:
            return Text(candidate.reason.label)
        case .installed(let appName, _):
            return Text("Installer for \(appName)")
        }
    }
}
