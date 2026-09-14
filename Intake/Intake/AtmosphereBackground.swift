import SwiftUI

/// Routes Designer A/B/C atmospheres per surface. Never menu bar / Dock.
struct AtmosphereBackground: View {
    var style: AtmosphereStyle
    var surface: AtmosphereSurface
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var flatten: Bool {
        reduceTransparency || contrast == .increased
    }

    private var freeze: Bool {
        reduceMotion || !animated
    }

    var body: some View {
        Group {
            if flatten {
                IntakeColor.surface
            } else {
                switch style {
                case .quietMesh:
                    QuietMeshAtmosphere(surface: surface, animated: !freeze)
                case .softAurora:
                    SoftAuroraAtmosphere(surface: surface, animated: !freeze)
                case .materialFirst:
                    MaterialFirstAtmosphere(surface: surface)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - A Quiet Mesh

struct QuietMeshAtmosphere: View {
    var surface: AtmosphereSurface
    var animated: Bool

    var body: some View {
        switch surface {
        case .settingsDetail:
            // Grouped Form stays on system background — no mesh under controls.
            Color.clear
        case .settingsWindow:
            QuietMeshGradient(animated: false)
                .opacity(0.10)
                .ignoresSafeArea()
        case .activity:
            QuietMeshGradient(animated: animated)
                .opacity(0.55)
                .ignoresSafeArea()
        }
    }
}

private struct QuietMeshGradient: View {
    var animated: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if animated {
                // Glacial drift — period ≥12s per Designer.
                TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: false)) { context in
                    mesh(at: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                mesh(at: 0)
            }
        }
    }

    private func mesh(at time: TimeInterval) -> some View {
        let drift: Float = animated ? Float(sin(time / 14.0) * 0.03) : 0
        let charcoal = colorScheme == .dark
            ? Color(red: 14 / 255, green: 14 / 255, blue: 18 / 255)
            : Color(red: 236 / 255, green: 236 / 255, blue: 240 / 255)
        let graphite = colorScheme == .dark
            ? Color(red: 22 / 255, green: 22 / 255, blue: 28 / 255)
            : Color(red: 224 / 255, green: 226 / 255, blue: 232 / 255)
        // Soft cool blob — muted indigo/teal, not neon purple beams.
        let cool = Color(red: 70 / 255, green: 92 / 255, blue: 120 / 255)
            .opacity(colorScheme == .dark ? 0.28 : 0.18)

        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                SIMD2<Float>(0.0, 0.0),
                SIMD2<Float>(0.5, 0.0),
                SIMD2<Float>(1.0, 0.0),
                SIMD2<Float>(0.0, 0.5),
                SIMD2<Float>(0.52 + drift, 0.55),
                SIMD2<Float>(1.0, 0.5),
                SIMD2<Float>(0.0, 1.0),
                SIMD2<Float>(0.5, 1.0),
                SIMD2<Float>(1.0, 1.0),
            ],
            colors: [
                charcoal, graphite, charcoal,
                graphite, cool, graphite,
                charcoal, graphite, charcoal,
            ]
        )
    }
}

// MARK: - B Soft Aurora Vignette (NO rays / spokes / center burst)

struct SoftAuroraAtmosphere: View {
    var surface: AtmosphereSurface
    var animated: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch surface {
        case .settingsDetail:
            Color.clear
        case .settingsWindow:
            // Margins / titlebar bleed only — keep detail crisp.
            aurora(edgeStrength: 0.35, centerClear: 0.72)
        case .activity:
            // Stronger at edges; list sits on material in ActivityWindowView.
            aurora(edgeStrength: 0.70, centerClear: 0.55)
        }
    }

    @ViewBuilder
    private func aurora(edgeStrength: Double, centerClear: Double) -> some View {
        let layers = AuroraLayers(animated: animated, colorScheme: colorScheme)
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.55 : 0.06)
            layers
                .opacity(edgeStrength)
            // Center falloff — vignette (not a burst).
            RadialGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(centerClear),
                    Color.clear,
                ],
                center: .center,
                startRadius: 40,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

private struct AuroraLayers: View {
    var animated: Bool
    var colorScheme: ColorScheme

    var body: some View {
        let mint = Color(red: 90 / 255, green: 180 / 255, blue: 160 / 255)
            .opacity(colorScheme == .dark ? 0.22 : 0.12)
        let violet = Color(red: 110 / 255, green: 100 / 255, blue: 170 / 255)
            .opacity(colorScheme == .dark ? 0.20 : 0.10)

        Group {
            if animated {
                TimelineView(.animation(minimumInterval: 1.0 / 8.0, paused: false)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    // Slow opacity crossfade — never rotating beams.
                    let a = 0.55 + 0.45 * sin(t / 11.0)
                    let b = 0.55 + 0.45 * sin(t / 13.0 + 1.2)
                    stack(mintOpacity: a, violetOpacity: b, mint: mint, violet: violet)
                }
            } else {
                stack(mintOpacity: 0.85, violetOpacity: 0.75, mint: mint, violet: violet)
            }
        }
    }

    private func stack(mintOpacity: Double, violetOpacity: Double, mint: Color, violet: Color) -> some View {
        ZStack {
            EllipticalGradient(
                colors: [mint.opacity(mintOpacity), .clear],
                center: .topLeading,
                startRadiusFraction: 0.05,
                endRadiusFraction: 0.85
            )
            EllipticalGradient(
                colors: [violet.opacity(violetOpacity), .clear],
                center: .bottomTrailing,
                startRadiusFraction: 0.05,
                endRadiusFraction: 0.9
            )
            EllipticalGradient(
                colors: [mint.opacity(mintOpacity * 0.5), .clear],
                center: UnitPoint(x: 0.8, y: 0.15),
                startRadiusFraction: 0.0,
                endRadiusFraction: 0.55
            )
        }
    }
}

// MARK: - C Material First (zero mesh / aurora)

struct MaterialFirstAtmosphere: View {
    var surface: AtmosphereSurface

    var body: some View {
        // System materials / window background only — honest HIG baseline.
        switch surface {
        case .settingsWindow, .settingsDetail:
            Color.clear
        case .activity:
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()
        }
    }
}
