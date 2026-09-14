import SwiftUI

/// Paper Design MeshGradient look — native Metal stitchable (no npm).
/// Captain reference: #343232 / #000000, distortion 1, swirl 0.3, grainMixer 0.31,
/// grainOverlay 0, speed 0.26, scale 0.52, rotation 90°.
struct PaperMeshBackground: View {
    enum Surface {
        case settingsWindow
        case settingsSidebar
        case settingsDetail
        case activity
    }

    var surface: Surface = .activity
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    /// Captain Paper params.
    private let distortion: Float = 1.0
    private let swirl: Float = 0.3
    private let grainMixer: Float = 0.31
    private let grainOverlay: Float = 0.0
    private let speed: Double = 0.26
    private let scale: Float = 0.52
    private let rotationDegrees: Float = 90

    private var opacity: Double {
        switch surface {
        case .settingsDetail:
            return 0 // Form stays readable — no wash under controls
        case .settingsSidebar:
            return 0.28
        case .settingsWindow:
            return 0.42
        case .activity:
            return 0.85
        }
    }

    var body: some View {
        Group {
            if reduceTransparency || contrast == .increased {
                IntakeColor.surface
            } else if surface == .settingsDetail {
                Color.clear
            } else if reduceMotion || !animated {
                mesh(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
                    mesh(at: context.date.timeIntervalSinceReferenceDate * speed)
                }
            }
        }
        .opacity(opacity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func mesh(at time: TimeInterval) -> some View {
        Rectangle()
            .fill(Color.black)
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.intakePaperMesh(
                        .float2(proxy.size),
                        .float(Float(time)),
                        .float(distortion),
                        .float(swirl),
                        .float(grainMixer),
                        .float(grainOverlay),
                        .float(scale),
                        .float(rotationDegrees),
                        .color(PaperMeshPalette.graphite),
                        .color(PaperMeshPalette.black)
                    )
                )
            }
    }
}

private enum PaperMeshPalette {
    /// `#343232`
    static let graphite = Color(red: 0x34 / 255, green: 0x32 / 255, blue: 0x32 / 255)
    /// `#000000`
    static let black = Color.black
}
