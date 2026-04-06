import SwiftUI

struct LinearConnectView: View {
    let status: LinearAuthFeature.AuthStatus
    let onConnect: () -> Void

    @Environment(\.themeColors) private var themeColors
    @Environment(\.swimlaneAnimating) private var isAnimating

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 48) {
                logoSection
                connectButton
                if case let .failed(message) = status {
                    errorBanner(message)
                }
            }
            .frame(maxWidth: 400)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Logo

    private var logoSection: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.5 + 0.5 * sin(time * .pi * 2.0 / 3.0)
            let glowRadius = 30 + 20 * pulse
            let glowOpacity = (0.2 + 0.15 * pulse) * themeColors.glowIntensity

            ZStack {
                // Outer glow
                Circle()
                    .fill(themeColors.accentColor.opacity(glowOpacity * 0.5))
                    .frame(width: 160, height: 160)
                    .blur(radius: glowRadius)

                // Linear logo
                Image("LinearLogo")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .foregroundStyle(.primary)
                    .shadow(
                        color: themeColors.accentColor.opacity(glowOpacity),
                        radius: glowRadius * 0.4
                    )
            }
        }
    }

    // MARK: - Button

    private var connectButton: some View {
        Button(action: onConnect) {
            HStack(spacing: 8) {
                if status == .authenticating {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(hexString: themeColors.background))
                    Text("Connecting...")
                        .font(.body.weight(.semibold))
                } else {
                    Text("Connect to Linear")
                        .font(.body.weight(.semibold))
                }
            }
            .foregroundStyle(Color(hexString: themeColors.background))
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(themeColors.accentColor, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: themeColors.accentColor.opacity(0.3 * themeColors.glowIntensity), radius: 12)
        }
        .buttonStyle(.plain)
        .disabled(status == .authenticating)
    }

    // MARK: - Error

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(themeColors.warningColor)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
