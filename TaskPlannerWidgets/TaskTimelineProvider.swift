import Foundation
import SwiftData
import WidgetKit

// MARK: - Snapshot

/// A task as the widget shows it: plain values, safe to hand across threads.
struct WidgetTask: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let effort: EffortLevel
    let isOverdue: Bool
}

/// The next Leisure checkpoint (daily) or shop reward the user is working toward.
struct WidgetCheckpoint: Hashable, Sendable {
    let title: String
    let iconName: String
    let current: Int
    let target: Int
    /// Reached today and waiting to be claimed in the app.
    let isReady: Bool

    var progress: Double {
        target > 0 ? min(1, Double(current) / Double(target)) : 1
    }
}

/// Everything the three widget sizes need, read once per timeline reload.
struct PlannerSnapshot: Sendable {
    /// `false` when the shared App Group store isn't reachable yet.
    var isConnected = true
    var todayCompleted = 0
    var todayTotal = 0
    /// Open tasks for today plus overdue ones, most urgent first.
    var openTasks: [WidgetTask] = []
    var streak = 0
    var xpToday = 0
    var points = 0
    var checkpoint: WidgetCheckpoint?

    var remaining: Int { openTasks.count }

    var progress: Double {
        todayTotal > 0 ? Double(todayCompleted) / Double(todayTotal) : 0
    }

    static let disconnected = PlannerSnapshot(isConnected: false)

    /// Reads the shared store on the calling thread with its own context.
    static func load(now: Date = .now) -> PlannerSnapshot {
        guard let container = SharedModelContainer.widgetContainer() else { return .disconnected }
        let context = ModelContext(container)
        return make(
            tasks: (try? context.fetch(FetchDescriptor<TaskItem>())) ?? [],
            checkpoints: (try? context.fetch(FetchDescriptor<RewardCheckpoint>())) ?? [],
            redemptions: (try? context.fetch(FetchDescriptor<RewardRedemption>())) ?? [],
            events: (try? context.fetch(FetchDescriptor<MomentumEvent>())) ?? [],
            now: now
        )
    }

    static func make(
        tasks: [TaskItem],
        checkpoints: [RewardCheckpoint],
        redemptions: [RewardRedemption],
        events: [MomentumEvent] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> PlannerSnapshot {
        let today = calendar.startOfDay(for: now)
        // Tasks cleared in a Sunday Reset stay out of the widget too.
        let tasks = tasks.filter { !$0.isArchived }
        let scheduledToday = tasks.filter { task in
            task.scheduledDate.map { calendar.isDate($0, inSameDayAs: today) } ?? false
        }

        // Overdue first, then the biggest XP, then oldest — the "do this next" order.
        let open = tasks
            .filter { task in
                guard !task.isCompleted, let date = task.scheduledDate else { return false }
                return calendar.startOfDay(for: date) <= today
            }
            .sorted { lhs, rhs in
                let lhsOverdue = lhs.isOverdue(asOf: now, calendar: calendar)
                let rhsOverdue = rhs.isOverdue(asOf: now, calendar: calendar)
                if lhsOverdue != rhsOverdue { return lhsOverdue }
                if lhs.effort.points != rhs.effort.points { return lhs.effort.points > rhs.effort.points }
                return lhs.createdAt < rhs.createdAt
            }
            .map { task in
                WidgetTask(
                    id: task.id,
                    title: task.title,
                    effort: task.effort,
                    isOverdue: task.isOverdue(asOf: now, calendar: calendar)
                )
            }

        let checkpoint: WidgetCheckpoint? = switch RewardMath.nextCheckpoint(
            checkpoints: checkpoints, tasks: tasks, redemptions: redemptions, events: events, now: now
        ) {
        case .claimable(let reward):
            WidgetCheckpoint(title: reward.title, iconName: reward.iconName, current: reward.cost, target: reward.cost, isReady: true)
        case .daily(let reward, let progress):
            WidgetCheckpoint(title: reward.title, iconName: reward.iconName, current: progress, target: reward.cost, isReady: false)
        case .shop(let reward, let balance):
            WidgetCheckpoint(title: reward.title, iconName: reward.iconName, current: balance, target: reward.cost, isReady: false)
        case .allUnlocked:
            nil
        }

        return PlannerSnapshot(
            todayCompleted: scheduledToday.count(where: \.isCompleted),
            todayTotal: scheduledToday.count,
            openTasks: open,
            streak: PlannerStats.currentStreak(tasks, now: now, calendar: calendar),
            xpToday: PlannerStats.xpEarned(on: now, tasks: tasks, events: events, calendar: calendar),
            points: RewardMath.balance(tasks: tasks, redemptions: redemptions, events: events),
            checkpoint: checkpoint
        )
    }
}

// MARK: - Sample snapshots (gallery placeholder & previews)

extension PlannerSnapshot {
    static let preview = PlannerSnapshot(
        todayCompleted: 3,
        todayTotal: 7,
        openTasks: [
            WidgetTask(id: UUID(), title: "Reply to landlord email", effort: .quick, isOverdue: true),
            WidgetTask(id: UUID(), title: "Draft Q4 roadmap", effort: .deepWork, isOverdue: false),
            WidgetTask(id: UUID(), title: "Review design mockups", effort: .standard, isOverdue: false),
            WidgetTask(id: UUID(), title: "Prep slides for Thursday sync", effort: .standard, isOverdue: false),
            WidgetTask(id: UUID(), title: "Book dentist appointment", effort: .quick, isOverdue: false),
            WidgetTask(id: UUID(), title: "Water the plants", effort: .quick, isOverdue: false),
            WidgetTask(id: UUID(), title: "Expense last week's receipts", effort: .quick, isOverdue: false),
        ],
        streak: 9,
        xpToday: 85,
        points: 275,
        checkpoint: WidgetCheckpoint(title: "Guilt-Free Snack Break", iconName: "cup.and.saucer.fill", current: 85, target: 100, isReady: false)
    )

    static let fewTasks = PlannerSnapshot(
        todayCompleted: 4,
        todayTotal: 6,
        openTasks: Array(preview.openTasks.prefix(2)),
        streak: 9,
        xpToday: 110,
        points: 300,
        checkpoint: WidgetCheckpoint(title: "Episode of Your Show", iconName: "tv.fill", current: 110, target: 150, isReady: false)
    )

    static let allClear = PlannerSnapshot(
        todayCompleted: 6,
        todayTotal: 6,
        openTasks: [],
        streak: 10,
        xpToday: 160,
        points: 350,
        checkpoint: WidgetCheckpoint(title: "Guilt-Free Gaming Hour", iconName: "gamecontroller.fill", current: 150, target: 150, isReady: true)
    )
}

// MARK: - Timeline

struct PlannerEntry: TimelineEntry {
    let date: Date
    let snapshot: PlannerSnapshot
}

/// Reads the shared store; the app and the widget intents reload timelines after every change,
/// and a midnight refresh rolls the widget over to the new day.
struct TaskTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlannerEntry {
        PlannerEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlannerEntry) -> Void) {
        let snapshot = PlannerSnapshot.load()
        // The widget gallery shows sample data until the planner has something to show.
        let useSample = context.isPreview && (!snapshot.isConnected || snapshot.todayTotal + snapshot.remaining == 0)
        completion(PlannerEntry(date: .now, snapshot: useSample ? .preview : snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlannerEntry>) -> Void) {
        let now = Date.now
        let entry = PlannerEntry(date: now, snapshot: .load(now: now))
        let nextMidnight = Calendar.current.dayOffset(1, from: now)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}
