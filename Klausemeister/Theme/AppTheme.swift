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
        }
    }

    var displayName: String {
        "\(family.displayName) \(variantName)"
    }

    var isDark: Bool {
        switch self {
        case .everforestDarkHard, .everforestDarkMedium, .everforestDarkSoft,
             .gruvboxDarkHard, .gruvboxDarkMedium, .gruvboxDarkSoft,
             .catppuccinFrappe, .catppuccinMacchiato, .catppuccinMocha:
            true
        case .everforestLightHard, .everforestLightMedium, .everforestLightSoft,
             .gruvboxLightHard, .gruvboxLightMedium, .gruvboxLightSoft,
             .catppuccinLatte:
            false
        }
    }

    /// Maps legacy `@AppStorage` raw values (pre-multi-family) to the
    /// corresponding Everforest case, so existing users keep their theme.
    static func legacyMigration(_ stored: String) -> AppTheme? {
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

    static func resolve(stored: String?) -> AppTheme {
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

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .everforest: "Everforest"
        case .gruvbox: "Gruvbox"
        case .catppuccin: "Catppuccin"
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
        }
    }
}

extension EnvironmentValues {
    @Entry var themeColors: ThemeColors = AppTheme.everforestDarkMedium.colors
}
