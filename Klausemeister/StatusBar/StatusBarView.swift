import ComposableArchitecture
import SwiftUI

struct StatusBarView: View {
    let store: StoreOf<StatusBarFeature>

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        if !store.errors.isEmpty || store.isSyncing {
            barContent
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var barContent: some View {
        HStack(spacing: 8) {
            if !store.errors.isEmpty {
                errorContent
            } else if store.isSyncing {
                syncContent
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    @ViewBuilder
    private var syncContent: some View {
        ProgressView()
            .controlSize(.small)
            .tint(themeColors.accentColor)
        Text("Syncing…")
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
    }

    @ViewBuilder
    private var errorContent: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(themeColors.warningColor)
            .imageScale(.small)
        if let summary = store.summaryMessage {
            Text(summary)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
        }
        Spacer()
        if store.errors.count > 1 {
            detailButton
        }
        copyButton
        dismissButton
    }

    private var detailButton: some View {
        Button {
            store.send(.errorDetailToggled)
        } label: {
            Image(systemName: "chevron.up")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .rotationEffect(store.isErrorDetailExpanded ? .degrees(180) : .zero)
        }
        .buttonStyle(.plain)
        .help("Show error details")
        .popover(
            isPresented: Binding(
                get: { store.isErrorDetailExpanded },
                set: { if !$0 { store.send(.errorDetailToggled) } }
            ),
            arrowEdge: .bottom
        ) {
            errorDetailPopover
        }
    }

    private var errorDetailPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.errors) { error in
                HStack(spacing: 6) {
                    if let key = error.teamKey {
                        Text(key)
                            .font(.caption.bold())
                            .foregroundStyle(themeColors.warningColor)
                    }
                    Text(error.message)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button {
                        store.send(.dismissError(id: error.id))
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .frame(minWidth: 280, maxWidth: 400)
    }

    private var copyButton: some View {
        Button {
            store.send(.copyTapped)
        } label: {
            if store.copiedConfirmationVisible {
                Text("Copied")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(themeColors.accentColor)
                    .transition(.opacity)
            } else {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help("Copy error message")
        .animation(.easeInOut(duration: 0.2), value: store.copiedConfirmationVisible)
    }

    private var dismissButton: some View {
        Button {
            store.send(.dismissTapped)
        } label: {
            Image(systemName: "xmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Dismiss")
    }
}
