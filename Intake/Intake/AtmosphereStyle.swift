import Foundation

/// IN-12 Designer atmospheres (IN-12-atmospheres.md). Captain picks one after screenshots.
/// Switch for Mac smoke:
///   defaults write app.intake.Intake intake.atmosphereStyle quietMesh
///   defaults write app.intake.Intake intake.atmosphereStyle softAurora
///   defaults write app.intake.Intake intake.atmosphereStyle materialFirst
/// Or Debug menu → Atmosphere (live via `@AppStorage`).
enum AtmosphereStyle: String, CaseIterable, Identifiable, Sendable {
    /// A — Quiet Mesh (refined utility).
    case quietMesh
    /// B — Soft Aurora Vignette (no rays).
    case softAurora
    /// C — Material First (HIG only).
    case materialFirst

    /// Legacy aliases from hold stub — accepted by defaults / AppStorage.
    public static func resolve(_ raw: String?) -> AtmosphereStyle {
        switch raw {
        case "quietMesh", "designerA", "mesh": return .quietMesh
        case "softAurora", "designerB", "aurora": return .softAurora
        case "materialFirst", "designerC", "material": return .materialFirst
        case "godRays": return .quietMesh // rejected look — fall back to A
        default: return .shippingDefault
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quietMesh: "A — Quiet Mesh"
        case .softAurora: "B — Soft Aurora"
        case .materialFirst: "C — Material First"
        }
    }

    var shortTitle: String {
        switch self {
        case .quietMesh: "Quiet Mesh"
        case .softAurora: "Soft Aurora"
        case .materialFirst: "Material First"
        }
    }

    static let defaultsKey = "intake.atmosphereStyle"
    static var previewChoices: [AtmosphereStyle] { [.quietMesh, .softAurora, .materialFirst] }
    /// Default while captain undecided — calm utility (A), not rejected God Rays.
    static let shippingDefault: AtmosphereStyle = .quietMesh
}

enum AtmosphereSurface: Sendable {
    /// Full Settings window wash (behind sidebar + chrome). Detail content stays clear of mesh for A.
    case settingsWindow
    /// Settings detail column — usually system Form; A uses none.
    case settingsDetail
    /// Activity window full-bleed behind list / empty state.
    case activity
}
