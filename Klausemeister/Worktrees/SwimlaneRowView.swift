import SwiftUI

struct SwimlaneRowView: View {
    let worktree: Worktree
    /// Unique per-row tint resolved by the parent from the theme's swimlane
    /// palette. Used as the glass container tint so each lane reads as its
    /// own surface. The 30fps active pulse still uses `accentColor` so all
    /// "work is happening" cues read the same across rows.
    let tint: Color
    let onDelete: () -> Void
    let onRemove: () -> Void
    var onClearInbox: (() -> Void)?
    var onClearOutbox: (() -> Void)?
    var onMarkComplete: (() -> Void)?
    var onReturnToMeister: ((_ issueId: String) -> Void)?
    var onDropToInbox: ((_ issueId: String) -> Void)?
    var onDropToProcessing: ((_ issueId: String) -> Void)?
    var onDropToOutbox: ((_ issueId: String) -> Void)?
    var onSelectIssue: ((_ issueId: String) -> Void)?
    var onSendSlashCommand: ((_ slashCommand: String) -> Void)?
    var onMoveIssueStatus: ((_ issueId: String, _ target: MeisterState) -> Void)?

    @Environment(\.themeColors) private var themeColors
    @Environment(\.swimlaneAnimating) private var isAnimating

    var body: some View {
        rowContent
            .overlay {
                if worktree.isActive {
                    ActiveGlowOverlay(
                        accentColor: themeColors.accentColor,
                        glowIntensity: themeColors.glowIntensity,
                        isAnimating: isAnimating
                    )
                }
            }
            .animation(.easeInOut(duration: 0.3), value: worktree.isActive)
    }

    /// Indices 1–6 of the Everforest palette — red, green, yellow, blue,
    /// magenta, cyan. Excludes bg/fg (0 and 7) and bright/alt variants.
    private var themeCycleColors: [Color] {
        let indices = [1, 2, 3, 4, 5, 6]
        return indices.compactMap { idx in
            guard idx < themeColors.palette.count else { return nil }
            return Color(hexString: themeColors.palette[idx])
        }
    }

    /// Deterministic per-worktree phase offset in `[0, 6.0)` seconds —
    /// desyncs the comet rotation across rows so they don't all show the
    /// same angle and colour at the same moment.
    private static func phaseOffset(for id: String) -> Double {
        let sum = id.utf8.reduce(0) { $0 &+ Int($1) }
        return Double(sum % 600) / 100.0
    }

    // MARK: - Layout

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            contentRow
            Spacer(minLength: 4)
            footerRow
        }
        .padding(14)
        .frame(minHeight: 120, alignment: .top)
        .glassEffect(
            .regular.tint(tint.opacity(0.04)),
            in: RoundedRectangle(cornerRadius: swimlaneGlassCornerRadius, style: .continuous)
        )
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SwimlaneHeaderView(worktree: worktree)
            Spacer()
            ellipsisMenu
        }
    }

    private var contentRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            SwimlaneAdvanceButton(
                worktree: worktree,
                onSendSlashCommand: onSendSlashCommand
            )
            SwimlaneBarRow(
                worktree: worktree,
                onMarkComplete: onMarkComplete,
                onReturnToMeister: onReturnToMeister,
                onSelectIssue: onSelectIssue,
                onSendSlashCommand: onSendSlashCommand,
                onMoveIssueStatus: onMoveIssueStatus,
                onDropToInbox: onDropToInbox,
                onDropToProcessing: onDropToProcessing,
                onDropToOutbox: onDropToOutbox
            )
        }
    }

    @ViewBuilder
    private var footerRow: some View {
        let branch = worktree.currentBranch
        let stats = worktree.gitStats.flatMap { $0.isEmpty ? nil : $0 }
        if branch != nil || stats != nil {
            HStack(spacing: 6) {
                if let branch {
                    Text(branch)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if branch != nil, stats != nil {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let stats {
                    GitStatsLineView(stats: stats)
                }
            }
        }
    }

    private var ellipsisMenu: some View {
        Menu {
            if let onClearInbox {
                Button { onClearInbox() } label: {
                    Label("Clear inbox", systemImage: "tray")
                }
                .disabled(worktree.inbox.isEmpty)
            }
            if let onClearOutbox {
                Button { onClearOutbox() } label: {
                    Label("Clear outbox", systemImage: "tray.and.arrow.up")
                }
                .disabled(worktree.outbox.isEmpty)
            }
            if onClearInbox != nil || onClearOutbox != nil {
                Divider()
            }
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete worktree", systemImage: "trash")
            }
            Button { onRemove() } label: {
                Label("Remove from Klausemeister", systemImage: "minus.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Rotating comet border around the whole swimlane while the meister is
/// actively running a tool. AngularGradient stroke sweeping around the shape
/// (~1.5s per revolution) with a blurred halo + crisp highlight composed
/// via `.plusLighter`, and a colour cycling through the theme palette
/// (~6s full sweep). `phaseOffset` desyncs rows so the comets look
/// independent.
struct SwimlaneWorkingCometOverlay: View {
    let cycleColors: [Color]
    let phaseOffset: Double
    /// When `true`, the 30fps timeline stops ticking entirely so the
    /// comet doesn't burn CPU on rows that aren't currently working.
    var paused: Bool = false
    var cornerRadius: CGFloat = swimlaneGlassCornerRadius

    private let rotationPeriod: Double = 1.5
    private let colorCyclePeriod: Double = 6.0

    var body: some View {
        // 30fps: visual rotation period is 1.5s, so the difference
        // between 30 and 60fps is imperceptible but halves the per-tick
        // cost across every active swimlane.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate - phaseOffset
            let rotationDegrees = (elapsed / rotationPeriod)
                .truncatingRemainder(dividingBy: 1) * 360
            let headColor = interpolatedColor(at: elapsed)
            CometTrailLayer(
                rotationDegrees: rotationDegrees,
                headColor: headColor,
                cornerRadius: cornerRadius
            )
        }
    }

    private func interpolatedColor(at elapsed: Double) -> Color {
        guard !cycleColors.isEmpty else { return .white }
        guard cycleColors.count > 1 else { return cycleColors[0] }
        let count = Double(cycleColors.count)
        let raw = (elapsed / colorCyclePeriod)
            .truncatingRemainder(dividingBy: 1)
        // `truncatingRemainder` can return negatives when `elapsed` is
        // negative (phaseOffset subtraction early after reference epoch);
        // wrap into [0, 1) before scaling.
        let progress = (raw < 0 ? raw + 1 : raw) * count
        let index = Int(progress) % cycleColors.count
        let nextIndex = (index + 1) % cycleColors.count
        let fraction = progress - Double(index)
        return cycleColors[index].mix(with: cycleColors[nextIndex], by: fraction)
    }
}

/// Rotating-trail layer for the comet overlay. Builds the
/// `[Gradient.Stop]` array once per `headColor` change (roughly every
/// ~6s as the palette interpolates) instead of per 30fps frame. Cached
/// via `@State` + `.onChange(of: headColor)`.
private struct CometTrailLayer: View {
    let rotationDegrees: Double
    let headColor: Color
    let cornerRadius: CGFloat

    @State private var stops: [Gradient.Stop] = []

    var body: some View {
        let gradient = Gradient(stops: stops.isEmpty ? Self.makeStops(for: headColor) : stops)
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    AngularGradient(
                        gradient: gradient,
                        center: .center,
                        angle: .degrees(rotationDegrees)
                    ),
                    lineWidth: 3.2
                )
                .blur(radius: 3.5)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    AngularGradient(
                        gradient: gradient,
                        center: .center,
                        angle: .degrees(rotationDegrees)
                    ),
                    lineWidth: 1.2
                )
                .blur(radius: 0.6)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .onAppear { stops = Self.makeStops(for: headColor) }
        .onChange(of: headColor) { _, newColor in
            stops = Self.makeStops(for: newColor)
        }
    }

    private static func makeStops(for headColor: Color) -> [Gradient.Stop] {
        [
            .init(color: .clear, location: 0.00),
            .init(color: .clear, location: 0.50),
            .init(color: headColor.opacity(0.25), location: 0.68),
            .init(color: headColor.opacity(0.70), location: 0.82),
            .init(color: headColor, location: 0.94),
            .init(color: Color.white, location: 1.00)
        ]
    }
}

/// Lightweight view that contains the 30fps TimelineView for the active
/// glow pulse. Extracted so the timeline ticks only re-evaluate this
/// overlay — not the entire `rowContent` subtree (pills, menus, stats).
private struct ActiveGlowOverlay: View {
    let accentColor: Color
    let glowIntensity: Double
    let isAnimating: Bool

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 30.0,
            paused: !isAnimating
        )) { timeline in
            let phase = 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 2 * .pi / 2.0)
            RoundedRectangle(cornerRadius: swimlaneGlassCornerRadius, style: .continuous)
                .stroke(
                    accentColor.opacity((0.3 + 0.5 * phase) * glowIntensity),
                    lineWidth: 1.5
                )
                .shadow(
                    color: accentColor.opacity((0.15 + 0.25 * phase) * glowIntensity),
                    radius: 4 + 8 * phase
                )
        }
    }
}
