import SwiftUI
import IntakeCore

struct CleanupSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Threshold") {
                Stepper(value: $model.cleanupThresholdDays, in: 1...365) {
                    Text("Unused for \(model.cleanupThresholdDays) days")
                }
                Toggle(
                    "Include loose files still in the watch folder",
                    isOn: $model.includeWatchRootInCleanup
                )
            }
            Section("Queue") {
                if model.cleanupCandidates.isEmpty {
                    ContentUnavailableView(
                        "No cleanup candidates",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Files not opened or modified for \(model.cleanupThresholdDays) days will show up here for File Away, Delete, or Keep.")
                    )
                    .frame(minHeight: 180)
                } else {
                    CleanupQueueTable()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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
                Button("File Away") {}
                    .disabled(selection == nil)
                Button("Keep") {}
                    .disabled(selection == nil)
                Button("Delete", role: .destructive) {
                    confirmDelete = true
                }
                .disabled(selection == nil)
                .foregroundStyle(IntakeColor.danger)
            }
        }
        .confirmationDialog(
            "Delete this file?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone from Intake.")
        }
    }

    private func byteCount(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
