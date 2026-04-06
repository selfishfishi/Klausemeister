import ComposableArchitecture
import SwiftUI

struct StatusBarView: View {
    let store: StoreOf<StatusBarFeature>

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        if store.activeError != nil || store.isSyncing {
            barContent
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var barContent: some View {
        HStack(spacing: 8) {
            if let error = store.activeError {
                errorContent(error)
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
    private func errorContent(_ error: StatusBarFeature.StatusError) -> some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(themeColors.warningColor)
            .imageScale(.small)
        Text(error.message)
            .font(.caption)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .textSelection(.enabled)
        Spacer()
        copyButton
        dismissButton
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
