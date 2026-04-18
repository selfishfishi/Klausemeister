import SwiftUI

// Canonical Tokyo Night palettes — folke/tokyonight.nvim.
// Variants: Night (default dark), Storm (lighter bg), Moon (warmer bg), Day (light).

extension AppTheme {
    var tokyoNightColors: ThemeColors {
        switch self {
        case .tokyoNight: nightColors
        case .tokyoNightStorm: stormColors
        case .tokyoNightMoon: moonColors
        case .tokyoNightDay: dayColors
        default: fatalError("Not a Tokyo Night theme")
        }
    }

    // MARK: - Night

    private var nightColors: ThemeColors {
        let pal = [
            "#15161E", // 0  black
            "#F7768E", // 1  red
            "#9ECE6A", // 2  green
            "#E0AF68", // 3  yellow
            "#7AA2F7", // 4  blue
            "#BB9AF7", // 5  magenta
            "#7DCFFF", // 6  cyan
            "#A9B1D6", // 7  white
            "#414868", // 8  bright black
            "#F7768E",
            "#9ECE6A",
            "#E0AF68",
            "#7AA2F7",
            "#BB9AF7",
            "#7DCFFF",
            "#C0CAF5" // 15 bright white
        ]
        return ThemeColors(
            isDark: true,
            accentColor: Color(hex: 0x7AA2F7), // blue
            warningColor: Color(hex: 0xE0AF68),
            errorColor: Color(hex: 0xF7768E),
            background: "#1A1B26",
            foreground: "#C0CAF5",
            palette: pal,
            cursorColor: "#C0CAF5",
            selectionBg: "#283457",
            selectionFg: "#C0CAF5",
            glowIntensity: 1.0,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }

    // MARK: - Storm

    private var stormColors: ThemeColors {
        let pal = [
            "#1D202F", // 0  black
            "#F7768E",
            "#9ECE6A",
            "#E0AF68",
            "#7AA2F7",
            "#BB9AF7",
            "#7DCFFF",
            "#A9B1D6",
            "#414868",
            "#F7768E",
            "#9ECE6A",
            "#E0AF68",
            "#7AA2F7",
            "#BB9AF7",
            "#7DCFFF",
            "#C0CAF5"
        ]
        return ThemeColors(
            isDark: true,
            accentColor: Color(hex: 0x7AA2F7),
            warningColor: Color(hex: 0xE0AF68),
            errorColor: Color(hex: 0xF7768E),
            background: "#24283B",
            foreground: "#C0CAF5",
            palette: pal,
            cursorColor: "#C0CAF5",
            selectionBg: "#2E3C64",
            selectionFg: "#C0CAF5",
            glowIntensity: 1.0,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }

    // MARK: - Moon

    private var moonColors: ThemeColors {
        let pal = [
            "#1B1D2B",
            "#FF757F", // red (moon variant has slightly warmer tones)
            "#C3E88D", // green
            "#FFC777", // yellow
            "#82AAFF", // blue
            "#C099FF", // magenta
            "#86E1FC", // cyan
            "#828BB8",
            "#444A73",
            "#FF757F",
            "#C3E88D",
            "#FFC777",
            "#82AAFF",
            "#C099FF",
            "#86E1FC",
            "#C8D3F5"
        ]
        return ThemeColors(
            isDark: true,
            accentColor: Color(hex: 0x82AAFF),
            warningColor: Color(hex: 0xFFC777),
            errorColor: Color(hex: 0xFF757F),
            background: "#222436",
            foreground: "#C8D3F5",
            palette: pal,
            cursorColor: "#C8D3F5",
            selectionBg: "#2D3F76",
            selectionFg: "#C8D3F5",
            glowIntensity: 1.0,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }

    // MARK: - Day

    private var dayColors: ThemeColors {
        let pal = [
            "#B4B5B9", // 0  dark gray
            "#F52A65", // 1  red
            "#587539", // 2  green
            "#8C6C3E", // 3  yellow
            "#2E7DE9", // 4  blue
            "#9854F1", // 5  magenta
            "#007197", // 6  cyan
            "#6172B0", // 7  muted blue
            "#A1A6C5", // 8  bright black
            "#F52A65",
            "#587539",
            "#8C6C3E",
            "#2E7DE9",
            "#9854F1",
            "#007197",
            "#3760BF"
        ]
        return ThemeColors(
            isDark: false,
            accentColor: Color(hex: 0x2E7DE9),
            warningColor: Color(hex: 0x8C6C3E),
            errorColor: Color(hex: 0xF52A65),
            background: "#E1E2E7",
            foreground: "#3760BF",
            palette: pal,
            cursorColor: "#3760BF",
            selectionBg: "#B7C1E3",
            selectionFg: "#3760BF",
            glowIntensity: 0.55,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }
}
