import SwiftUI

/// Paper-inspired black + `#1D16E9` mesh. Native SwiftUI only — never a web view.
struct IntakeMeshBackground: View {
    enum Style {
        case activity
        case settingsWash
    }

    var style: Style = .activity
    var animated: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let freeze = reduceMotion || !animated || reduceTransparency || contrast == .increased
        Group {
            if reduceTransparency || contrast == .increased {
                Rectangle().fill(IntakeColor.surface)
            } else if freeze {
                mesh(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 24, paused: false)) { context in
                    mesh(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .opacity(style == .settingsWash ? 0.12 : 1)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func mesh(at time: TimeInterval) -> some View {
        let driftX = Float(sin(time / 9.0) * 0.05)
        let driftY = Float(cos(time / 11.0) * 0.04)
        let purple = Color(red: 29 / 255, green: 22 / 255, blue: 233 / 255)
        let accent = purple.opacity(0.34)
        let base = baseColor
        let cool = coolGray
        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                SIMD2<Float>(0.0, 0.0),
                SIMD2<Float>(0.5, 0.0),
                SIMD2<Float>(1.0, 0.0),
                SIMD2<Float>(0.0, 0.5),
                SIMD2<Float>(0.50 + driftX, 0.48 + driftY),
                SIMD2<Float>(1.0, 0.5),
                SIMD2<Float>(0.0, 1.0),
                SIMD2<Float>(0.5, 1.0),
                SIMD2<Float>(1.0, 1.0),
            ],
            colors: [
                base,
                cool,
                base,
                cool,
                accent,
                purple.opacity(0.22),
                base,
                accent.opacity(0.8),
                cool,
            ]
        )
    }

    private var baseColor: Color {
        if colorScheme == .dark {
            Color(red: 10 / 255, green: 10 / 255, blue: 12 / 255)
        } else {
            Color(red: 236 / 255, green: 236 / 255, blue: 242 / 255)
        }
    }

    private var coolGray: Color {
        if colorScheme == .dark {
            Color(red: 18 / 255, green: 18 / 255, blue: 24 / 255)
        } else {
            Color(red: 220 / 255, green: 222 / 255, blue: 232 / 255)
        }
    }
}
