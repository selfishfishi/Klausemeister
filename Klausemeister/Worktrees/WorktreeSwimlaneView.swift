import ComposableArchitecture
import SwiftUI

struct WorktreeSwimlaneView: View {
    @Bindable var store: StoreOf<WorktreeFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            swimlanes
        }
        .task { store.send(.onAppear) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Worktrees")
                .font(.headline)
            Spacer()
            TextField("New worktree...", text: $store.newWorktreeName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .onSubmit { store.send(.createWorktreeTapped) }
            if store.isCreatingWorktree {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(12)
    }

    private var swimlanes: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 12) {
                ForEach(store.worktrees) { worktree in
                    SwimlaneRowView(
                        worktree: worktree,
                        onDelete: {
                            store.send(.confirmDeleteTapped(worktreeId: worktree.id))
                        }
                    )
                }
            }
            .padding(12)
        }
    }
}
