import AppIntents
import SwiftUI
import WidgetKit

/// Command Center: date, completion ratio, streak and points; up to six open tasks with
/// check-off buttons and XP pills; and a quick-add bar (deep link + one-tap presets).
struct LargeWidgetView: View {
    let snapshot: PlannerSnapshot
    var date: Date = .now

    private static let maxRows = 6

    /// Six rows fit; with more than six, show five and an overflow line.
    private var visibleTasks: [WidgetTask] {
        let tasks = snapshot.openTasks
        return tasks.count > Self.maxRows ? Array(tasks.prefix(Self.maxRows - 1)) : tasks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            WidgetProgressBar(progress: snapshot.progress)
            taskList
            Spacer(minLength: 0)
            quickAddBar
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(date.formatted(.dateTime.weekday(.wide)))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.indigo)
                    .textCase(.uppercase)
                Text(date.formatted(.dateTime.month(.wide).day()))
                    .font(Theme.rounded(.title3, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(snapshot.todayCompleted) / \(snapshot.todayTotal) Done")
                    .font(Theme.rounded(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                WidgetStatPill(icon: "flame.fill", text: "\(snapshot.streak) day\(snapshot.streak == 1 ? "" : "s")")
                WidgetStatPill(icon: "leaf.fill", text: "\(snapshot.points) pts", colors: Theme.successColors)
            }
        }
    }

    // MARK: Tasks

    @ViewBuilder
    private var taskList: some View {
        if visibleTasks.isEmpty {
            Spacer(minLength: 0)
            WidgetAllClearView()
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(visibleTasks) { task in
                    WidgetTaskRow(task: task)
                        .padding(.leading, -4)
                }
                if snapshot.remaining > visibleTasks.count {
                    Text("+\(snapshot.remaining - visibleTasks.count) more in Momentum")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, 28)
                }
            }
        }
    }

    // MARK: Quick add

    private var quickAddBar: some View {
        HStack(spacing: 6) {
            Link(destination: DeepLink.quickAddURL) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("New Task")
                }
                .font(Theme.rounded(.caption, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Theme.primaryGradient, in: Capsule())
                .shadow(color: Theme.violet.opacity(0.45), radius: 6, y: 2)
            }

            // Like New Task, but with the effort pre-selected (iOS: Add Task sheet; macOS:
            // quick-add bar), so the task gets a real title instead of a generic preset one.
            ForEach(QuickAddPreset.allCases) { preset in
                Link(destination: DeepLink.quickAddURL(effort: preset.effort)) {
                    presetChip(preset)
                }
                .accessibilityLabel("New \(preset.chipTitle) task, \(preset.effort.points) XP")
            }
        }
    }

    private func presetChip(_ preset: QuickAddPreset) -> some View {
        VStack(spacing: 0) {
            Text("+ \(preset.chipTitle)")
                .font(Theme.rounded(.caption2, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("\(preset.effort.points) XP")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(preset.effort.tint)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(preset.effort.tint.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(preset.effort.tint.opacity(0.4), lineWidth: 0.75))
    }
}

#Preview("Command Center", as: .systemLarge) {
    CommandCenterWidget()
} timeline: {
    PlannerEntry(date: .now, snapshot: .preview)
    PlannerEntry(date: .now, snapshot: .fewTasks)
    PlannerEntry(date: .now, snapshot: .allClear)
}
