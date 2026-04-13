import SwiftUI

/// Swimlane row tinting sourced from the theme's ANSI palette so each
/// worktree reads as its own lane while staying visually consistent with
/// terminal output.
extension ThemeColors {
    /// Build the tint palette from ANSI indices 1–6 (red, green, yellow,
    /// blue, magenta, cyan). Called once at ThemeColors init so the array
    /// is stored rather than recomputed on every view body evaluation.
    static func buildSwimlaneRowTints(from palette: [String]) -> [Color] {
        var seen: Set<String> = []
        return [1, 2, 3, 4, 5, 6].compactMap { index in
            guard palette.indices.contains(index) else { return nil }
            let hex = palette[index]
            guard seen.insert(hex).inserted else { return nil }
            return Color(hexString: hex)
        }
    }

    func teamTint(colorIndex: Int) -> Color {
        guard !swimlaneRowTints.isEmpty else { return accentColor }
        return swimlaneRowTints[colorIndex % swimlaneRowTints.count]
    }
}
