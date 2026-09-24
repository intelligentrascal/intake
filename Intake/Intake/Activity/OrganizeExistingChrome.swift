import SwiftUI
import IntakeCore

struct OrganizeExistingChromeModifier: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .sheet(isPresented: $model.organizePreviewPresented) {
                OrganizeExistingPreviewSheet()
                    .environment(model)
            }
            .sheet(isPresented: $model.organizeProgressPresented) {
                OrganizeExistingProgressSheet()
                    .environment(model)
            }
            .alert(
                model.organizeSummary?.doneMessage ?? "Done",
                isPresented: $model.organizeDonePresented
            ) {
                Button(OrganizeExistingCopy.showActivityButton) {
                    model.openActivity()
                }
            }
            .alert(
                "Nothing to organize",
                isPresented: $model.organizeNothingPresented
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("There are no loose files in the \(model.watchFolder.lastPathComponent) folder root.")
            }
    }
}

struct FirstRunTipModifier: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .alert(
                "Intake lives in the Dock and menu bar",
                isPresented: $model.showFirstRunTip
            ) {
                Button("OK") {
                    model.acknowledgeFirstRunTip()
                }
            } message: {
                Text("Look for the soft-catch icon in the Dock and near Control Center.")
            }
    }
}

/// Preview before Organize Existing: every eligible file mapped to its
/// destination, grouped by folder, with skip reasons — so Apply never
/// surprises. Replaces the old confirmation alert for any run with at least
/// one eligible file.
struct OrganizeExistingPreviewSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let preview = model.organizePreview {
                List {
                    ForEach(preview.groups) { group in
                        Section {
                            ForEach(group.items) { item in
                                OrganizePreviewRow(item: item)
                            }
                        } header: {
                            OrganizePreviewGroupHeader(group: group)
                        }
                    }
                    if !preview.skipped.isEmpty {
                        Section("Skipped (\(preview.skipped.count))") {
                            ForEach(preview.skipped, id: \.url) { skip in
                                HStack {
                                    Text(skip.url.lastPathComponent)
                                    Spacer()
                                    Text(skip.reason.reasonText)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.callout)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 480)
        .interactiveDismissDisabled()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.organizeConfirmTitle)
                .font(.headline)
            Text(OrganizeExistingCopy.confirmBody)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let note = model.organizePausedNote {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Text("\(model.organizeSelectedCount) selected")
                .foregroundStyle(.secondary)
            Spacer()
            Button(OrganizeExistingCopy.cancelButton) {
                model.cancelOrganizePreview()
            }
            .keyboardShortcut(.cancelAction)
            Button(OrganizeExistingCopy.organizeButton) {
                model.confirmOrganizePreview()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.organizeSelectedCount == 0)
        }
        .padding(20)
    }
}

private struct OrganizePreviewGroupHeader: View {
    @Environment(AppModel.self) private var model
    var group: OrganizePreviewGroup

    var body: some View {
        HStack {
            Button {
                model.toggleGroupExcluded(group)
            } label: {
                Image(systemName: model.isGroupFullyExcluded(group) ? "square" : "checkmark.square.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                model.isGroupFullyExcluded(group) ? "Include \(group.destinationFolderName)" : "Exclude \(group.destinationFolderName)"
            )
            Text(group.destinationFolderName)
                .font(.subheadline.weight(.semibold))
            if group.isNewFolder {
                Text("New folder")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tertiary, in: Capsule())
            }
            Spacer()
            Text("\(group.count)")
                .foregroundStyle(.secondary)
        }
    }
}

private struct OrganizePreviewRow: View {
    @Environment(AppModel.self) private var model
    var item: OrganizePreviewItem

    private var isExcluded: Bool {
        model.organizeExcludedURLs.contains(item.id)
    }

    var body: some View {
        HStack {
            Button {
                model.toggleExcluded(item)
            } label: {
                Image(systemName: isExcluded ? "square" : "checkmark.square.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExcluded ? "Include \(item.plan.renamedFileName)" : "Exclude \(item.plan.renamedFileName)")
            VStack(alignment: .leading, spacing: 2) {
                Text(item.plan.renamedFileName)
                if item.plan.needsRename {
                    Text(item.plan.sourceURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let domain = item.plan.sourceDomain {
                Text(domain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(isExcluded ? 0.5 : 1)
    }
}

struct OrganizeExistingProgressSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Organizing…")
                .font(.headline)
            if model.organizeEligibleTotal > 0 {
                ProgressView(
                    value: Double(model.organizeProcessedCount),
                    total: Double(model.organizeEligibleTotal)
                ) {
                    Text("Filing loose files")
                } currentValueLabel: {
                    Text("\(model.organizeProcessedCount) of \(model.organizeEligibleTotal)")
                }
                .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            HStack {
                Spacer()
                Button(OrganizeExistingCopy.cancelButton) {
                    model.cancelOrganizeExisting()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
        .interactiveDismissDisabled()
    }
}

extension View {
    func intakeOrganizeExistingChrome() -> some View {
        modifier(OrganizeExistingChromeModifier())
    }

    func intakeFirstRunTip() -> some View {
        modifier(FirstRunTipModifier())
    }
}
