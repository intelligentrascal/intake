import Foundation

/// IN-12 atmosphere preview picker — Designer will define three drastically different
/// native directions; captain picks one before live. God Rays stays available as a
/// hidden/dev option but is **not** the default after captain reject.
enum AtmosphereStyle: String, CaseIterable, Identifiable, Sendable {
    /// Prior MeshGradient wash (current default / Apps install).
    case mesh
    /// Paper-inspired God Rays (kept for A/B; not default).
    case godRays
    /// Placeholder slots for Designer’s three directions (filled when handoff lands).
    case designerA
    case designerB
    case designerC

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mesh: "Mesh"
        case .godRays: "God Rays"
        case .designerA: "Direction A"
        case .designerB: "Direction B"
        case .designerC: "Direction C"
        }
    }

    /// Styles offered in a future Settings preview control once Designer ships A/B/C.
    static var previewChoices: [AtmosphereStyle] { [.mesh, .godRays, .designerA, .designerB, .designerC] }

    /// Default for shipping / Apps install while IN-12 is on hold.
    static let shippingDefault: AtmosphereStyle = .mesh
}
