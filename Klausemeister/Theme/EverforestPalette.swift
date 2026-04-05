import SwiftUI

extension AppTheme {
    var colors: ThemeColors {
        switch self {
        case .darkHard:
            ThemeColors(
                accentColor: Color(hex: 0xA7C080),
                background: "#272E33",
                foreground: "#D3C6AA",
                palette: darkPalette(bg1: "#2E383C"),
                cursorColor: "#A7C080",
                selectionBg: "#4C3743",
                selectionFg: "#D3C6AA"
            )
        case .darkMedium:
            ThemeColors(
                accentColor: Color(hex: 0xA7C080),
                background: "#2D353B",
                foreground: "#D3C6AA",
                palette: darkPalette(bg1: "#343F44"),
                cursorColor: "#A7C080",
                selectionBg: "#543A48",
                selectionFg: "#D3C6AA"
            )
        case .darkSoft:
            ThemeColors(
                accentColor: Color(hex: 0xA7C080),
                background: "#333C43",
                foreground: "#D3C6AA",
                palette: darkPalette(bg1: "#3A464C"),
                cursorColor: "#A7C080",
                selectionBg: "#5C3F4F",
                selectionFg: "#D3C6AA"
            )
        case .lightHard:
            ThemeColors(
                accentColor: Color(hex: 0x8DA101),
                background: "#FFFBEF",
                foreground: "#5C6A72",
                palette: lightPalette(bg1: "#F8F5E4"),
                cursorColor: "#8DA101",
                selectionBg: "#F0F2D4",
                selectionFg: "#5C6A72"
            )
        case .lightMedium:
            ThemeColors(
                accentColor: Color(hex: 0x8DA101),
                background: "#FDF6E3",
                foreground: "#5C6A72",
                palette: lightPalette(bg1: "#F4F0D9"),
                cursorColor: "#8DA101",
                selectionBg: "#EAEDC8",
                selectionFg: "#5C6A72"
            )
        case .lightSoft:
            ThemeColors(
                accentColor: Color(hex: 0x8DA101),
                background: "#F3EAD3",
                foreground: "#5C6A72",
                palette: lightPalette(bg1: "#EAE4CA"),
                cursorColor: "#8DA101",
                selectionBg: "#E1E4BD",
                selectionFg: "#5C6A72"
            )
        }
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
