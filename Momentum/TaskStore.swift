import Foundation
import Observation
import OSLog
import SwiftData

/// Single entry point for task and reward mutations. Every task change saves, re-evaluates
/// awards, and re-syncs the reminder schedule so views never have to remember to.
@MainActor
@Observable
final class TaskStore {
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let awardEngine: AwardEngine
    @ObservationIgnored private let notificationManager: NotificationManager
    @ObservationIgnored private let logger = Logger(subsystem: "com.example.momentum", category: "TaskStore")

    init(context: ModelContext, awardEngine: AwardEngine, notificationManager: NotificationManager) {
        self.context = context
        self.awardEngine = awardEngine
        self.notificationManager = notificationManager
    }

    // MARK: Queries

    func allTasks() -> [TaskItem] {
        fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    private func allRedemptions() -> [RewardRedemption] {
        fetch(FetchDescriptor<RewardRedemption>())
    }

    private func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) -> [Model] {
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: Task mutations

    func addTask(title: String, notes: String, scheduledDate: Date?, effort: EffortLevel) {
        let task = TaskItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            scheduledDate: normalized(scheduledDate),
            effort: effort
        )
        context.insert(task)
        commit()
    }

    func update(_ task: TaskItem, title: String, notes: String, scheduledDate: Date?, effort: EffortLevel) {
        task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.scheduledDate = normalized(scheduledDate)
        task.effort = effort
        commit()
    }

    func toggleCompletion(_ task: TaskItem) {
        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? .now : nil
        commit()
    }

    func reschedule(_ task: TaskItem, to date: Date?) {
        task.scheduledDate = normalized(date)
        commit()
    }

    func reschedule(_ task: TaskItem, byDaysFromToday days: Int) {
        reschedule(task, to: Calendar.current.dayOffset(days))
    }

    func delete(_ task: TaskItem) {
        context.delete(task)
        commit()
    }

    // MARK: Rewards

    /// Spends Leisure Points on a shop reward. Returns the new pass, or `nil` if unaffordable.
    @discardableResult
    func redeem(_ reward: RewardCheckpoint) -> RewardRedemption? {
        guard reward.kind == .shopReward else { return nil }
        let balance = RewardMath.balance(tasks: allTasks(), redemptions: allRedemptions())
        guard balance >= reward.cost else { return nil }
        let redemption = RewardRedemption(reward: reward, pointsSpent: reward.cost)
        context.insert(redemption)
        save()
        return redemption
    }

    /// Claims today's daily checkpoint for free once today's XP reaches its threshold.
    @discardableResult
    func claimDailyCheckpoint(_ checkpoint: RewardCheckpoint) -> RewardRedemption? {
        guard checkpoint.kind == .dailyCheckpoint else { return nil }
        let todayXP = PlannerStats.xpEarned(on: .now, tasks: allTasks())
        guard todayXP >= checkpoint.cost,
              !RewardMath.isClaimed(checkpoint, redemptions: allRedemptions()) else { return nil }
        let redemption = RewardRedemption(reward: checkpoint, pointsSpent: 0)
        context.insert(redemption)
        save()
        return redemption
    }

    func addCustomReward(title: String, details: String, iconName: String, cost: Int) {
        let existing = fetch(FetchDescriptor<RewardCheckpoint>())
        let reward = RewardCheckpoint(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            iconName: iconName,
            cost: max(1, cost),
            kind: .shopReward,
            isCustom: true,
            sortOrder: (existing.map(\.sortOrder).max() ?? 0) + 1
        )
        context.insert(reward)
        save()
    }

    /// Deletes a user-created reward. Passes already claimed for it are kept.
    func deleteReward(_ reward: RewardCheckpoint) {
        guard reward.isCustom else { return }
        context.delete(reward)
        save()
    }

    // MARK: Lifecycle

    /// Called when the app becomes active: picks up day rollovers and permission changes.
    func refresh() {
        RewardCatalog.seedIfNeeded(in: context)
        awardEngine.seedAwardsIfNeeded(in: context)
        awardEngine.evaluate(in: context)
        syncNotifications()
    }

    func syncNotifications() {
        notificationManager.syncNotifications(tasks: allTasks())
    }

    /// Wipes tasks, awards and passes, then re-seeds the demo data set. Custom rewards are kept.
    func resetDemoData() {
        awardEngine.clearPendingUnlocks()
        for task in allTasks() {
            context.delete(task)
        }
        for award in fetch(FetchDescriptor<Award>()) {
            context.delete(award)
        }
        for redemption in allRedemptions() {
            context.delete(redemption)
        }
        save()

        PreviewSampleData.insertSampleTasks(into: context)
        RewardCatalog.seedIfNeeded(in: context)
        PreviewSampleData.insertSampleRedemptions(into: context)
        awardEngine.seedAwardsIfNeeded(in: context)
        commit(announceAwards: false)
    }

    // MARK: Private

    private func commit(announceAwards: Bool = true) {
        save()
        awardEngine.evaluate(in: context, announce: announceAwards)
        syncNotifications()
    }

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("Saving failed: \(error.localizedDescription)")
        }
    }

    private func normalized(_ date: Date?) -> Date? {
        date.map { Calendar.current.startOfDay(for: $0) }
    }
}
