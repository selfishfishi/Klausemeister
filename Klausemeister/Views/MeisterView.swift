import ComposableArchitecture
import SwiftUI

struct MeisterView: View {
    @Bindable var store: StoreOf<MeisterFeature>

    var body: some View {
        VStack(spacing: 0) {
            // Import bar
            HStack(spacing: 8) {
                TextField("Import issue: KLA-15 or paste URL...", text: $store.importText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.send(.importSubmitted) }
                if store.isImporting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(12)

            // Error banner
            if let error = store.error {
                HStack {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") {
                        store.send(.set(\.error, nil))
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // Kanban board
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(store.columns) { column in
                        KanbanColumnView(
                            column: column,
                            workflowStates: store.workflowStates,
                            onMoveToStatus: { issueId, statusId in
                                store.send(.moveToStatusTapped(issueId: issueId, statusId: statusId))
                            },
                            onRemove: { issueId in
                                store.send(.removeIssueTapped(issueId: issueId))
                            },
                            onDrop: { issueId in
                                guard let fromColumn = store.columns.first(where: {
                                    $0.issues.contains { $0.id == issueId }
                                }) else { return }
                                store.send(.issueMoved(
                                    issueId: issueId,
                                    fromColumnId: fromColumn.id,
                                    toColumnId: column.id
                                ))
                            }
                        )
                    }
                }
                .padding(12)
            }

            if store.isRefreshing {
                ProgressView("Refreshing...")
                    .controlSize(.small)
                    .padding(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { store.send(.onAppear) }
    }
}
