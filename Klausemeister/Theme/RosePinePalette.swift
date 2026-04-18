import SwiftUI

// Canonical Rosé Pine palettes — rose-pine/rose-pine.
// Variants: Main (dark), Moon (dark, slightly warmer), Dawn (light).

extension AppTheme {
    var rosePineColors: ThemeColors {
        switch self {
        case .rosePine: mainColors
        case .rosePineMoon: rpMoonColors
        case .rosePineDawn: dawnColors
        default: fatalError("Not a Rosé Pine theme")
        }
    }

    // MARK: - Main

    private var mainColors: ThemeColors {
        let pal = [
            "#26233A", // 0  black (overlay)
            "#EB6F92", // 1  love (red)
            "#31748F", // 2  pine (green)
            "#F6C177", // 3  gold (yellow)
            "#9CCFD8", // 4  foam (blue)
            "#C4A7E7", // 5  iris (magenta)
            "#EBBCBA", // 6  rose (cyan)
            "#E0DEF4", // 7  text (white)
            "#6E6A86", // 8  muted
            "#EB6F92",
            "#31748F",
            "#F6C177",
            "#9CCFD8",
            "#C4A7E7",
            "#EBBCBA",
            "#E0DEF4"
        ]
        return ThemeColors(
            isDark: true,
            accentColor: Color(hex: 0xC4A7E7), // iris
            warningColor: Color(hex: 0xF6C177),
            errorColor: Color(hex: 0xEB6F92),
            background: "#191724", // base
            foreground: "#E0DEF4", // text
            palette: pal,
            cursorColor: "#E0DEF4",
            selectionBg: "#403D52", // highlight high
            selectionFg: "#E0DEF4",
            glowIntensity: 0.95,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }

    // MARK: - Moon

    private var rpMoonColors: ThemeColors {
        let pal = [
            "#393552", // 0  overlay
            "#EB6F92",
            "#3E8FB0", // pine (slightly brighter on moon)
            "#F6C177",
            "#9CCFD8",
            "#C4A7E7",
            "#EA9A97", // rose
            "#E0DEF4",
            "#6E6A86",
            "#EB6F92",
            "#3E8FB0",
            "#F6C177",
            "#9CCFD8",
            "#C4A7E7",
            "#EA9A97",
            "#E0DEF4"
        ]
        return ThemeColors(
            isDark: true,
            accentColor: Color(hex: 0xC4A7E7),
            warningColor: Color(hex: 0xF6C177),
            errorColor: Color(hex: 0xEB6F92),
            background: "#232136",
            foreground: "#E0DEF4",
            palette: pal,
            cursorColor: "#E0DEF4",
            selectionBg: "#44415A",
            selectionFg: "#E0DEF4",
            glowIntensity: 0.95,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }

    // MARK: - Dawn

    private var dawnColors: ThemeColors {
        let pal = [
            "#F2E9E1", // 0  overlay
            "#B4637A", // 1  love
            "#286983", // 2  pine
            "#EA9D34", // 3  gold
            "#56949F", // 4  foam
            "#907AA9", // 5  iris
            "#D7827E", // 6  rose
            "#575279", // 7  text
            "#9893A5", // 8  muted
            "#B4637A",
            "#286983",
            "#EA9D34",
            "#56949F",
            "#907AA9",
            "#D7827E",
            "#575279"
        ]
        return ThemeColors(
            isDark: false,
            accentColor: Color(hex: 0x907AA9),
            warningColor: Color(hex: 0xEA9D34),
            errorColor: Color(hex: 0xB4637A),
            background: "#FAF4ED",
            foreground: "#575279",
            palette: pal,
            cursorColor: "#575279",
            selectionBg: "#DFDAD9", // highlight high (dawn)
            selectionFg: "#575279",
            glowIntensity: 0.55,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }
}
