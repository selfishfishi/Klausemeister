// Klausemeister/CommandPalette/FuzzyMatcher.swift
import Foundation

/// Simple subsequence fuzzy matcher with scoring. No external dependencies.
/// Returns nil if `query` is not a subsequence of `target`.
enum FuzzyMatcher {
    struct Match: Equatable {
        let score: Int
        /// Character offsets (not String.Index) into the target string. Portable
        /// across string representations and safe to store independently.
        let matchedOffsets: [Int]
    }

    static func match(query: String, against target: String) -> Match? {
        let queryLower = query.lowercased()
        let targetLower = target.lowercased()
        guard !queryLower.isEmpty else {
            return Match(score: 0, matchedOffsets: [])
        }

        var queryIndex = queryLower.startIndex
        var matchedOffsets: [Int] = []
        var score = 1000
        var lastMatchOffset: Int?
        var gapCount = 0
        var charOffset = 0

        for targetIndex in targetLower.indices {
            guard queryIndex < queryLower.endIndex else { break }

            if targetLower[targetIndex] == queryLower[queryIndex] {
                matchedOffsets.append(charOffset)

                // Bonus: consecutive match
                if let last = lastMatchOffset, last == charOffset - 1 {
                    score += 15
                }
                // Bonus: start of string
                if charOffset == 0 {
                    score += 10
                }
                // Bonus: word boundary (space, dash, underscore, or camelCase)
                if targetIndex > targetLower.startIndex {
                    let prevIndex = targetLower.index(before: targetIndex)
                    let prev = target[prevIndex]
                    if prev == " " || prev == "-" || prev == "_" {
                        score += 8
                    } else if prev.isLowercase, target[targetIndex].isUppercase {
                        score += 8
                    }
                }

                score -= gapCount
                gapCount = 0
                lastMatchOffset = charOffset
                queryIndex = queryLower.index(after: queryIndex)
            } else {
                gapCount += 1
            }
            charOffset += 1
        }

        guard queryIndex == queryLower.endIndex else { return nil }

        // Penalty for longer targets (favor shorter, more precise matches)
        score -= (target.count - query.count) / 10

        return Match(score: score, matchedOffsets: matchedOffsets)
    }
}
