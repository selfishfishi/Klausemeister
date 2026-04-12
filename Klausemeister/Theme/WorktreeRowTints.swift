import SwiftUI

/// Swimlane row tinting sourced from the theme's ANSI palette so each
/// worktree reads as its own lane while staying visually consistent with
/// terminal output.
extension ThemeColors {
    /// Distinct accent colors for swimlane rows. Drawn from ANSI palette
    /// indices 1–6 — red, green, yellow, blue, magenta, cyan — the vivid
    /// accent band of Everforest. Some theme variants collapse two ANSI
    /// slots to the same hex, so duplicates are filtered.
    var swimlaneRowTints: [Color] {
        var seen: Set<String> = []
        return [1, 2, 3, 4, 5, 6].compactMap { index in
            guard palette.indices.contains(index) else { return nil }
            let hex = palette[index]
            guard seen.insert(hex).inserted else { return nil }
            return Color(hexString: hex)
        }
    }

    func teamTint(colorIndex: Int) -> Color {
        let tints = swimlaneRowTints
        guard !tints.isEmpty else { return accentColor }
        return tints[colorIndex % tints.count]
    }
}
