import Foundation

/// IN-12 locked: captain approved Paper Mesh as the only shipping atmosphere.
enum AtmosphereStyle: String, CaseIterable, Identifiable, Sendable {
    case paperMesh

    public static func resolve(_ raw: String?) -> AtmosphereStyle {
        // Any legacy preview key collapses to Paper Mesh.
        .paperMesh
    }

    var id: String { rawValue }
    var title: String { "Paper Mesh" }

    static let defaultsKey = "intake.atmosphereStyle"
    static let shippingDefault: AtmosphereStyle = .paperMesh
}

enum AtmosphereSurface: Sendable {
    case settingsWindow
    case settingsDetail
    case activity
}
