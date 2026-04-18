import SwiftUI

// Canonical Kanagawa palettes — rebelot/kanagawa.nvim.
// Variants: Wave (dark, default), Dragon (deeper/warmer), Lotus (light).

extension AppTheme {
    var kanagawaColors: ThemeColors {
        switch self {
        case .kanagawaWave: waveColors
        case .kanagawaDragon: dragonColors
        case .kanagawaLotus: lotusColors
        default: fatalError("Not a Kanagawa theme")
        }
    }

    // MARK: - Wave

    private var waveColors: ThemeColors {
        let pal = [
            "#16161D", // 0  sumiInk0
            "#C34043", // 1  autumnRed
            "#76946A", // 2  autumnGreen
            "#C0A36E", // 3  boatYellow2
            "#7E9CD8", // 4  crystalBlue
            "#957FB8", // 5  oniViolet
            "#6A9589", // 6  waveAqua1
            "#C8C093", // 7  oldWhite
            "#727169", // 8  sumiInk4
            "#E82424", // 9  samuraiRed
            "#98BB6C", // 10 springGreen
            "#E6C384", // 11 carpYellow
            "#7FB4CA", // 12 springBlue
            "#938AA9", // 13 springViolet2
            "#7AA89F", // 14 waveAqua2
            "#DCD7BA" // 15 fujiWhite
        ]
        return ThemeColors(
            isDark: true,
            accentColor: Color(hex: 0x7E9CD8), // crystalBlue
            warningColor: Color(hex: 0xE6C384),
            errorColor: Color(hex: 0xE82424),
            background: "#1F1F28", // sumiInk3
            foreground: "#DCD7BA", // fujiWhite
            palette: pal,
            cursorColor: "#C8C093",
            selectionBg: "#2D4F67", // waveBlue2
            selectionFg: "#DCD7BA",
            glowIntensity: 0.95,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }

    // MARK: - Dragon

    private var dragonColors: ThemeColors {
        let pal = [
            "#0D0C0C", // 0  dragonBlack0
            "#C4746E", // 1  dragonRed
            "#8A9A7B", // 2  dragonGreen
            "#C4B28A", // 3  dragonYellow
            "#8BA4B0", // 4  dragonBlue
            "#A292A3", // 5  dragonViolet
            "#8EA4A2", // 6  dragonAqua
            "#C5C9C5", // 7  dragonWhite
            "#625E5A", // 8  dragonGray
            "#E46876", // 9  dragonPink (bright red)
            "#87A987",
            "#E6C384",
            "#7FB4CA",
            "#957FB8",
            "#7AA89F",
            "#C5C9C5"
        ]
        return ThemeColors(
            isDark: true,
            accentColor: Color(hex: 0x8BA4B0), // dragonBlue
            warningColor: Color(hex: 0xC4B28A),
            errorColor: Color(hex: 0xC4746E),
            background: "#181616", // dragonBlack3
            foreground: "#C5C9C5",
            palette: pal,
            cursorColor: "#C5C9C5",
            selectionBg: "#2D4F67",
            selectionFg: "#C5C9C5",
            glowIntensity: 0.9,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }

    // MARK: - Lotus

    private var lotusColors: ThemeColors {
        let pal = [
            "#DCD5AC", // 0  lotusWhite4
            "#C84053", // 1  autumnRed
            "#6F894E", // 2  autumnGreen
            "#77713F", // 3  boatYellow2
            "#4D699B", // 4  crystalBlue
            "#624C83", // 5  oniViolet
            "#597B75", // 6  waveAqua1
            "#545464", // 7  lotusInk1
            "#8A8980", // 8  lotusGray2
            "#D7474B", // 9  samuraiRed
            "#6E915F", // 10
            "#836F4A", // 11 carpYellow
            "#4E8CA2", // 12 springBlue
            "#5D57A3", // 13
            "#5E857A", // 14
            "#43436C" // 15
        ]
        return ThemeColors(
            isDark: false,
            accentColor: Color(hex: 0x4D699B),
            warningColor: Color(hex: 0x836F4A),
            errorColor: Color(hex: 0xC84053),
            background: "#F2ECBC", // lotusWhite3
            foreground: "#545464",
            palette: pal,
            cursorColor: "#545464",
            selectionBg: "#D5CEA3", // lotusBlue2
            selectionFg: "#545464",
            glowIntensity: 0.55,
            swimlaneRowTints: ThemeColors.buildSwimlaneRowTints(from: pal)
        )
    }
}
