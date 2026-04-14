import SwiftUI

struct InspectorEmptyView: View {
    @Environment(\.themeColors) private var themeColors

    var body: some View {
        ZStack {
            Color(hexString: themeColors.background)
            themeColors.accentColor.opacity(0.04)
            Text("Select an item to inspect")
                .foregroundStyle(.secondary)
                .padding()
        }
        .ignoresSafeArea()
    }
}
