import SwiftUI
import WidgetKit

/// Focus Glance: today's progress ring, tasks left, streak, and the next task to check off.
struct SmallWidgetView: View {
    let snapshot: PlannerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                WidgetProgressRing(progress: snapshot.progress, size: 54, lineWidth: 6) {
                    VStack(spacing: -2) {
                        Text("\(snapshot.todayCompleted)")
                            .font(Theme.rounded(size: 18, weight: .heavy))
                            .foregroundStyle(Theme.textPrimary)
                        Text("of \(snapshot.todayTotal)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 5) {
                    WidgetStatPill(icon: "flame.fill", text: "\(snapshot.streak)")
                    Text(snapshot.remaining == 0 ? "Done" : "\(snapshot.remaining) left")
                        .font(Theme.rounded(.caption, weight: .bold))
                        .foregroundStyle(snapshot.remaining == 0 ? Theme.emerald : Theme.textSecondary)
                }
            }

            Spacer(minLength: 6)

            if let task = snapshot.openTasks.first {
                WidgetSectionLabel(text: task.isOverdue ? "Overdue" : "Up next")
                    .padding(.bottom, 3)
                HStack(alignment: .top, spacing: 4) {
                    WidgetCheckButton(task: task, size: 20)
                        .padding(.leading, -4)
                        .padding(.top, -4)
                    Text(task.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .invalidatableContent()
                }
            } else {
                WidgetAllClearView(compact: true)
            }
        }
    }
}

#Preview("Focus Glance", as: .systemSmall) {
    FocusGlanceWidget()
} timeline: {
    PlannerEntry(date: .now, snapshot: .preview)
    PlannerEntry(date: .now, snapshot: .allClear)
    PlannerEntry(date: .now, snapshot: .disconnected)
}
