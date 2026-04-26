// Klausemeister/Views/MeisterScheduleStripView.swift
import SwiftUI

/// Prominent horizontal strip of saved-schedule cards rendered above the
/// kanban in the Meister tab. Distinct from `RepoScheduleStripView` (which
/// stays as a tiny one-line pill in the sidebar where vertical real estate
/// is scarce); here the user has space, so each card carries the schedule
/// name, status pip row, and a thicker progress bar so the schedule's state
/// is readable without opening the gantt.
struct MeisterScheduleStripView: View {
    let schedules: [Schedule]
    let onScheduleTapped: (String) -> Void

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        if schedules.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Schedules")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.6)
                }
                .padding(.horizontal, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(schedules) { schedule in
                            MeisterScheduleCard(
                                schedule: schedule,
                                onTapped: { onScheduleTapped(schedule.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

/// One schedule card in the Meister-tab strip. Bigger than the sidebar pill:
/// shows the name, a 4-pip status row mirroring the gantt header legend, and
/// a thin filled progress bar. Tapping opens the gantt overlay.
private struct MeisterScheduleCard: View {
    let schedule: Schedule
    let onTapped: () -> Void

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        let total = schedule.items.count
        let done = schedule.doneCount
        let fraction = total > 0 ? Double(done) / Double(total) : 0

        Button(action: onTapped) {
            VStack(alignment: .leading, spacing: 6) {
                Text(schedule.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                StatusPipRow(items: schedule.items)
                ProgressBar(fraction: fraction, tint: themeColors.accentColor)
                    .frame(height: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minWidth: 200, maxWidth: 320, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(themeColors.accentColor.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(themeColors.accentColor.opacity(0.30), lineWidth: 0.75)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(schedule.name) · \(done)/\(total) done")
    }
}

/// Compact row of the four status pips with their counts. Mirrors the gantt
/// header legend so the user learns one symbol vocabulary that works
/// everywhere a schedule is shown.
private struct StatusPipRow: View {
    let items: [ScheduleItem]

    private let order: [ScheduleItemStatus] = [.planned, .queued, .inProgress, .done]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(order, id: \.self) { status in
                let count = items.count(where: { $0.status == status })
                let isEmpty = count == 0
                HStack(spacing: 3) {
                    StatusPip(status: status, tint: isEmpty ? .secondary : status.tint)
                        .opacity(isEmpty ? 0.35 : 1.0)
                    Text("\(count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(isEmpty ? .secondary : .primary)
                }
            }
        }
    }
}

private struct ProgressBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.18))
                Capsule()
                    .fill(tint.opacity(0.85))
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
    }
}
