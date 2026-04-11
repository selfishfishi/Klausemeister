import Foundation

/// Result of sanitizing a user-entered worktree name into a valid git ref.
/// `wasTransformed` is what the Create sheet uses to decide whether to render
/// the `→ <sanitized>` preview under the Name field: when the raw input is
/// already a legal ref, there is nothing to preview.
struct SanitizedBranchName: Equatable {
    let value: String
    let wasTransformed: Bool

    var isEmpty: Bool {
        value.isEmpty
    }
}

enum WorktreeNameSanitizer {
    /// Sanitize a free-form worktree name into a git-ref-safe branch name.
    ///
    /// Rules:
    /// - Case is preserved so ticket-style prefixes like `KLA-85` round-trip.
    /// - ASCII alphanumerics, underscore, and dash are kept.
    /// - Everything else (whitespace, dots, slashes, punctuation, non-ASCII)
    ///   becomes a dash.
    /// - Runs of dashes collapse to one.
    /// - Leading and trailing dashes are trimmed.
    static func sanitize(_ input: String) -> SanitizedBranchName {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed: Set<Character> = Set(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
        )
        let replaced = String(trimmedInput.map { allowed.contains($0) ? $0 : "-" })
        let collapsed = collapseDashes(replaced)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return SanitizedBranchName(
            value: trimmed,
            wasTransformed: trimmed != trimmedInput
        )
    }

    private static func collapseDashes(_ string: String) -> String {
        var result = ""
        var lastWasDash = false
        for character in string {
            if character == "-" {
                if !lastWasDash {
                    result.append(character)
                }
                lastWasDash = true
            } else {
                result.append(character)
                lastWasDash = false
            }
        }
        return result
    }
}
