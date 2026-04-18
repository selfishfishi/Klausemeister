import SwiftUI

// Canonical Catppuccin palettes — catppuccin/catppuccin.
// Flavors: Latte (light), Frappé, Macchiato, Mocha (darkest).

extension AppTheme {
    var catppuccinColors: ThemeColors {
        switch self {
        case .catppuccinMocha: mochaColors
        case .catppuccinMacchiato: macchiatoColors
        case .catppuccinFrappe: frappeColors
        case .catppuccinLatte: latteColors
        default: fatalError("Not a Catppuccin theme")
        }
    }

    // MARK: - Mocha

    private var mochaColors: ThemeColors {
        let pal = [
            "#45475A", // 0  black (surface1)
            "#F38BA8", // 1  red
            "#A6E3A1", // 2  green
            "#F9E2AF", // 3  yellow
            "#89B4FA", // 4  blue
            "#F5C2E7", // 5  magenta (pink)
            "#94E2D5", // 6  cyan (teal)
            "#BAC2DE", // 7  white (subtext1)
            "#585B70", // 8  bright black (surface2)
            "#F38BA8", // 9  bright red
            "#A6E3A1", // 10 bright green
            "#F9E2AF", // 11 bright yellow
            "#89B4FA", // 12 bright blue
            "#F5C2E7", // 13 bright magenta
            "#94E2D5", // 14 bright cyan
            "#A6ADC8" // 15 bright white (subtext0)
        ]
        return ThemeColors(
            isDark: true,
            accentColor: Color(hex: 0xCBA6F7), // mauve
            warningColor: Color(hex: 0xF9E2AF), // yellow
            errorColor: Color(hex: 0xF38BA8), // red
            background: "#1E1E2E", // base
            foreground: "#CDD6F4", // text
            palette: pal,
            cursorColor: "#F5E0DC", // rosewater
            selectionBg: "#585B70", // surface2
            selectionFg: "#CDD6F4",
            glowIntensity: 1.0,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }

    // MARK: - Macchiato

    private var macchiatoColors: ThemeColors {
        let pal = [
            "#494D64", // 0  surface1
            "#ED8796", // 1  red
            "#A6DA95", // 2  green
            "#EED49F", // 3  yellow
            "#8AADF4", // 4  blue
            "#F5BDE6", // 5  pink
            "#8BD5CA", // 6  teal
            "#B8C0E0", // 7  subtext1
            "#5B6078", // 8  surface2
            "#ED8796",
            "#A6DA95",
            "#EED49F",
            "#8AADF4",
            "#F5BDE6",
            "#8BD5CA",
            "#A5ADCB" // 15 subtext0
        ]
        return ThemeColors(
            isDark: true,
            accentColor: Color(hex: 0xC6A0F6), // mauve
            warningColor: Color(hex: 0xEED49F),
            errorColor: Color(hex: 0xED8796),
            background: "#24273A",
            foreground: "#CAD3F5",
            palette: pal,
            cursorColor: "#F4DBD6",
            selectionBg: "#5B6078",
            selectionFg: "#CAD3F5",
            glowIntensity: 1.0,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }

    // MARK: - Frappé

    private var frappeColors: ThemeColors {
        let pal = [
            "#51576D", // 0  surface1
            "#E78284", // 1
            "#A6D189",
            "#E5C890",
            "#8CAAEE",
            "#F4B8E4",
            "#81C8BE",
            "#B5BFE2", // 7  subtext1
            "#626880", // 8  surface2
            "#E78284",
            "#A6D189",
            "#E5C890",
            "#8CAAEE",
            "#F4B8E4",
            "#81C8BE",
            "#A5ADCE" // 15 subtext0
        ]
        return ThemeColors(
            isDark: true,
            accentColor: Color(hex: 0xCA9EE6), // mauve
            warningColor: Color(hex: 0xE5C890),
            errorColor: Color(hex: 0xE78284),
            background: "#303446",
            foreground: "#C6D0F5",
            palette: pal,
            cursorColor: "#F2D5CF",
            selectionBg: "#626880",
            selectionFg: "#C6D0F5",
            glowIntensity: 1.0,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }

    // MARK: - Latte

    private var latteColors: ThemeColors {
        let pal = [
            "#BCC0CC", // 0  surface1 (used as dark row base on light bg)
            "#D20F39", // 1  red
            "#40A02B", // 2  green
            "#DF8E1D", // 3  yellow
            "#1E66F5", // 4  blue
            "#EA76CB", // 5  pink
            "#179299", // 6  teal
            "#5C5F77", // 7  subtext1
            "#ACB0BE", // 8  surface2
            "#D20F39",
            "#40A02B",
            "#DF8E1D",
            "#1E66F5",
            "#EA76CB",
            "#179299",
            "#6C6F85" // 15 subtext0
        ]
        return ThemeColors(
            isDark: false,
            accentColor: Color(hex: 0x8839EF), // mauve
            warningColor: Color(hex: 0xDF8E1D),
            errorColor: Color(hex: 0xD20F39),
            background: "#EFF1F5", // base
            foreground: "#4C4F69", // text
            palette: pal,
            cursorColor: "#DC8A78", // rosewater
            selectionBg: "#ACB0BE", // surface2
            selectionFg: "#4C4F69",
            glowIntensity: 0.55,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }
}
