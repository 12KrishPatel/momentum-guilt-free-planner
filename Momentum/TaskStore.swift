import Foundation
import Observation
import OSLog
import SwiftData
import WidgetKit

/// Single entry point for task and reward mutations. Every task change saves, re-evaluates
/// awards, and re-syncs the reminder schedule so views never have to remember to.
@MainActor
@Observable
final class TaskStore {
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let awardEngine: AwardEngine
    @ObservationIgnored private let notificationManager: NotificationManager
    /// App only: drives the combo pill and "+XP" burst. The widget passes `nil`.
    @ObservationIgnored private let comboEngine: ComboEngine?
    @ObservationIgnored private let logger = Logger(subsystem: "com.krishpatel.momentum", category: "TaskStore")

    init(
        context: ModelContext,
        awardEngine: AwardEngine,
        notificationManager: NotificationManager,
        comboEngine: ComboEngine? = nil
    ) {
        self.context = context
        self.awardEngine = awardEngine
        self.notificationManager = notificationManager
        self.comboEngine = comboEngine
    }

    // MARK: Queries

    func allTasks() -> [TaskItem] {
        fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    func task(withID id: UUID) -> TaskItem? {
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    private func allRedemptions() -> [RewardRedemption] {
        fetch(FetchDescriptor<RewardRedemption>())
    }

    func allEvents() -> [MomentumEvent] {
        fetch(FetchDescriptor<MomentumEvent>())
    }

    func allPasses() -> [ActivePass] {
        fetch(FetchDescriptor<ActivePass>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    func pass(forRedemption redemptionID: UUID) -> ActivePass? {
        allPasses().first { $0.redemptionID == redemptionID }
    }

    /// Spendable Leisure Points right now.
    func currentBalance() -> Int {
        RewardMath.balance(tasks: allTasks(), redemptions: allRedemptions(), events: allEvents())
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

    /// Checks a task off (or re-opens it). A completion locks in the combo multiplier in effect
    /// (Momentum Combo, Overdrive or Early Finisher), so its XP and Leisure Points are multiplied.
    /// Returns what the completion earned, or `nil` when re-opening.
    @discardableResult
    func toggleCompletion(_ task: TaskItem) -> CompletionReward? {
        task.isCompleted.toggle()
        var reward: CompletionReward?
        if task.isCompleted {
            let now = Date.now
            task.completedAt = now
            let tasks = allTasks()
            var events = allEvents()
            if !ComboMath.hasEarlyFinisher(events: events, on: now),
               ComboMath.qualifiesForEarlyFinisher(tasks: tasks, now: now) {
                let marker = MomentumEvent(kind: .earlyFinisher, xp: 0, occurredAt: now)
                context.insert(marker)
                events.append(marker)
            }
            let bonus = ComboMath.multiplier(
                forCompletionAt: now,
                completions: ComboMath.completionDates(tasks),
                earlyFinisherActive: ComboMath.hasEarlyFinisher(events: events, on: now)
            )
            task.storedXPMultiplier = bonus.multiplier > 1 ? bonus.multiplier : nil
            reward = CompletionReward(
                taskID: task.id,
                baseXP: task.effort.points,
                xp: task.earnedXP,
                multiplier: bonus.multiplier,
                kind: bonus.kind
            )
        } else {
            task.completedAt = nil
            task.storedXPMultiplier = nil
        }
        commit()
        if let reward { comboEngine?.register(reward) }
        return reward
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

    /// Clears a task from every list without deleting it (Sunday Reset's swipe left).
    func archive(_ task: TaskItem) {
        task.archivedAt = .now
        commit()
    }

    func unarchive(_ task: TaskItem) {
        task.archivedAt = nil
        commit()
    }

    /// Morning Kickoff: saves the confirmed order (first = top priority).
    func setPriorityOrder(_ ordered: [TaskItem]) {
        for (rank, task) in ordered.enumerated() where task.priorityRank != rank {
            task.priorityRank = rank
        }
        commit()
    }

    // MARK: Rituals

    struct RitualOutcome: Sendable {
        let xpAwarded: Int
        /// The ritual was already rewarded today, so this run earned no XP.
        let wasAlreadyRewarded: Bool
    }

    static let ritualXP = 25

    /// Records a finished Sunday Reset or Morning Kickoff: +25 XP (once per ritual per day),
    /// then re-evaluates badges (Sunday Planner).
    @discardableResult
    func completeRitual(_ kind: MomentumEventKind, itemCount: Int) -> RitualOutcome {
        let now = Date.now
        let alreadyRewarded = allEvents().contains {
            $0.kind == kind && Calendar.current.isDate($0.occurredAt, inSameDayAs: now)
        }
        let xp = alreadyRewarded ? 0 : Self.ritualXP
        context.insert(MomentumEvent(kind: kind, xp: xp, occurredAt: now, itemCount: itemCount))
        commit()
        return RitualOutcome(xpAwarded: xp, wasAlreadyRewarded: alreadyRewarded)
    }

    func hasCompletedRitual(_ kind: MomentumEventKind, on day: Date = .now) -> Bool {
        allEvents().contains { $0.kind == kind && Calendar.current.isDate($0.occurredAt, inSameDayAs: day) }
    }

    // MARK: Rewards

    /// Spends Leisure Points on a shop reward. Returns the new pass, or `nil` if unaffordable.
    @discardableResult
    func redeem(_ reward: RewardCheckpoint) -> RewardRedemption? {
        guard reward.kind == .shopReward else { return nil }
        guard currentBalance() >= reward.cost else { return nil }
        let redemption = RewardRedemption(reward: reward, pointsSpent: reward.cost)
        context.insert(redemption)
        context.insert(makePass(for: redemption, source: .shop, rarity: rarity(forCost: reward.cost)))
        save()
        return redemption
    }

    /// Claims today's daily checkpoint for free once today's XP reaches its threshold.
    @discardableResult
    func claimDailyCheckpoint(_ checkpoint: RewardCheckpoint) -> RewardRedemption? {
        guard checkpoint.kind == .dailyCheckpoint else { return nil }
        let todayXP = PlannerStats.xpEarned(on: .now, tasks: allTasks(), events: allEvents())
        guard todayXP >= checkpoint.cost,
              !RewardMath.isClaimed(checkpoint, redemptions: allRedemptions()) else { return nil }
        let redemption = RewardRedemption(reward: checkpoint, pointsSpent: 0)
        context.insert(redemption)
        context.insert(makePass(for: redemption, source: .dailyCheckpoint, rarity: .rare))
        save()
        return redemption
    }

    struct CrateResult {
        let crate: MysteryCrate
        let drop: LootDrop
        let redemption: RewardRedemption
        let pass: ActivePass
    }

    /// Buys and opens a Mystery Loot Box: deducts its price, rolls the loot table and saves the
    /// won pass to the wallet. Returns `nil` if the balance is too low.
    func openCrate(_ crate: MysteryCrate) -> CrateResult? {
        guard currentBalance() >= crate.cost else { return nil }
        let drop = crate.roll()
        let redemption = RewardRedemption(
            rewardID: nil,
            title: drop.title,
            details: "\(drop.details) Won from the \(crate.title).",
            iconName: drop.iconName,
            pointsSpent: crate.cost,
            kind: .mysteryCrate,
            durationMinutes: drop.breakMinutes
        )
        let pass = makePass(for: redemption, source: .mysteryCrate, rarity: drop.rarity)
        context.insert(redemption)
        context.insert(pass)
        save()
        return CrateResult(crate: crate, drop: drop, redemption: redemption, pass: pass)
    }

    // MARK: Pass timers

    /// Starts a timed pass's break (minimum 30 minutes). Any other running break ends first.
    /// On iPhone this launches the Live Activity / Dynamic Island countdown.
    func startBreak(_ pass: ActivePass) {
        guard let minutes = pass.breakMinutes, pass.status() == .saved else { return }
        let now = Date.now
        for other in allPasses() where other.id != pass.id {
            if case .running = other.status(at: now) { other.finishedAt = now }
        }
        pass.startedAt = now
        pass.endsAt = now.addingTimeInterval(TimeInterval(minutes * 60))
        save()
        #if !WIDGET_EXTENSION
        LiveActivityManager.shared.startBreakActivity(
            passID: pass.id,
            title: pass.title,
            iconName: pass.iconName,
            durationMinutes: minutes
        )
        #endif
    }

    /// "End Break Early", or marks an untimed pass as used.
    func finishPass(_ pass: ActivePass) {
        guard pass.finishedAt == nil else { return }
        pass.finishedAt = .now
        save()
        #if !WIDGET_EXTENSION
        if pass.isTimed { LiveActivityManager.shared.endBreakActivity() }
        #endif
    }

    func finishPass(id: UUID) {
        guard let pass = allPasses().first(where: { $0.id == id }) else { return }
        finishPass(pass)
    }

    private func makePass(for redemption: RewardRedemption, source: PassSource, rarity: PassRarity) -> ActivePass {
        ActivePass(
            redemptionID: redemption.id,
            title: redemption.title,
            details: redemption.details,
            iconName: redemption.iconName,
            durationMinutes: redemption.durationMinutes,
            source: source,
            rarity: rarity,
            createdAt: redemption.redeemedAt
        )
    }

    private func rarity(forCost cost: Int) -> PassRarity {
        switch cost {
        case 300...: .legendary
        case 150..<300: .epic
        case 75..<150: .rare
        default: .common
        }
    }

    /// Adds a shop reward. `durationMinutes` (if any) is raised to the 30-minute minimum.
    func addCustomReward(title: String, details: String, iconName: String, cost: Int, durationMinutes: Int? = nil) {
        let existing = fetch(FetchDescriptor<RewardCheckpoint>())
        let reward = RewardCheckpoint(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            iconName: iconName,
            cost: max(1, cost),
            kind: .shopReward,
            isCustom: true,
            sortOrder: (existing.map(\.sortOrder).max() ?? 0) + 1,
            durationMinutes: BreakPolicy.clamped(durationMinutes)
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
        refreshCombo()
        #if !WIDGET_EXTENSION
        LiveActivityManager.shared.sync(with: allPasses())
        #endif
    }

    func refreshCombo() {
        comboEngine?.refresh(tasks: allTasks(), events: allEvents())
    }

    /// Called after data changes that didn't go through this store — e.g. edits merged in from
    /// another device via iCloud — so badges and reminders reflect the latest tasks.
    func handleExternalChanges() {
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func syncNotifications() {
        notificationManager.syncNotifications(tasks: allTasks())
    }

    /// Erase All Data: deletes every task, badge, pass, ritual record and custom reward, then
    /// restores the built-in rewards and a fresh (all-locked) badge catalog. With iCloud sync
    /// on, the deletions reach the user's other devices too. Reminder settings are kept.
    func eraseAllData() {
        awardEngine.clearPendingUnlocks()
        #if !WIDGET_EXTENSION
        LiveActivityManager.shared.endBreakActivity()
        #endif
        for task in allTasks() { context.delete(task) }
        for award in fetch(FetchDescriptor<Award>()) { context.delete(award) }
        for redemption in allRedemptions() { context.delete(redemption) }
        for pass in allPasses() { context.delete(pass) }
        for event in allEvents() { context.delete(event) }
        for reward in fetch(FetchDescriptor<RewardCheckpoint>()) where reward.isCustom {
            context.delete(reward)
        }
        save()

        RewardCatalog.seedIfNeeded(in: context)
        awardEngine.seedAwardsIfNeeded(in: context)
        commit(announceAwards: false)
    }

    // MARK: Private

    private func commit(announceAwards: Bool = true) {
        save()
        awardEngine.evaluate(in: context, announce: announceAwards)
        syncNotifications()
        refreshCombo()
    }

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
            didSave()
        } catch {
            logger.error("Saving failed: \(error.localizedDescription)")
        }
    }

    /// Every saved change (tasks, points, passes) can alter what the widgets show.
    private func didSave() {
        WidgetCenter.shared.reloadAllTimelines()
        #if WIDGET_EXTENSION
        // Let the app, if it's running, refresh its views from the shared store.
        SharedModelContainer.postExternalChange()
        #endif
    }

    private func normalized(_ date: Date?) -> Date? {
        date.map { Calendar.current.startOfDay(for: $0) }
    }
}
