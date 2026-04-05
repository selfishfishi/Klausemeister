import SwiftUI

enum AppTheme: String, CaseIterable, Codable, Identifiable {
    case darkHard, darkMedium, darkSoft
    case lightHard, lightMedium, lightSoft

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .darkHard: "Dark Hard"
        case .darkMedium: "Dark Medium"
        case .darkSoft: "Dark Soft"
        case .lightHard: "Light Hard"
        case .lightMedium: "Light Medium"
        case .lightSoft: "Light Soft"
        }
    }

    var isDark: Bool {
        switch self {
        case .darkHard, .darkMedium, .darkSoft: true
        case .lightHard, .lightMedium, .lightSoft: false
        }
    }
}

struct ThemeColors {
    let accentColor: Color
    let warningColor: Color
    let background: String
    let foreground: String
    let palette: [String]
    let cursorColor: String
    let selectionBg: String
    let selectionFg: String
    let glowIntensity: Double
}

extension EnvironmentValues {
    @Entry var themeColors: ThemeColors = AppTheme.darkMedium.colors
}
