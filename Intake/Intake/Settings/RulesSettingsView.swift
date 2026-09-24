import SwiftUI
import IntakeCore

struct RulesSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var editor: RuleEditorItem?
    @State private var selectedRuleID: RoutingRule.ID?
    @State private var pendingDeleteRule: RoutingRule?
    @State private var pendingResetRule: RoutingRule?

    var body: some View {
        Form {
            suggestionsSection
            if !model.ruleConflicts.isEmpty {
                Section {
                    ForEach(model.ruleConflicts) { conflict in
                        Label(conflict.summary, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(IntakeColor.warning)
                    }
                } header: {
                    Text("Conflicts")
                } footer: {
                    Text("When two enabled rules list the same extension, the first in this list wins.")
                }
            }
            if !model.unreachableRules.isEmpty {
                Section {
                    ForEach(model.unreachableRules) { unreachable in
                        Label(unreachable.summary, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(IntakeColor.warning)
                    }
                } header: {
                    Text("Unreachable rules")
                } footer: {
                    Text("An earlier enabled rule already matches everything these would. Reorder them so the more specific rule comes first.")
                }
            }
            Section {
                List(selection: $selectedRuleID) {
                    ForEach(model.rules) { rule in
                        RuleRowView(rule: rule)
                            .tag(rule.id)
                            .contextMenu {
                                Button("Edit…") {
                                    editor = .edit(rule)
                                }
                                Button("Move Up") {
                                    moveRule(rule, up: true)
                                }
                                .disabled(!canMove(rule, up: true))
                                Button("Move Down") {
                                    moveRule(rule, up: false)
                                }
                                .disabled(!canMove(rule, up: false))
                                if rule.isBuiltIn {
                                    Button("Reset to Default") {
                                        pendingResetRule = rule
                                    }
                                } else {
                                    Button("Delete", role: .destructive) {
                                        pendingDeleteRule = rule
                                    }
                                }
                            }
                    }
                    .onMove { source, destination in
                        model.moveRules(from: source, to: destination)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 280)
                // Hidden shortcut buttons: SwiftUI only registers keyboardShortcut as a
                // system-wide key equivalent when the button is present in the view tree,
                // not only while its context menu is open.
                .background {
                    Group {
                        Button("Delete Rule") {
                            if let rule = selectedRule, !rule.isBuiltIn {
                                pendingDeleteRule = rule
                            }
                        }
                        .keyboardShortcut(.delete, modifiers: .command)
                        .focusable(false)
                        Button("Move Rule Up") {
                            if let rule = selectedRule {
                                moveRule(rule, up: true)
                            }
                        }
                        .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                        .focusable(false)
                        Button("Move Rule Down") {
                            if let rule = selectedRule {
                                moveRule(rule, up: false)
                            }
                        }
                        .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                        .focusable(false)
                    }
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                HStack {
                    Button("Add Rule…") {
                        editor = .add
                    }
                    Button("Edit…") {
                        if let rule = selectedRule {
                            editor = .edit(rule)
                        }
                    }
                    .disabled(selectedRule == nil)
                    if let rule = selectedRule, rule.isBuiltIn {
                        Button("Reset to Default") {
                            pendingResetRule = rule
                        }
                    }
                    if let rule = selectedRule, !rule.isBuiltIn {
                        Button("Delete", role: .destructive) {
                            pendingDeleteRule = rule
                        }
                    }
                    Spacer()
                }
            } header: {
                Text("Filing rules")
            } footer: {
                Text("Each rule can match a file's type, name, source, or size; scoped rules only apply within their chosen watch folders. Drag to change order — the first enabled match wins. Unmatched files go to Other.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshSuggestions()
        }
        .sheet(item: $editor) { item in
            RuleEditorSheet(item: item)
                .environment(model)
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: Binding(
                get: { pendingDeleteRule != nil },
                set: { if !$0 { pendingDeleteRule = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let rule = pendingDeleteRule {
                    model.deleteCustomRule(id: rule.id)
                    if selectedRuleID == rule.id {
                        selectedRuleID = nil
                    }
                }
                pendingDeleteRule = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteRule = nil
            }
        } message: {
            Text("This can't be undone.")
        }
        .confirmationDialog(
            resetConfirmationTitle,
            isPresented: Binding(
                get: { pendingResetRule != nil },
                set: { if !$0 { pendingResetRule = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Reset to Default", role: .destructive) {
                if let rule = pendingResetRule {
                    model.resetBuiltInRule(id: rule.id)
                }
                pendingResetRule = nil
            }
            Button("Cancel", role: .cancel) {
                pendingResetRule = nil
            }
        } message: {
            Text("Any changes you made to this rule will be discarded.")
        }
    }

    private var deleteConfirmationTitle: String {
        guard let rule = pendingDeleteRule else { return "Delete rule?" }
        return "Delete “\(rule.folderName)”?"
    }

    private var resetConfirmationTitle: String {
        guard let rule = pendingResetRule else { return "Reset rule to default?" }
        return "Reset “\(rule.folderName)” to default?"
    }

    private func canMove(_ rule: RoutingRule, up: Bool) -> Bool {
        guard let index = model.rules.firstIndex(where: { $0.id == rule.id }) else { return false }
        return up ? index > 0 : index < model.rules.count - 1
    }

    private func moveRule(_ rule: RoutingRule, up: Bool) {
        guard let index = model.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        if up {
            guard index > 0 else { return }
            model.moveRules(from: IndexSet(integer: index), to: index - 1)
        } else {
            guard index < model.rules.count - 1 else { return }
            model.moveRules(from: IndexSet(integer: index), to: index + 2)
        }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        Section {
            if model.ruleSuggestions.isEmpty {
                ContentUnavailableView(
                    "No suggestions yet",
                    systemImage: "lightbulb",
                    description: Text("Suggestions appear after Intake sees repeating file types.")
                )
                .frame(minHeight: 120)
            } else {
                ForEach(model.ruleSuggestions) { suggestion in
                    SuggestionRowView(suggestion: suggestion)
                }
            }
        } header: {
            Text("Suggestions")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggestions never change files until you accept. They stay on this Mac — Intake does not read file contents or go online to propose rules.")
                if !model.suggestionMemory.neverExtensions.isEmpty
                    || !model.suggestionMemory.dismissedUntil.isEmpty {
                    Button("Reset dismissed suggestions") {
                        model.resetDismissedSuggestions()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var selectedRule: RoutingRule? {
        guard let selectedRuleID else { return nil }
        return model.rules.first { $0.id == selectedRuleID }
    }
}

private struct RuleRowView: View {
    @Environment(AppModel.self) private var model
    var rule: RoutingRule

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Toggle("Enabled", isOn: model.binding(for: rule))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 28)
                .accessibilityLabel("Enabled")
            Label(rule.folderName, systemImage: rule.systemImage)
                .frame(minWidth: 140, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.extensions.isEmpty ? "Any type" : rule.extensionsDisplay)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if !rule.conditions.isEmpty {
                    Text(conditionsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let scopeSummary {
                    Text(scopeSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rule.folderName)
        .accessibilityValue(accessibilitySummary)
    }

    /// Read after the row's name: destination, match criteria, enabled state, and scope,
    /// while leaving the Enabled checkbox itself reachable and independently operable.
    private var accessibilitySummary: String {
        var parts = [rule.extensions.isEmpty ? "Any type" : rule.extensionsDisplay]
        if !rule.conditions.isEmpty {
            parts.append(conditionsSummary)
        }
        if let scopeSummary {
            parts.append(scopeSummary)
        }
        parts.append(rule.isEnabled ? "Enabled" : "Disabled")
        return parts.joined(separator: ", ")
    }

    private var conditionsSummary: String {
        rule.conditions.map(\.summary).joined(separator: ", ")
    }

    /// "Only Desktop, Screenshots" for a rule scoped to specific watch folders.
    private var scopeSummary: String? {
        guard case .watchFolders(let ids) = rule.scope else { return nil }
        let names = model.watchFolderProfiles.filter { ids.contains($0.id) }.map(\.displayName)
        return names.isEmpty ? "No watch folders" : "Only \(names.joined(separator: ", "))"
    }
}

private struct SuggestionRowView: View {
    @Environment(AppModel.self) private var model
    var suggestion: RuleSuggestion

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: suggestion.systemImage)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                Text(suggestion.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Accept") {
                model.acceptSuggestion(suggestion)
            }
            .buttonStyle(.borderedProminent)
            Button("Dismiss") {
                model.dismissSuggestion(suggestion)
            }
            Button("Never") {
                model.neverSuggestion(suggestion)
            }
            .buttonStyle(.borderless)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }
}

enum RuleEditorItem: Identifiable {
    case add
    case edit(RoutingRule)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let rule): rule.id
        }
    }
}

struct RuleEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var item: RuleEditorItem

    @State private var folderName: String
    @State private var extensionsText: String
    @State private var conditions: [RuleCondition]
    @State private var isEnabled: Bool
    @State private var subfolderPattern: SubfolderPattern
    @State private var scope: RuleScope
    @State private var errorMessage: String?

    init(item: RuleEditorItem) {
        self.item = item
        switch item {
        case .add:
            _folderName = State(initialValue: "")
            _extensionsText = State(initialValue: "")
            _conditions = State(initialValue: [])
            _isEnabled = State(initialValue: true)
            _subfolderPattern = State(initialValue: .none)
            _scope = State(initialValue: .allWatchFolders)
        case .edit(let rule):
            _folderName = State(initialValue: rule.folderName)
            _extensionsText = State(initialValue: rule.extensionsDisplay)
            _conditions = State(initialValue: rule.conditions)
            _isEnabled = State(initialValue: rule.isEnabled)
            _subfolderPattern = State(initialValue: rule.subfolderPattern)
            _scope = State(initialValue: rule.scope)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Folder", text: $folderName)
                TextField(
                    "Extensions",
                    text: $extensionsText,
                    prompt: Text(conditions.isEmpty ? "psd, ai" : "psd, ai (or leave empty for any type)")
                )
                Toggle("Enabled", isOn: $isEnabled)
                Picker("Subfolders", selection: $subfolderPattern) {
                    ForEach(SubfolderPattern.allCases, id: \.self) { pattern in
                        Text(pattern.title).tag(pattern)
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(IntakeColor.danger)
                }
                conditionsSection
                if model.hasMultipleWatchFolders || !scope.isAll {
                    scopeSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    @ViewBuilder
    private var conditionsSection: some View {
        Section {
            ForEach(Array(conditions.enumerated()), id: \.offset) { index, _ in
                ConditionEditorRow(
                    condition: Binding(
                        get: { conditions[index] },
                        set: { conditions[index] = $0 }
                    ),
                    sourceDomainHint: sourceDomainHint
                )
            }
            .onDelete { offsets in
                conditions.remove(atOffsets: offsets)
            }
            Menu {
                ForEach(RuleCondition.Kind.allCases, id: \.self) { kind in
                    Button(kind.label) {
                        conditions.append(ConditionEditorRow.defaultCondition(for: kind))
                    }
                }
            } label: {
                Label("Add Condition", systemImage: "plus")
            }
        } header: {
            Text("Conditions")
        } footer: {
            Text(conditionsFooter)
        }
    }

    /// Applies to: all watch folders (default) or specific ones.
    @ViewBuilder
    private var scopeSection: some View {
        Section {
            Picker("Watch folders", selection: Binding(
                get: { scope.isAll },
                set: { isAll in
                    if isAll {
                        scope = .allWatchFolders
                    } else if scope.isAll {
                        scope = .watchFolders(Set(model.watchFolderProfiles.prefix(1).map(\.id)))
                    }
                }
            )) {
                Text("All watch folders").tag(true)
                Text("Specific folders").tag(false)
            }
            if case .watchFolders(let ids) = scope {
                ForEach(model.watchFolderProfiles) { profile in
                    Toggle(profile.displayName, isOn: Binding(
                        get: { ids.contains(profile.id) },
                        set: { included in
                            var next = ids
                            if included {
                                next.insert(profile.id)
                            } else {
                                next.remove(profile.id)
                            }
                            scope = .watchFolders(next)
                        }
                    ))
                }
            }
        } header: {
            Text("Applies to")
        } footer: {
            Text("A rule scoped to specific folders is skipped everywhere else, so screenshot rules never touch Downloads.")
        }
    }

    private var sourceDomainHint: String {
        model.recentSourceDomains.first ?? "bank.com"
    }

    private var conditionsFooter: String {
        var lines = ["All conditions must match (AND). With at least one condition, extensions can be left empty to match any type."]
        if !model.recentSourceDomains.isEmpty {
            lines.append("Recently seen: \(model.recentSourceDomains.joined(separator: ", ")).")
        }
        return lines.joined(separator: " ")
    }

    private var title: String {
        switch item {
        case .add: "Add Rule"
        case .edit: "Edit Rule"
        }
    }

    private func save() {
        switch FolderNameToken.parse(folderName) {
        case .failure(let error):
            errorMessage = error.description
            return
        case .success(let name):
            let trimmedExtensions = extensionsText.trimmingCharacters(in: .whitespacesAndNewlines)
            let extensionsResult: Result<Set<String>, ExtensionToken.ParseError> = trimmedExtensions.isEmpty
                ? .success([])
                : ExtensionToken.parse(extensionsText)
            switch extensionsResult {
            case .failure(let error):
                errorMessage = error.description
            case .success(let tokens):
                guard !tokens.isEmpty || !conditions.isEmpty else {
                    errorMessage = "Add at least one extension or condition."
                    return
                }
                if case .watchFolders(let ids) = scope, ids.isEmpty {
                    errorMessage = "Choose at least one watch folder."
                    return
                }
                let id: String? = {
                    if case .edit(let rule) = item { return rule.id }
                    return nil
                }()
                model.saveRule(
                    id: id,
                    folderName: name,
                    extensions: tokens,
                    conditions: conditions,
                    isEnabled: isEnabled,
                    subfolderPattern: subfolderPattern,
                    scope: scope
                )
                dismiss()
            }
        }
    }
}

private struct ConditionEditorRow: View {
    @Binding var condition: RuleCondition
    var sourceDomainHint: String

    var body: some View {
        HStack(spacing: 8) {
            Picker("Condition", selection: kindBinding) {
                ForEach(RuleCondition.Kind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Condition")
            .frame(width: 160)
            valueField
        }
    }

    @ViewBuilder
    private var valueField: some View {
        switch condition {
        case .sourceDomain(let value):
            TextField(sourceDomainHint, text: Binding(
                get: { value },
                set: { condition = .sourceDomain($0) }
            ))
        case .nameContains(let value):
            TextField("invoice", text: Binding(
                get: { value },
                set: { condition = .nameContains($0) }
            ))
        case .nameStartsWith(let value):
            TextField("IMG_", text: Binding(
                get: { value },
                set: { condition = .nameStartsWith($0) }
            ))
        case .nameMatchesWildcard(let value):
            TextField("IMG_*", text: Binding(
                get: { value },
                set: { condition = .nameMatchesWildcard($0) }
            ))
        case .sizeAtLeast(let bytes):
            SizeField(bytes: Binding(
                get: { bytes },
                set: { condition = .sizeAtLeast($0) }
            ))
        case .sizeAtMost(let bytes):
            SizeField(bytes: Binding(
                get: { bytes },
                set: { condition = .sizeAtMost($0) }
            ))
        }
    }

    private var kindBinding: Binding<RuleCondition.Kind> {
        Binding(
            get: { condition.kind },
            set: { condition = Self.defaultCondition(for: $0) }
        )
    }

    static func defaultCondition(for kind: RuleCondition.Kind) -> RuleCondition {
        switch kind {
        case .sourceDomain: .sourceDomain("")
        case .nameContains: .nameContains("")
        case .nameStartsWith: .nameStartsWith("")
        case .nameMatchesWildcard: .nameMatchesWildcard("")
        case .sizeAtLeast: .sizeAtLeast(0)
        case .sizeAtMost: .sizeAtMost(0)
        }
    }
}

/// A byte-size field edited in megabytes for readability; stores exact bytes.
private struct SizeField: View {
    @Binding var bytes: Int64
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 4) {
            TextField("0", text: $text)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                .onAppear { text = Self.formatted(bytes) }
                .onChange(of: text) { _, newValue in
                    guard let megabytes = Double(newValue) else { return }
                    bytes = Int64((megabytes * 1_000_000).rounded())
                }
            Text("MB")
                .foregroundStyle(.secondary)
        }
    }

    private static func formatted(_ bytes: Int64) -> String {
        guard bytes != 0 else { return "" }
        return String(format: "%g", Double(bytes) / 1_000_000)
    }
}
