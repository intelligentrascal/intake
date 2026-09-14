import Foundation

/// IN-12 atmospheres. Captain chose Paper Mesh as the live default (skipped A/B/C picker).
/// Switch for Mac smoke:
///   Debug menu → Atmosphere
///   defaults write app.intake.Intake intake.atmosphereStyle paperMesh
enum AtmosphereStyle: String, CaseIterable, Identifiable, Sendable {
    /// Captain pick — Paper Design MeshGradient look (native Metal).
    case paperMesh
    /// A — Quiet Mesh (preview retained).
    case quietMesh
    /// B — Soft Aurora Vignette (preview retained).
    case softAurora
    /// C — Material First (preview retained).
    case materialFirst

    public static func resolve(_ raw: String?) -> AtmosphereStyle {
        switch raw {
        case "paperMesh", "paper", "meshGradient": return .paperMesh
        case "quietMesh", "designerA", "mesh": return .quietMesh
        case "softAurora", "designerB", "aurora": return .softAurora
        case "materialFirst", "designerC", "material": return .materialFirst
        case "godRays": return .paperMesh // rejected — map to captain pick
        default: return .shippingDefault
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paperMesh: "Paper Mesh (default)"
        case .quietMesh: "A — Quiet Mesh"
        case .softAurora: "B — Soft Aurora"
        case .materialFirst: "C — Material First"
        }
    }

    static let defaultsKey = "intake.atmosphereStyle"
    static var previewChoices: [AtmosphereStyle] {
        [.paperMesh, .quietMesh, .softAurora, .materialFirst]
    }
    static let shippingDefault: AtmosphereStyle = .paperMesh
}

enum AtmosphereSurface: Sendable {
    case settingsWindow
    case settingsDetail
    case activity
}
