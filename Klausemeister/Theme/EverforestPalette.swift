import SwiftUI

private struct ContrastSet {
    let background: String
    let bg1: String
    let selectionBg: String
}

extension AppTheme {
    var colors: ThemeColors {
        if isDark {
            darkColors
        } else {
            lightColors
        }
    }

    private var darkColors: ThemeColors {
        let contrast: ContrastSet = switch self {
        case .darkHard: ContrastSet(background: "#272E33", bg1: "#2E383C", selectionBg: "#4C3743")
        case .darkMedium: ContrastSet(background: "#2D353B", bg1: "#343F44", selectionBg: "#543A48")
        case .darkSoft: ContrastSet(background: "#333C43", bg1: "#3A464C", selectionBg: "#5C3F4F")
        default: fatalError("Not a dark theme")
        }
        let pal = darkPalette(bg1: contrast.bg1)
        return ThemeColors(
            isDark: true,
            accentColor: Color(hex: 0xA7C080),
            warningColor: Color(hex: 0xDBBC7F),
            errorColor: Color(hex: 0xE67E80),
            background: contrast.background,
            foreground: "#D3C6AA",
            palette: pal,
            cursorColor: "#A7C080",
            selectionBg: contrast.selectionBg,
            selectionFg: "#D3C6AA",
            glowIntensity: 1.0,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }

    private var lightColors: ThemeColors {
        let contrast: ContrastSet = switch self {
        case .lightHard: ContrastSet(background: "#FFFBEF", bg1: "#F8F5E4", selectionBg: "#F0F2D4")
        case .lightMedium: ContrastSet(background: "#FDF6E3", bg1: "#F4F0D9", selectionBg: "#EAEDC8")
        case .lightSoft: ContrastSet(background: "#F3EAD3", bg1: "#EAE4CA", selectionBg: "#E1E4BD")
        default: fatalError("Not a light theme")
        }
        let pal = lightPalette(bg1: contrast.bg1)
        return ThemeColors(
            isDark: false,
            accentColor: Color(hex: 0x8DA101),
            warningColor: Color(hex: 0xDFA000),
            errorColor: Color(hex: 0xF85552),
            background: contrast.background,
            foreground: "#5C6A72",
            palette: pal,
            cursorColor: "#8DA101",
            selectionBg: contrast.selectionBg,
            selectionFg: "#5C6A72",
            glowIntensity: 0.55,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }
}

private func darkPalette(bg1: String) -> [String] {
    [
        bg1, // 0  black
        "#E67E80", // 1  red
        "#A7C080", // 2  green
        "#DBBC7F", // 3  yellow
        "#7FBBB3", // 4  blue
        "#D699B6", // 5  magenta
        "#83C092", // 6  cyan
        "#D3C6AA", // 7  white
        "#7A8478", // 8  bright black
        "#E67E80", // 9  bright red
        "#A7C080", // 10 bright green
        "#E69875", // 11 bright yellow (orange)
        "#7FBBB3", // 12 bright blue
        "#D699B6", // 13 bright magenta
        "#83C092", // 14 bright cyan
        "#9DA9A0" // 15 bright white
    ]
}

private func lightPalette(bg1: String) -> [String] {
    [
        bg1, // 0  black
        "#F85552", // 1  red
        "#8DA101", // 2  green
        "#DFA000", // 3  yellow
        "#3A94C5", // 4  blue
        "#DF69BA", // 5  magenta
        "#35A77C", // 6  cyan
        "#5C6A72", // 7  white
        "#A6B0A0", // 8  bright black
        "#F85552", // 9  bright red
        "#8DA101", // 10 bright green
        "#F57D26", // 11 bright yellow (orange)
        "#3A94C5", // 12 bright blue
        "#DF69BA", // 13 bright magenta
        "#35A77C", // 14 bright cyan
        "#829181" // 15 bright white
    ]
}

extension Color {
    init(hex: UInt32) {
        // swiftlint:disable identifier_name
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        // swiftlint:enable identifier_name
        self.init(red: r, green: g, blue: b)
    }

    init(hexString: String) {
        let hex = String(hexString.dropFirst()) // remove #
        self.init(hex: UInt32(hex, radix: 16) ?? 0)
    }
}
