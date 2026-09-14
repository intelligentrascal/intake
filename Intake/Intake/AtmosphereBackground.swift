import SwiftUI

/// Routes the locked Paper Mesh atmosphere per surface.
struct AtmosphereBackground: View {
    var style: AtmosphereStyle = .paperMesh
    var surface: AtmosphereSurface
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if reduceTransparency || contrast == .increased {
                IntakeColor.surface
            } else {
                PaperMeshAtmosphere(surface: surface, animated: animated && !reduceMotion)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PaperMeshAtmosphere: View {
    var surface: AtmosphereSurface
    var animated: Bool

    var body: some View {
        let mapped: PaperMeshBackground.Surface = {
            switch surface {
            case .settingsWindow: return .settingsWindow
            case .settingsDetail: return .settingsDetail
            case .activity: return .activity
            }
        }()
        PaperMeshBackground(surface: mapped, animated: animated)
    }
}
