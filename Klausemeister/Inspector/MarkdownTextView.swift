import MarkdownUI
import SwiftUI

/// Themed wrapper around MarkdownUI's `Markdown` view. Renders Linear ticket
/// descriptions inside the inspector with sizing and palette hooks that match
/// the rest of the panel.
struct MarkdownTextView: View {
    let markdown: String

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        Markdown(markdown)
            .markdownTheme(ThemeCache.shared.theme(for: themeColors))
            .markdownTextStyle {
                FontFamilyVariant(.normal)
                FontSize(.em(1.0))
            }
            .textSelection(.enabled)
    }
}

/// Theme construction is expensive (chain of builder closures reallocated every
/// call). Views re-evaluate `body` frequently; cache by background hex so each
/// theme variant pays the cost once per session.
@MainActor
private final class ThemeCache {
    static let shared = ThemeCache()

    private var cache: [String: Theme] = [:]

    func theme(for themeColors: ThemeColors) -> Theme {
        let key = themeColors.background
        if let cached = cache[key] { return cached }
        let built = Theme.inspector(themeColors: themeColors)
        cache[key] = built
        return built
    }
}

private extension Theme {
    static func inspector(themeColors: ThemeColors) -> Theme {
        Theme.gitHub
            .text {
                FontFamily(.system())
                FontSize(13)
                ForegroundColor(.primary)
            }
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.4))
                    }
                    .padding(.vertical, 4)
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.2))
                    }
                    .padding(.vertical, 3)
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.05))
                    }
                    .padding(.vertical, 2)
            }
            .link {
                ForegroundColor(themeColors.accentColor)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.9))
                BackgroundColor(.secondary.opacity(0.15))
            }
            .codeBlock { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
            }
            .blockquote { configuration in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(.tertiary)
                        .frame(width: 3)
                    configuration.label
                        .markdownTextStyle { ForegroundColor(.secondary) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
    }
}

#Preview {
    ScrollView {
        MarkdownTextView(markdown: """
        # Heading 1

        Regular paragraph with **bold**, *italic*, and `inline code`. Plus a [link](https://example.com).

        ## Heading 2

        ### Scope

        - First bullet point with **bold**
        - Second bullet
        - Third bullet with `code`

        ### Steps

        1. First numbered item
        2. Second numbered item
        3. Third numbered item

        ```swift
        let foo = "bar"
        print(foo)
        ```

        > This is a blockquote with **bold** text.

        ---

        Another paragraph after a divider.

        | Col A | Col B |
        | ----- | ----- |
        | One   | Two   |
        | Three | Four  |

        - [x] Completed task
        - [ ] Pending task
        """)
        .padding()
    }
    .frame(width: 380, height: 800)
    .environment(\.themeColors, AppTheme.darkMedium.colors)
}
