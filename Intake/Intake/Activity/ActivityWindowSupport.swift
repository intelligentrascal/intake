import AppKit
import SwiftUI

enum IntakeSceneID {
    static let activity = "activity"
}

extension Notification.Name {
    static let intakeOpenActivity = Notification.Name("intake.openActivity")
}

extension NSWindow {
    var isIntakeActivityWindow: Bool {
        identifier?.rawValue == IntakeSceneID.activity
    }
}

/// Stamps the SwiftUI Activity window so Dock reopen can find it without duplicates.
struct ActivityWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.identifier = NSUserInterfaceItemIdentifier(IntakeSceneID.activity)
            window.minSize = NSSize(width: 520, height: 420)
            window.setFrameAutosaveName("intake.activity")
            window.isReleasedWhenClosed = true
            window.title = "Activity"
        }
    }
}

/// Used when no SwiftUI scene is alive to receive `openWindow` (Dock on, menu bar off, Activity closed).
@MainActor
final class ActivityWindowFallback {
    static let shared = ActivityWindowFallback()
    private var window: NSWindow?

    func present(model: AppModel) {
        if let existing = NSApp.windows.first(where: \.isIntakeActivityWindow) {
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            existing.makeKeyAndOrderFront(nil)
            return
        }
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let root = NSHostingController(rootView: ActivityWindowView().environment(model))
        let created = NSWindow(contentViewController: root)
        created.title = "Activity"
        created.identifier = NSUserInterfaceItemIdentifier(IntakeSceneID.activity)
        created.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        created.setContentSize(NSSize(width: 640, height: 520))
        created.minSize = NSSize(width: 520, height: 420)
        created.setFrameAutosaveName("intake.activity")
        created.isReleasedWhenClosed = false
        created.makeKeyAndOrderFront(nil)
        window = created
    }
}

/// Bridges AppKit reopen / Dock clicks to SwiftUI `openWindow(id:)`.
struct ActivityWindowOpenBridge: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppModel.self) private var model

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: model.activityWindowRequestID) { _, _ in
                openWindow(id: IntakeSceneID.activity)
            }
            .onReceive(NotificationCenter.default.publisher(for: .intakeOpenActivity)) { _ in
                openWindow(id: IntakeSceneID.activity)
            }
    }
}
