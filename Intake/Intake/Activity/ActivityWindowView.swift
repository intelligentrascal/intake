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
            Group {
                if model.activity.isEmpty {
                    ContentUnavailableView(
                        "No activity yet",
                        systemImage: "list.bullet.clipboard",
                        description: Text("When Intake renames or files a download, it shows up here.")
                    )
                } else {
                    ActivityListView()
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .background {
            ZStack {
                IntakeMeshBackground(style: .activity, animated: !reduceMotion)
                Rectangle()
                    .fill(.background.opacity(0.32))
            }
        }
        .background(ActivityWindowConfigurator())
        .toolbar {
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
        .intakeOrganizeExistingChrome()
        .intakeFirstRunTip()
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

    var body: some View {
        List(selection: $selection) {
            ForEach(model.activity) { entry in
                ActivityRow(entry: entry)
                    .tag(entry.id)
                    .listRowBackground(Color.clear)
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            selection = entry.id
                            model.reveal(entry.url)
                        }
                    )
                    .contextMenu {
                        Button("Reveal in Finder") {
                            model.reveal(entry.url)
                        }
                        .disabled(entry.url == nil)
                        Button("Copy path") {
                            model.copyPath(entry.url)
                        }
                        .disabled(entry.url == nil)
                    }
                    .accessibilityAction(named: "Reveal in Finder") {
                        model.reveal(entry.url)
                    }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Reveal in Finder") {
                    model.reveal(selectedEntry?.url)
                }
                .disabled(selectedEntry?.url == nil)
            }
        }
    }

    private var selectedEntry: ActivityEntry? {
        guard let selection else { return nil }
        return model.activity.first { $0.id == selection }
    }
}

struct ActivityRow: View {
    var entry: ActivityEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
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
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.fileName), \(subtitle)")
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
        let when = entry.date.formatted(date: .abbreviated, time: .shortened)
        switch entry.kind {
        case .renamed:
            return "Renamed · \(when)"
        case .moved:
            if let folder = entry.destinationFolder {
                return "Moved to \(folder) · \(when)"
            }
            return "Moved · \(when)"
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
