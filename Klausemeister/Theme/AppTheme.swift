import SwiftUI

enum AppTheme: String, CaseIterable, Codable, Identifiable {
    // Everforest
    case everforestDarkHard
    case everforestDarkMedium
    case everforestDarkSoft
    case everforestLightHard
    case everforestLightMedium
    case everforestLightSoft

    // Gruvbox
    case gruvboxDarkHard
    case gruvboxDarkMedium
    case gruvboxDarkSoft
    case gruvboxLightHard
    case gruvboxLightMedium
    case gruvboxLightSoft

    // Catppuccin
    case catppuccinLatte
    case catppuccinFrappe
    case catppuccinMacchiato
    case catppuccinMocha

    // Tokyo Night
    case tokyoNight
    case tokyoNightStorm
    case tokyoNightMoon
    case tokyoNightDay

    // Rose Pine
    case rosePine
    case rosePineMoon
    case rosePineDawn

    // Kanagawa
    case kanagawaWave
    case kanagawaDragon
    case kanagawaLotus

    var id: String {
        rawValue
    }

    var family: ThemeFamily {
        switch self {
        case .everforestDarkHard, .everforestDarkMedium, .everforestDarkSoft,
             .everforestLightHard, .everforestLightMedium, .everforestLightSoft:
            .everforest
        case .gruvboxDarkHard, .gruvboxDarkMedium, .gruvboxDarkSoft,
             .gruvboxLightHard, .gruvboxLightMedium, .gruvboxLightSoft:
            .gruvbox
        case .catppuccinLatte, .catppuccinFrappe, .catppuccinMacchiato, .catppuccinMocha:
            .catppuccin
        case .tokyoNight, .tokyoNightStorm, .tokyoNightMoon, .tokyoNightDay:
            .tokyoNight
        case .rosePine, .rosePineMoon, .rosePineDawn:
            .rosePine
        case .kanagawaWave, .kanagawaDragon, .kanagawaLotus:
            .kanagawa
        }
    }

    var variantName: String {
        switch self {
        case .everforestDarkHard, .gruvboxDarkHard: "Dark Hard"
        case .everforestDarkMedium, .gruvboxDarkMedium: "Dark Medium"
        case .everforestDarkSoft, .gruvboxDarkSoft: "Dark Soft"
        case .everforestLightHard, .gruvboxLightHard: "Light Hard"
        case .everforestLightMedium, .gruvboxLightMedium: "Light Medium"
        case .everforestLightSoft, .gruvboxLightSoft: "Light Soft"
        case .catppuccinLatte: "Latte"
        case .catppuccinFrappe: "Frappé"
        case .catppuccinMacchiato: "Macchiato"
        case .catppuccinMocha: "Mocha"
        case .tokyoNight: "Night"
        case .tokyoNightStorm: "Storm"
        case .tokyoNightMoon: "Moon"
        case .tokyoNightDay: "Day"
        case .rosePine: "Main"
        case .rosePineMoon: "Moon"
        case .rosePineDawn: "Dawn"
        case .kanagawaWave: "Wave"
        case .kanagawaDragon: "Dragon"
        case .kanagawaLotus: "Lotus"
        }
    }

    var displayName: String {
        "\(family.displayName) \(variantName)"
    }

    var isDark: Bool {
        switch self {
        case .everforestDarkHard, .everforestDarkMedium, .everforestDarkSoft,
             .gruvboxDarkHard, .gruvboxDarkMedium, .gruvboxDarkSoft,
             .catppuccinFrappe, .catppuccinMacchiato, .catppuccinMocha,
             .tokyoNight, .tokyoNightStorm, .tokyoNightMoon,
             .rosePine, .rosePineMoon,
             .kanagawaWave, .kanagawaDragon:
            true
        case .everforestLightHard, .everforestLightMedium, .everforestLightSoft,
             .gruvboxLightHard, .gruvboxLightMedium, .gruvboxLightSoft,
             .catppuccinLatte,
             .tokyoNightDay,
             .rosePineDawn,
             .kanagawaLotus:
            false
        }
    }

    /// Maps legacy `@AppStorage` raw values (pre-multi-family) to the
    /// corresponding Everforest case, so existing users keep their theme.
    /// Pure mapping — nonisolated so migration can run off the main actor.
    nonisolated static func legacyMigration(_ stored: String) -> AppTheme? {
        switch stored {
        case "darkHard": .everforestDarkHard
        case "darkMedium": .everforestDarkMedium
        case "darkSoft": .everforestDarkSoft
        case "lightHard": .everforestLightHard
        case "lightMedium": .everforestLightMedium
        case "lightSoft": .everforestLightSoft
        default: nil
        }
    }

    /// Pure string → theme resolution. Nonisolated so it composes with
    /// `migrateStoredValue`, which runs outside the main actor.
    nonisolated static func resolve(stored: String?) -> AppTheme {
        guard let stored else { return .everforestDarkMedium }
        if let direct = AppTheme(rawValue: stored) { return direct }
        if let legacy = legacyMigration(stored) { return legacy }
        return .everforestDarkMedium
    }

    /// `@AppStorage` key used for the persisted theme selection.
    nonisolated static let storageKey = "selectedTheme"

    /// Read the persisted raw value, migrate it to the current namespace
    /// if it's a legacy string, and write the migrated rawValue back so
    /// `@AppStorage` sees a matching value on its first read. Returns the
    /// effective theme for the session. Takes `UserDefaultsClient` so the
    /// migration is testable without touching `UserDefaults.standard`.
    @discardableResult
    nonisolated static func migrateStoredValue(
        using client: UserDefaultsClient
    ) -> AppTheme {
        let stored = client.string(storageKey)
        let resolved = resolve(stored: stored)
        if stored != resolved.rawValue {
            client.setString(resolved.rawValue, storageKey)
        }
        return resolved
    }
}

enum ThemeFamily: String, CaseIterable, Identifiable {
    case everforest
    case gruvbox
    case catppuccin
    case tokyoNight
    case rosePine
    case kanagawa

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .everforest: "Everforest"
        case .gruvbox: "Gruvbox"
        case .catppuccin: "Catppuccin"
        case .tokyoNight: "Tokyo Night"
        case .rosePine: "Rosé Pine"
        case .kanagawa: "Kanagawa"
        }
    }

    var darkVariants: [AppTheme] {
        switch self {
        case .everforest:
            [.everforestDarkHard, .everforestDarkMedium, .everforestDarkSoft]
        case .gruvbox:
            [.gruvboxDarkHard, .gruvboxDarkMedium, .gruvboxDarkSoft]
        case .catppuccin:
            [.catppuccinMocha, .catppuccinMacchiato, .catppuccinFrappe]
        case .tokyoNight:
            [.tokyoNight, .tokyoNightStorm, .tokyoNightMoon]
        case .rosePine:
            [.rosePine, .rosePineMoon]
        case .kanagawa:
            [.kanagawaWave, .kanagawaDragon]
        }
    }

    var lightVariants: [AppTheme] {
        switch self {
        case .everforest:
            [.everforestLightHard, .everforestLightMedium, .everforestLightSoft]
        case .gruvbox:
            [.gruvboxLightHard, .gruvboxLightMedium, .gruvboxLightSoft]
        case .catppuccin:
            [.catppuccinLatte]
        case .tokyoNight:
            [.tokyoNightDay]
        case .rosePine:
            [.rosePineDawn]
        case .kanagawa:
            [.kanagawaLotus]
        }
    }
}

struct ThemeColors {
    let isDark: Bool
    let accentColor: Color
    let warningColor: Color
    let errorColor: Color
    let background: String
    let foreground: String
    let palette: [String]
    let cursorColor: String
    let selectionBg: String
    let selectionFg: String
    let glowIntensity: Double
    let swimlaneRowTints: [Color]
}

extension AppTheme {
    var colors: ThemeColors {
        switch family {
        case .everforest: everforestColors
        case .gruvbox: gruvboxColors
        case .catppuccin: catppuccinColors
        case .tokyoNight: tokyoNightColors
        case .rosePine: rosePineColors
        case .kanagawa: kanagawaColors
        }
    }
}

extension EnvironmentValues {
    @Entry var themeColors: ThemeColors = AppTheme.everforestDarkMedium.colors
}
