import SwiftUI
import IntakeCore

struct CleanupSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Stepper(value: $model.cleanupThresholdDays, in: 1...365) {
                    Text("Unused for \(model.cleanupThresholdDays) days")
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
            Section("Queue") {
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
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            model.scanCleanupCandidates()
        }
    }
}

private struct CleanupQueueTable: View {
    @Environment(AppModel.self) private var model
    @State private var selection: URL?
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Table(model.cleanupCandidates, selection: $selection) {
                TableColumn("Name") { candidate in
                    Text(candidate.url.lastPathComponent)
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
            HStack {
                Button("File Away") {
                    if let candidate {
                        model.fileAway(candidate)
                        selection = nil
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(candidate == nil)
                Button("Keep") {
                    if let candidate {
                        model.keep(candidate)
                        selection = nil
                    }
                }
                .disabled(candidate == nil)
                Button("Delete", role: .destructive) {
                    confirmDelete = true
                }
                .disabled(candidate == nil)
                .foregroundStyle(IntakeColor.danger)
            }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let candidate {
                    model.delete(candidate)
                    selection = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Intake moves it to Trash.")
        }
    }

    private var candidate: CleanupCandidate? {
        model.cleanupCandidates.first { $0.url == selection }
    }

    private var deleteTitle: String {
        if let name = candidate?.url.lastPathComponent {
            return "Delete “\(name)”?"
        }
        return "Delete this file?"
    }

    private func byteCount(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
