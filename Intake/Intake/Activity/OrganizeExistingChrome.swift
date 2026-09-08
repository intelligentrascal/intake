import SwiftUI
import IntakeCore

struct OrganizeExistingChromeModifier: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .confirmationDialog(
                model.organizeConfirmTitle,
                isPresented: $model.organizeConfirmPresented,
                titleVisibility: .visible
            ) {
                Button(OrganizeExistingCopy.organizeButton) {
                    model.confirmOrganizeExisting()
                }
                Button(OrganizeExistingCopy.cancelButton, role: .cancel) {}
            } message: {
                Text(model.organizeConfirmMessage)
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
