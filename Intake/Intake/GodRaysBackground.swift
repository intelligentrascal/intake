import SwiftUI

/// Paper Design–inspired God Rays for Intake. Native Metal + SwiftUI only (no npm).
/// Captain reference props: blue `#4763ff` + orange `#ff8c00`, black back, bloom `#222287`.
struct GodRaysBackground: View {
    enum Profile {
        /// Settings sidebar — calmer so labels stay readable (HIG).
        case settingsSidebar
        /// Settings detail — richer animated wash behind content.
        case settingsDetail
        /// Activity — very subtle; opt-in only when it still feels product-grade.
        case activitySubtle
    }

    var profile: Profile = .settingsDetail
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    private var params: GodRaysParams {
        switch profile {
        case .settingsDetail:
            // Captain reference — full look on the main Settings pane.
            return GodRaysParams(
                intensity: 0.08,
                density: 0.04,
                spotty: 0.15,
                midSize: 0.39,
                midIntensity: 0.45,
                bloom: 0.64,
                speed: 0.57,
                scale: 0.44,
                offsetY: -0.25,
                opacity: colorScheme == .dark ? 0.72 : 0.40
            )
        case .settingsSidebar:
            // Dimmer / slower / less bloom — readability wins on the nav column.
            return GodRaysParams(
                intensity: 0.05,
                density: 0.03,
                spotty: 0.18,
                midSize: 0.28,
                midIntensity: 0.28,
                bloom: 0.35,
                speed: 0.28,
                scale: 0.50,
                offsetY: -0.15,
                opacity: colorScheme == .dark ? 0.38 : 0.22
            )
        case .activitySubtle:
            return GodRaysParams(
                intensity: 0.04,
                density: 0.025,
                spotty: 0.20,
                midSize: 0.22,
                midIntensity: 0.20,
                bloom: 0.25,
                speed: 0.22,
                scale: 0.55,
                offsetY: -0.35,
                opacity: colorScheme == .dark ? 0.28 : 0.14
            )
        }
    }

    var body: some View {
        let freeze = reduceMotion || !animated
        Group {
            if reduceTransparency || contrast == .increased {
                Rectangle().fill(IntakeColor.surface)
            } else if freeze {
                rays(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
                    rays(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .opacity(params.opacity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func rays(at time: TimeInterval) -> some View {
        let p = params
        let t = Float(time * Double(p.speed))
        Rectangle()
            .fill(Color.black)
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.intakeGodRays(
                        .float2(proxy.size),
                        .float(t),
                        .float(p.intensity),
                        .float(p.density),
                        .float(p.spotty),
                        .float(p.midSize),
                        .float(p.midIntensity),
                        .float(p.bloom),
                        .float(p.scale),
                        .float(p.offsetY),
                        .color(GodRaysPalette.blue),
                        .color(GodRaysPalette.orange),
                        .color(GodRaysPalette.back),
                        .color(GodRaysPalette.bloom)
                    )
                )
            }
    }
}

private struct GodRaysParams {
    var intensity: Float
    var density: Float
    var spotty: Float
    var midSize: Float
    var midIntensity: Float
    var bloom: Float
    var speed: Double
    var scale: Float
    var offsetY: Float
    var opacity: Double
}

private enum GodRaysPalette {
    /// `#4763ff`
    static let blue = Color(red: 0x47 / 255, green: 0x63 / 255, blue: 0xff / 255)
    /// `#ff8c00`
    static let orange = Color(red: 0xff / 255, green: 0x8c / 255, blue: 0x00 / 255)
    /// `#000000`
    static let back = Color.black
    /// `#222287`
    static let bloom = Color(red: 0x22 / 255, green: 0x22 / 255, blue: 0x87 / 255)
}
