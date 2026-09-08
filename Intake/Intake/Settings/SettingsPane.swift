import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case rules
    case cleanup
    case activity
    case ai
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .rules: "Rules"
        case .cleanup: "Cleanup"
        case .activity: "Activity"
        case .ai: "AI"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .rules: "list.bullet.rectangle"
        case .cleanup: "clock.arrow.circlepath"
        case .activity: "list.bullet.clipboard"
        case .ai: "sparkles"
        case .about: "info.circle"
        }
    }
}
