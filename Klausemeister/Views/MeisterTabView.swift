import ComposableArchitecture
import SwiftUI

struct MeisterTabView: View {
    let meisterStore: StoreOf<MeisterFeature>
    let worktreeStore: StoreOf<WorktreeFeature>

    var body: some View {
        VSplitView {
            MeisterView(store: meisterStore)
                .frame(minHeight: 200)
            WorktreeSwimlaneView(store: worktreeStore)
                .frame(minHeight: 150)
        }
    }
}
