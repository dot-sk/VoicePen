import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct VoicePenTheme {
    let isDark: Bool
    let background: Color
    let surface: Color
    let surfaceElevated: Color
    let border: Color
    let borderStrong: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let blue: Color
    let green: Color
    let purple: Color
    let orange: Color
    let yellow: Color
    let red: Color
    let cardShadow: Color

    var gridLine: Color {
        isDark ? Color.white.opacity(0.10) : Color(red: 0.18, green: 0.22, blue: 0.30).opacity(0.08)
    }

    var panelHighlight: Color {
        isDark ? blue.opacity(0.06) : blue.opacity(0.026)
    }

    var emphasizedCardBorder: Color {
        isDark ? borderStrong : border.opacity(0.86)
    }

    var heroText: LinearGradient {
        LinearGradient(
            colors: isDark ? [Color.white, blue.opacity(0.86)] : [blue, purple],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var heroGlow: Color {
        isDark ? blue.opacity(0.30) : blue.opacity(0.07)
    }

    var heroBackground: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [Color(red: 0.04, green: 0.07, blue: 0.12), surfaceElevated]
                : [surface, Color(red: 0.970, green: 0.982, blue: 1.000)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var heroBorder: Color {
        blue.opacity(0.30)
    }

    var statusBorder: Color {
        isDark ? border : border.opacity(0.74)
    }

    func glassFill(tint: Color) -> LinearGradient {
        LinearGradient(
            colors: isDark
                ? [
                    Color.white.opacity(0.080),
                    tint.opacity(0.050),
                    Color.white.opacity(0.024)
                ]
                : [
                    Color.white.opacity(0.86),
                    tint.opacity(0.070),
                    Color.white.opacity(0.58)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func glassStroke(tint: Color) -> LinearGradient {
        LinearGradient(
            colors: isDark
                ? [
                    Color.white.opacity(0.18),
                    tint.opacity(0.24),
                    Color.white.opacity(0.06)
                ]
                : [
                    Color.white.opacity(0.86),
                    tint.opacity(0.20),
                    border.opacity(0.34)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var heatmapCellBorder: Color {
        isDark ? Color.white.opacity(0.05) : Color.white.opacity(0.82)
    }

    var emptyProgressSegment: Color {
        surfaceElevated
    }

    static func resolve(_ colorScheme: ColorScheme) -> VoicePenTheme {
        if colorScheme == .dark {
            return VoicePenTheme(
                isDark: true,
                background: Color(red: 0.03, green: 0.05, blue: 0.08),
                surface: Color(red: 0.05, green: 0.08, blue: 0.12),
                surfaceElevated: Color(red: 0.07, green: 0.10, blue: 0.15),
                border: Color.white.opacity(0.12),
                borderStrong: Color(red: 0.34, green: 0.45, blue: 1.00).opacity(0.34),
                textPrimary: Color.white.opacity(0.96),
                textSecondary: Color.white.opacity(0.66),
                textTertiary: Color.white.opacity(0.42),
                blue: Color(red: 0.28, green: 0.43, blue: 1.00),
                green: Color(red: 0.39, green: 0.85, blue: 0.36),
                purple: Color(red: 0.56, green: 0.44, blue: 1.00),
                orange: Color(red: 1.00, green: 0.54, blue: 0.16),
                yellow: Color(red: 0.97, green: 0.84, blue: 0.22),
                red: Color(red: 1.00, green: 0.32, blue: 0.32),
                cardShadow: Color.black.opacity(0.35)
            )
        }

        return VoicePenTheme(
            isDark: false,
            background: Color(red: 0.972, green: 0.978, blue: 0.992),
            surface: Color.white,
            surfaceElevated: Color(red: 0.988, green: 0.992, blue: 1.000),
            border: Color(red: 0.80, green: 0.84, blue: 0.91).opacity(0.60),
            borderStrong: Color(red: 0.42, green: 0.50, blue: 0.96).opacity(0.24),
            textPrimary: Color(red: 0.08, green: 0.10, blue: 0.15),
            textSecondary: Color(red: 0.35, green: 0.39, blue: 0.48),
            textTertiary: Color(red: 0.54, green: 0.58, blue: 0.67),
            blue: Color(red: 0.28, green: 0.39, blue: 0.95),
            green: Color(red: 0.22, green: 0.68, blue: 0.46),
            purple: Color(red: 0.50, green: 0.42, blue: 0.92),
            orange: Color(red: 0.91, green: 0.55, blue: 0.30),
            yellow: Color(red: 0.96, green: 0.80, blue: 0.24),
            red: Color(red: 0.86, green: 0.22, blue: 0.24),
            cardShadow: Color(red: 0.22, green: 0.28, blue: 0.38).opacity(0.08)
        )
    }

    func heatmapColor(value: Double) -> Color {
        let normalized = max(0, min(1, value))
        if isDark {
            switch normalized {
            case 0:
                return Color(red: 0.10, green: 0.15, blue: 0.24).opacity(0.70)
            case ..<0.20:
                return Color(red: 0.14, green: 0.20, blue: 0.42)
            case ..<0.45:
                return Color(red: 0.18, green: 0.30, blue: 0.66)
            case ..<0.70:
                return Color(red: 0.28, green: 0.43, blue: 0.90)
            default:
                return Color(red: 0.48, green: 0.50, blue: 1.00)
            }
        }

        switch normalized {
        case 0:
            return Color(red: 0.92, green: 0.94, blue: 0.99)
        case ..<0.20:
            return Color(red: 0.82, green: 0.86, blue: 0.98)
        case ..<0.45:
            return Color(red: 0.66, green: 0.72, blue: 0.97)
        case ..<0.70:
            return Color(red: 0.45, green: 0.54, blue: 0.95)
        default:
            return Color(red: 0.28, green: 0.39, blue: 0.95)
        }
    }
}

private struct VoicePenThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = VoicePenTheme.resolve(.light)
}

extension EnvironmentValues {
    var voicePenTheme: VoicePenTheme {
        get { self[VoicePenThemeEnvironmentKey.self] }
        set { self[VoicePenThemeEnvironmentKey.self] = newValue }
    }
}

extension View {
    func voicePenThemedScreen(_ theme: VoicePenTheme) -> some View {
        scrollContentBackground(.hidden)
            .background(theme.background)
            .tint(theme.blue)
    }
}

#if os(macOS)
    extension VoicePenTheme {
        static func resolve(_ appearance: NSAppearance) -> VoicePenTheme {
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return resolve(match == .darkAqua ? .dark : .light)
        }

        var accentNSColor: NSColor {
            if isDark {
                return NSColor(calibratedRed: 0.28, green: 0.43, blue: 1.00, alpha: 1)
            }
            return NSColor(calibratedRed: 0.28, green: 0.39, blue: 0.95, alpha: 1)
        }

        var dangerNSColor: NSColor {
            if isDark {
                return NSColor(calibratedRed: 1.00, green: 0.32, blue: 0.32, alpha: 1)
            }
            return NSColor(calibratedRed: 0.86, green: 0.22, blue: 0.24, alpha: 1)
        }
    }
#endif
