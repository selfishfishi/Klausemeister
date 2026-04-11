import Foundation

/// Suggests a default worktree name drawn from the Greek alphabet. When every
/// letter is taken we cycle with a numeric suffix (`alpha-2`, `beta-2`, …).
enum WorktreeDefaultName {
    nonisolated static let greekLetters: [String] = [
        "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta",
        "iota", "kappa", "lambda", "mu", "nu", "xi", "omicron", "pi",
        "rho", "sigma", "tau", "upsilon", "phi", "chi", "psi", "omega"
    ]

    nonisolated static func next(excluding existing: Set<String>) -> String {
        for letter in greekLetters where !existing.contains(letter) {
            return letter
        }
        var suffix = 2
        while true {
            for letter in greekLetters {
                let candidate = "\(letter)-\(suffix)"
                if !existing.contains(candidate) {
                    return candidate
                }
            }
            suffix += 1
        }
    }
}
