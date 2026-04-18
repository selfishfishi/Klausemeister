import SwiftUI

// Canonical Gruvbox palette — morhetz/gruvbox.

private struct GruvboxContrast {
    let background: String
    let bg1: String
    let selectionBg: String
}

extension AppTheme {
    var gruvboxColors: ThemeColors {
        isDark ? gruvboxDark : gruvboxLight
    }

    private var gruvboxDark: ThemeColors {
        let contrast: GruvboxContrast = switch self {
        case .gruvboxDarkHard:
            GruvboxContrast(background: "#1D2021", bg1: "#3C3836", selectionBg: "#504945")
        case .gruvboxDarkMedium:
            GruvboxContrast(background: "#282828", bg1: "#3C3836", selectionBg: "#504945")
        case .gruvboxDarkSoft:
            GruvboxContrast(background: "#32302F", bg1: "#3C3836", selectionBg: "#504945")
        default: fatalError("Not a Gruvbox dark theme")
        }
        let pal = gruvboxDarkPalette(bg1: contrast.bg1)
        return ThemeColors(
            isDark: true,
            accentColor: Color(hex: 0xB8BB26),
            warningColor: Color(hex: 0xFABD2F),
            errorColor: Color(hex: 0xFB4934),
            background: contrast.background,
            foreground: "#EBDBB2",
            palette: pal,
            cursorColor: "#EBDBB2",
            selectionBg: contrast.selectionBg,
            selectionFg: "#EBDBB2",
            glowIntensity: 1.0,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }

    private var gruvboxLight: ThemeColors {
        let contrast: GruvboxContrast = switch self {
        case .gruvboxLightHard:
            GruvboxContrast(background: "#F9F5D7", bg1: "#EBDBB2", selectionBg: "#D5C4A1")
        case .gruvboxLightMedium:
            GruvboxContrast(background: "#FBF1C7", bg1: "#EBDBB2", selectionBg: "#D5C4A1")
        case .gruvboxLightSoft:
            GruvboxContrast(background: "#F2E5BC", bg1: "#EBDBB2", selectionBg: "#D5C4A1")
        default: fatalError("Not a Gruvbox light theme")
        }
        let pal = gruvboxLightPalette(bg1: contrast.bg1)
        return ThemeColors(
            isDark: false,
            accentColor: Color(hex: 0x79740E),
            warningColor: Color(hex: 0xB57614),
            errorColor: Color(hex: 0x9D0006),
            background: contrast.background,
            foreground: "#3C3836",
            palette: pal,
            cursorColor: "#3C3836",
            selectionBg: contrast.selectionBg,
            selectionFg: "#3C3836",
            glowIntensity: 0.55,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }
}

private func gruvboxDarkPalette(bg1: String) -> [String] {
    [
        bg1, // 0  black (use bg1 so row tinting has a deep base)
        "#CC241D", // 1  red
        "#98971A", // 2  green
        "#D79921", // 3  yellow
        "#458588", // 4  blue
        "#B16286", // 5  magenta (purple)
        "#689D6A", // 6  cyan (aqua)
        "#A89984", // 7  white (gray)
        "#928374", // 8  bright black
        "#FB4934", // 9  bright red
        "#B8BB26", // 10 bright green
        "#FABD2F", // 11 bright yellow
        "#83A598", // 12 bright blue
        "#D3869B", // 13 bright magenta
        "#8EC07C", // 14 bright cyan
        "#EBDBB2" // 15 bright white
    ]
}

private func gruvboxLightPalette(bg1: String) -> [String] {
    [
        bg1, // 0  black (fg on light = dark brown/grey base)
        "#CC241D", // 1  red
        "#98971A", // 2  green
        "#D79921", // 3  yellow
        "#458588", // 4  blue
        "#B16286", // 5  magenta
        "#689D6A", // 6  cyan (aqua)
        "#7C6F64", // 7  white (gray4)
        "#928374", // 8  bright black
        "#9D0006", // 9  bright red (faded/strong)
        "#79740E", // 10 bright green
        "#B57614", // 11 bright yellow
        "#076678", // 12 bright blue
        "#8F3F71", // 13 bright magenta
        "#427B58", // 14 bright cyan
        "#3C3836" // 15 bright white (fg1)
    ]
}
