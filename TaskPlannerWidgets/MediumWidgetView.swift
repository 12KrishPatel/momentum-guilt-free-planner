import SwiftUI
import WidgetKit

/// Today's Queue: progress, XP and the next Leisure checkpoint on the left; the next three
/// open tasks with interactive checkboxes on the right.
struct MediumWidgetView: View {
    let snapshot: PlannerSnapshot

    private var visibleTasks: [WidgetTask] { Array(snapshot.openTasks.prefix(3)) }

    var body: some View {
        HStack(spacing: 14) {
            summaryColumn
                .frame(width: 112)

            Rectangle()
                .fill(Theme.separator)
                .frame(width: 1)

            queueColumn
        }
    }

    private var summaryColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                WidgetProgressRing(progress: snapshot.progress, size: 46, lineWidth: 5) {
                    Text("\(Int((snapshot.progress * 100).rounded()))%")
                        .font(Theme.rounded(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("+\(snapshot.xpToday)")
                        .font(Theme.rounded(.headline, weight: .heavy))
                        .foregroundStyle(Theme.primaryGradient)
                    Text("XP today")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer(minLength: 0)

            if let checkpoint = snapshot.checkpoint {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: checkpoint.iconName)
                            .foregroundStyle(Theme.successGradient)
                        Text(checkpoint.isReady ? "Ready to claim" : "\(checkpoint.current)/\(checkpoint.target) pts")
                            .foregroundStyle(checkpoint.isReady ? Theme.emerald : Theme.textSecondary)
                    }
                    .font(Theme.rounded(.caption2, weight: .bold))
                    WidgetProgressBar(progress: checkpoint.progress, colors: Theme.successColors, height: 5)
                    Text(checkpoint.title)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                WidgetStatPill(icon: "leaf.fill", text: "\(snapshot.points) pts", colors: Theme.successColors)
            }
        }
    }

    private var queueColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                WidgetSectionLabel(text: "Today's queue")
                Spacer()
                WidgetStatPill(icon: "flame.fill", text: "\(snapshot.streak)")
            }
            .padding(.bottom, 2)

            if visibleTasks.isEmpty {
                Spacer(minLength: 0)
                WidgetAllClearView(compact: true)
                Spacer(minLength: 0)
            } else {
                ForEach(visibleTasks) { task in
                    WidgetTaskRow(task: task, showsXP: false)
                        .padding(.leading, -4)
                }
                Spacer(minLength: 0)
                if snapshot.remaining > visibleTasks.count {
                    Text("+\(snapshot.remaining - visibleTasks.count) more")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}

#Preview("Today's Queue", as: .systemMedium) {
    TodaysQueueWidget()
} timeline: {
    PlannerEntry(date: .now, snapshot: .preview)
    PlannerEntry(date: .now, snapshot: .fewTasks)
    PlannerEntry(date: .now, snapshot: .allClear)
}
