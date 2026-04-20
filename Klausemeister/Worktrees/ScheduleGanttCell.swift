// Klausemeister/Worktrees/ScheduleGanttCell.swift
import SwiftUI

/// One ticket card inside the gantt grid. Renders identifier + title + weight
/// dots, tinted by status, with status-driven motion overlays (breathing
/// edge for `.queued`; rotating comet trail for `.inProgress`). `done`
/// renders desaturated and dimmed via `displayIntensity` so completed work
/// recedes in the user's eye relative to in-flight and pending cells.
struct GanttCellView: View {
    let item: ScheduleItem

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        let tint = item.status.tint
        let intensity = item.status.displayIntensity

        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.issueIdentifier)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(tint.opacity(0.95 * intensity))
                Text(item.issueTitle)
                    .font(.caption2)
                    .foregroundStyle(.primary.opacity(intensity))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            WeightDots(weight: item.weight, tint: tint, intensity: intensity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(0.12 * intensity))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(tint.opacity(0.55 * intensity), lineWidth: 0.75)
        }
        .overlay {
            statusMotionOverlay(tint: tint)
        }
        .saturation(item.status == .done ? 0.7 : 1.0)
        .shadow(
            color: tint.opacity(item.status == .inProgress ? 0.35 : 0.0),
            radius: 8
        )
    }

    @ViewBuilder
    private func statusMotionOverlay(tint: Color) -> some View {
        switch item.status {
        case .planned, .done:
            EmptyView()
        case .queued:
            CellBreathingEdge(tint: tint, glowIntensity: themeColors.glowIntensity)
        case .inProgress:
            CellCometEdge(
                cycleColors: themeColors.swimlaneRowTints,
                phaseOffset: phaseOffset(for: item.id)
            )
        }
    }

    /// Stable per-cell offset so neighbouring comets desync — same idiom as
    /// `SwimlaneRowView`.
    private func phaseOffset(for identifier: String) -> Double {
        Double(identifier.utf8.reduce(0) { $0 &+ Int($1) } % 100) / 100.0 * 6.0
    }
}

private struct WeightDots: View {
    let weight: Int
    let tint: Color
    let intensity: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0 ..< max(1, weight), id: \.self) { _ in
                Circle()
                    .fill(tint.opacity(0.85 * intensity))
                    .frame(width: 4, height: 4)
            }
        }
    }
}

// MARK: - Cell motion overlays

/// Slow breathing edge pulse for `.queued` cells. ~1.5 s period — slightly
/// faster than the swimlane's 2 s breath so the gantt feels more
/// anticipation-heavy.
private struct CellBreathingEdge: View {
    let tint: Color
    let glowIntensity: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let phase = 0.5 + 0.5 * sin(
                timeline.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.5
            )
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    tint.opacity((0.25 + 0.5 * phase) * glowIntensity),
                    lineWidth: 1.0
                )
                .shadow(
                    color: tint.opacity((0.10 + 0.20 * phase) * glowIntensity),
                    radius: 3 + 4 * phase
                )
        }
        .allowsHitTesting(false)
    }
}

/// Rotating comet trail for `.inProgress` cells. Sized down from
/// `SwimlaneWorkingCometOverlay` (1.2/0.6 vs 3.2/1.2 stroke widths) so the
/// effect reads at cell scale rather than swimlane scale.
private struct CellCometEdge: View {
    let cycleColors: [Color]
    let phaseOffset: Double

    private let rotationPeriod: Double = 1.5
    private let colorCyclePeriod: Double = 6.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate - phaseOffset
            let rotationDegrees = (elapsed / rotationPeriod)
                .truncatingRemainder(dividingBy: 1) * 360
            let headColor = interpolatedColor(at: elapsed)
            cometStroke(rotationDegrees: rotationDegrees, headColor: headColor)
        }
        .allowsHitTesting(false)
    }

    private func interpolatedColor(at elapsed: Double) -> Color {
        guard !cycleColors.isEmpty else { return .white }
        guard cycleColors.count > 1 else { return cycleColors[0] }
        let count = Double(cycleColors.count)
        let raw = (elapsed / colorCyclePeriod).truncatingRemainder(dividingBy: 1)
        let progress = (raw < 0 ? raw + 1 : raw) * count
        let index = Int(progress) % cycleColors.count
        let nextIndex = (index + 1) % cycleColors.count
        let fraction = progress - Double(index)
        return cycleColors[index].mix(with: cycleColors[nextIndex], by: fraction)
    }

    @ViewBuilder
    private func cometStroke(rotationDegrees: Double, headColor: Color) -> some View {
        let stops: [Gradient.Stop] = [
            .init(color: .clear, location: 0.00),
            .init(color: .clear, location: 0.50),
            .init(color: headColor.opacity(0.25), location: 0.68),
            .init(color: headColor.opacity(0.70), location: 0.82),
            .init(color: headColor, location: 0.94),
            .init(color: Color.white, location: 1.00)
        ]
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: stops),
                        center: .center,
                        angle: .degrees(rotationDegrees)
                    ),
                    lineWidth: 2.0
                )
                .blur(radius: 2.5)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: stops),
                        center: .center,
                        angle: .degrees(rotationDegrees)
                    ),
                    lineWidth: 0.8
                )
                .blur(radius: 0.4)
        }
        .blendMode(.plusLighter)
    }
}
