import SwiftData
import SwiftUI

// MARK: - Checkbox

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.27, y: rect.minY + rect.height * 0.53))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.69))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.74, y: rect.minY + rect.height * 0.34))
        return path
    }
}

/// Circle that fills with the emerald→cyan gradient and draws its checkmark when turned on.
struct AnimatedCheckbox: View {
    let isOn: Bool
    var tint: Color = Theme.indigo
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isOn ? Theme.emerald : tint.opacity(0.7), lineWidth: 2)
            Circle()
                .fill(Theme.successGradient)
                .scaleEffect(isOn ? 1 : 0.01)
                .opacity(isOn ? 1 : 0)
            CheckmarkShape()
                .trim(from: 0, to: isOn ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.emerald.opacity(isOn ? 0.6 : 0), radius: 7)
        .scaleEffect(isOn ? 1.0 : 0.94)
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: isOn)
        .contentShape(Rectangle().inset(by: -8))
    }
}

// MARK: - Effort badge

struct EffortBadge: View {
    let effort: EffortLevel
    var showsPoints = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: effort.iconName)
            Text(showsPoints ? "\(effort.label) · \(effort.points) XP" : effort.label)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(effort.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(effort.tint.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(effort.tint.opacity(0.3), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(effort.label), \(effort.points) XP")
    }
}

// MARK: - Row

struct TaskRowView: View {
    let task: TaskItem
    /// Show the scheduled date (used in lists that mix several days).
    var showsDate = false
    let onToggle: () -> Void
    let onOpen: () -> Void

    private var isOverdue: Bool { task.isOverdue() }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                AnimatedCheckbox(isOn: task.isCompleted, tint: task.effort.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Mark complete")
            .sensoryFeedback(trigger: task.isCompleted) { _, isCompleted in
                isCompleted ? .success : .impact(weight: .light)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.body.weight(.medium))
                    .strikethrough(task.isCompleted, color: Theme.textTertiary)
                    .foregroundStyle(task.isCompleted ? Theme.textTertiary : Theme.textPrimary)

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    EffortBadge(effort: task.effort)
                    dateLabel
                }
                .opacity(task.isCompleted ? 0.55 : 1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to edit")
    }

    @ViewBuilder
    private var dateLabel: some View {
        if isOverdue, let date = task.scheduledDate {
            Label("Overdue · \(date.formatted(.dateTime.month(.abbreviated).day()))", systemImage: "exclamationmark.circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.rose)
        } else if showsDate {
            if let date = task.scheduledDate {
                Label(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()), systemImage: "calendar")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Label("Someday", systemImage: "tray")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

#Preview {
    List {
        ForEach(PreviewSampleData.makeSampleTasks().suffix(16).prefix(5)) { task in
            TaskRowView(task: task, showsDate: true, onToggle: {}, onOpen: {})
                .glassRow()
        }
    }
    .themedScreen()
    .previewEnvironment()
}

// MARK: - Context menu

/// Right-click (macOS) / long-press (iOS) actions for a task row.
struct TaskContextMenuItems: View {
    let task: TaskItem
    @Environment(TaskStore.self) private var store

    var body: some View {
        Button {
            withAnimation(Theme.spring) { store.toggleCompletion(task) }
        } label: {
            Label(task.isCompleted ? "Mark Incomplete" : "Complete",
                  systemImage: task.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
        }

        Divider()

        Button {
            withAnimation(Theme.spring) { store.reschedule(task, byDaysFromToday: 1) }
        } label: {
            Label("Move to Tomorrow", systemImage: "sunrise")
        }

        Button {
            withAnimation(Theme.spring) { store.reschedule(task, byDaysFromToday: 7) }
        } label: {
            Label("Move to Next Week", systemImage: "calendar.badge.plus")
        }

        if task.scheduledDate != nil {
            Button {
                withAnimation(Theme.spring) { store.reschedule(task, to: nil) }
            } label: {
                Label("Move to Someday", systemImage: "tray")
            }
        }

        Divider()

        Button(role: .destructive) {
            withAnimation(Theme.spring) { store.delete(task) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
