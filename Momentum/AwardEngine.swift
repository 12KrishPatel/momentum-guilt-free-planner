import Foundation
import Observation
import SwiftData
import SwiftUI

/// Static description of an award: what it is and how it is earned.
struct AwardDefinition: Sendable, Identifiable {
    let id: String
    let title: String
    let details: String
    let category: AwardCategory
    let tier: AwardTier
    let iconName: String
    let target: Int
    var isSecret: Bool = false
    /// Extra coaching shown on the award detail sheet (hidden for locked secrets).
    let tip: String
}

/// Value copy of a freshly unlocked award, used to drive the celebration overlay.
struct AwardUnlock: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let details: String
    let iconName: String
    let category: AwardCategory
    let tier: AwardTier
    let isSecret: Bool

    init(_ definition: AwardDefinition) {
        id = definition.id
        title = definition.title
        details = definition.details
        iconName = definition.iconName
        category = definition.category
        tier = definition.tier
        isSecret = definition.isSecret
    }

    init(_ award: Award) {
        id = award.id
        title = award.title
        details = award.details
        iconName = award.iconName
        category = award.category
        tier = award.tier
        isSecret = award.isSecret
    }
}

@MainActor
@Observable
final class AwardEngine {
    // MARK: Catalog (24 badges)

    nonisolated static let definitions: [AwardDefinition] = [
        // Consistency & Streaks
        AwardDefinition(
            id: "spark", title: "Spark", details: "Complete your first task.",
            category: .consistency, tier: .bronze, iconName: "sparkle", target: 1,
            tip: "Check off anything—every streak starts with a single spark."
        ),
        AwardDefinition(
            id: "hat_trick", title: "Hat Trick", details: "Complete 3 tasks in one day.",
            category: .consistency, tier: .bronze, iconName: "3.circle.fill", target: 3,
            tip: "Line up a few Quick tasks and knock them out back to back."
        ),
        AwardDefinition(
            id: "momentum", title: "Momentum", details: "Build a 3-day completion streak.",
            category: .consistency, tier: .silver, iconName: "wind", target: 3,
            tip: "Finish at least one task every day for three days running."
        ),
        AwardDefinition(
            id: "week_warrior", title: "Week Warrior", details: "Build a 7-day completion streak.",
            category: .consistency, tier: .silver, iconName: "flame.fill", target: 7,
            tip: "Schedule one small task for every day this week so the chain never breaks."
        ),
        AwardDefinition(
            id: "fortnight_focus", title: "Fortnight Focus", details: "Build a 14-day completion streak.",
            category: .consistency, tier: .gold, iconName: "calendar.badge.checkmark", target: 14,
            tip: "Two straight weeks. Keep a Quick task in reserve for your busiest days."
        ),
        AwardDefinition(
            id: "unbreakable", title: "Unbreakable", details: "Build a 30-day completion streak.",
            category: .consistency, tier: .obsidian, iconName: "shield.lefthalf.filled", target: 30,
            tip: "A full month of showing up. Plan tomorrow's task tonight so you never start cold."
        ),

        // Planning & Foresight
        AwardDefinition(
            id: "architect", title: "Architect", details: "Schedule 5 tasks for future dates in the upcoming week.",
            category: .planning, tier: .bronze, iconName: "building.columns.fill", target: 5,
            tip: "Use This Week to spread tasks across the next 7 days."
        ),
        AwardDefinition(
            id: "mastermind", title: "Mastermind", details: "Schedule tasks across all 7 days of the upcoming week.",
            category: .planning, tier: .silver, iconName: "square.grid.3x3.fill", target: 7,
            tip: "Give each of the next 7 days (starting tomorrow) at least one task."
        ),
        AwardDefinition(
            id: "clean_slate", title: "Clean Slate", details: "Reach 0 overdue tasks after completing at least 10 tasks.",
            category: .planning, tier: .silver, iconName: "eraser.fill", target: 10,
            tip: "Finish or reschedule anything overdue—swipe right on a task to move it."
        ),
        AwardDefinition(
            id: "inbox_zero_hero", title: "Inbox Zero Hero",
            details: "Clear every task scheduled this week (Mon–Sun, at least 7 tasks) before Sunday night.",
            category: .planning, tier: .gold, iconName: "tray.and.arrow.down.fill", target: 7,
            tip: "Plan a realistic week, then finish everything on it before it ends."
        ),

        // Volume & Effort
        AwardDefinition(
            id: "getting_rolling", title: "Getting Rolling", details: "Complete 10 total tasks.",
            category: .volume, tier: .bronze, iconName: "figure.run", target: 10,
            tip: "Small wins add up. Quick tasks count just as much here."
        ),
        AwardDefinition(
            id: "heavy_lifter", title: "Heavy Lifter", details: "Complete 10 Deep Work tasks.",
            category: .volume, tier: .silver, iconName: "dumbbell.fill", target: 10,
            tip: "Mark your most demanding tasks as Deep Work—they're worth 50 XP each."
        ),
        AwardDefinition(
            id: "quarter_century", title: "Quarter Century", details: "Complete 25 total tasks.",
            category: .volume, tier: .silver, iconName: "25.circle.fill", target: 25,
            tip: "Keep showing up. Every completed task counts toward this one."
        ),
        AwardDefinition(
            id: "centurion", title: "Centurion", details: "Complete 100 total tasks.",
            category: .volume, tier: .gold, iconName: "rosette", target: 100,
            tip: "Triple digits. Break big projects into concrete, checkable tasks."
        ),
        AwardDefinition(
            id: "titan_of_focus", title: "Titan of Focus", details: "Earn 2,500 total XP.",
            category: .volume, tier: .obsidian, iconName: "bolt.shield.fill", target: 2500,
            tip: "Deep Work tasks get you there twice as fast as Standard ones."
        ),

        // Time & Behavioral Patterns
        AwardDefinition(
            id: "early_bird", title: "Early Bird", details: "Complete 5 tasks before 9:00 AM.",
            category: .behavioral, tier: .bronze, iconName: "sunrise.fill", target: 5,
            tip: "Pick a Quick task the night before and finish it first thing."
        ),
        AwardDefinition(
            id: "lunchtime_hustle", title: "Lunchtime Hustle", details: "Complete 5 tasks between 11:30 AM and 1:30 PM.",
            category: .behavioral, tier: .silver, iconName: "fork.knife", target: 5,
            tip: "Use the Midday Check-In reminder as your cue to knock one out."
        ),
        AwardDefinition(
            id: "night_owl", title: "Night Owl", details: "Complete 5 tasks after 8:00 PM.",
            category: .behavioral, tier: .silver, iconName: "moon.stars.fill", target: 5,
            tip: "Evening wind-down tasks count—just finish them after 8 PM."
        ),
        AwardDefinition(
            id: "deep_work_marathon", title: "Deep Work Marathon", details: "Complete 3 Deep Work tasks in a single day.",
            category: .behavioral, tier: .gold, iconName: "brain.head.profile", target: 3,
            tip: "Block your calendar and stack three focused sessions in one day."
        ),
        AwardDefinition(
            id: "weekend_warrior", title: "Weekend Warrior", details: "Complete 10 tasks on Saturdays or Sundays.",
            category: .behavioral, tier: .silver, iconName: "figure.hiking", target: 10,
            tip: "Personal errands and hobbies on the weekend count too."
        ),

        // Secret / Hidden Milestones
        AwardDefinition(
            id: "comeback_kid", title: "Comeback Kid", details: "Complete a task after missing 3 or more days in a row.",
            category: .secret, tier: .silver, iconName: "arrow.uturn.up.circle.fill", target: 1, isSecret: true,
            tip: "Breaks happen. What matters is coming back."
        ),
        AwardDefinition(
            id: "speedrunner", title: "Speedrunner", details: "Complete 5 tasks within 2 hours of creating them.",
            category: .secret, tier: .gold, iconName: "stopwatch.fill", target: 5, isSecret: true,
            tip: "Capture it, then crush it right away."
        ),
        AwardDefinition(
            id: "overachiever", title: "Overachiever", details: "Earn 250+ XP in a single calendar day.",
            category: .secret, tier: .gold, iconName: "chart.line.uptrend.xyaxis", target: 250, isSecret: true,
            tip: "A huge day. Remember to claim your daily checkpoints, too."
        ),
        AwardDefinition(
            id: "midnight_oil", title: "Midnight Oil", details: "Complete a task between 12:00 AM and 3:00 AM.",
            category: .secret, tier: .obsidian, iconName: "moon.zzz.fill", target: 1, isSecret: true,
            tip: "Impressive dedication. Now get some sleep."
        ),
    ]

    /// V1 award ids that were renamed in V2. Unlocks carry over to the new id.
    nonisolated static let legacyIDs: [String: String] = [
        "first_step": "spark",
        "sunday_planner": "architect",
    ]

    nonisolated static func definition(for id: String) -> AwardDefinition? {
        definitions.first { $0.id == id }
    }

    nonisolated static let catalogOrder: [String: Int] = Dictionary(
        uniqueKeysWithValues: definitions.enumerated().map { ($1.id, $0) }
    )

    /// The unlock currently being celebrated on screen, if any.
    private(set) var presentedUnlock: AwardUnlock?
    /// Increments on every presentation; drives haptic feedback.
    private(set) var celebrationCount = 0

    @ObservationIgnored private var queue: [AwardUnlock] = []

    // MARK: Seeding & migration

    /// Brings the `Award` table in line with the catalog: inserts missing badges, refreshes
    /// metadata on existing ones, carries V1 unlocks over to renamed ids, and removes retired ids.
    /// Unlocked badges always stay unlocked.
    func seedAwardsIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Award>())) ?? []
        var byID: [String: Award] = [:]
        for award in existing {
            if byID[award.id] == nil {
                byID[award.id] = award
            } else {
                context.delete(award)
            }
        }

        for (legacyID, newID) in Self.legacyIDs {
            guard let legacy = byID.removeValue(forKey: legacyID) else { continue }
            if legacy.isUnlocked, byID[newID] == nil, let definition = Self.definition(for: newID) {
                let migrated = makeAward(from: definition)
                migrated.isUnlocked = true
                migrated.unlockedDate = legacy.unlockedDate
                migrated.currentProgress = definition.target
                context.insert(migrated)
                byID[newID] = migrated
            }
            context.delete(legacy)
        }

        for (id, award) in byID where Self.definition(for: id) == nil {
            context.delete(award)
            byID[id] = nil
        }

        for definition in Self.definitions {
            if let award = byID[definition.id] {
                apply(definition, to: award)
            } else {
                context.insert(makeAward(from: definition))
            }
        }

        if context.hasChanges {
            try? context.save()
        }
    }

    private func makeAward(from definition: AwardDefinition) -> Award {
        Award(
            id: definition.id,
            title: definition.title,
            details: definition.details,
            category: definition.category,
            iconName: definition.iconName,
            tier: definition.tier,
            isSecret: definition.isSecret,
            targetProgress: definition.target
        )
    }

    private func apply(_ definition: AwardDefinition, to award: Award) {
        if award.title != definition.title { award.title = definition.title }
        if award.details != definition.details { award.details = definition.details }
        if award.category != definition.category { award.category = definition.category }
        if award.iconName != definition.iconName { award.iconName = definition.iconName }
        if award.storedTier != definition.tier { award.tier = definition.tier }
        if award.storedIsSecret != definition.isSecret { award.isSecret = definition.isSecret }
        if award.targetProgress != definition.target { award.targetProgress = definition.target }
        let progress = award.isUnlocked ? definition.target : min(award.currentProgress, definition.target)
        if award.currentProgress != progress { award.currentProgress = progress }
    }

    // MARK: Evaluation

    struct RuleResult: Equatable {
        let progress: Int
        let isEarned: Bool
    }

    /// Evaluates all 24 rules against the current tasks.
    static func evaluateRules(
        tasks: [TaskItem],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [String: RuleResult] {
        let today = calendar.startOfDay(for: now)

        // Completions
        let completions: [(task: TaskItem, date: Date)] = tasks.compactMap { task in
            guard task.isCompleted, let date = task.completedAt else { return nil }
            return (task, date)
        }
        let completedCount = completions.count
        let totalXP = completions.reduce(0) { $0 + $1.task.effort.points }

        var countPerDay: [Date: Int] = [:]
        var xpPerDay: [Date: Int] = [:]
        var deepPerDay: [Date: Int] = [:]
        var early = 0, lunch = 0, night = 0, weekend = 0, speedy = 0, deepTotal = 0
        var midnightOil = false

        for (task, date) in completions {
            let day = calendar.startOfDay(for: date)
            countPerDay[day, default: 0] += 1
            xpPerDay[day, default: 0] += task.effort.points
            if task.effort == .deepWork {
                deepPerDay[day, default: 0] += 1
                deepTotal += 1
            }

            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let hour = parts.hour ?? 12
            let minuteOfDay = hour * 60 + (parts.minute ?? 0)
            if hour < 9 { early += 1 }
            if (690...810).contains(minuteOfDay) { lunch += 1 }   // 11:30 AM – 1:30 PM
            if hour >= 20 { night += 1 }
            if hour < 3 { midnightOil = true }
            if calendar.isDateInWeekend(date) { weekend += 1 }

            let elapsed = date.timeIntervalSince(task.createdAt)
            if elapsed >= 0, elapsed <= 2 * 60 * 60 { speedy += 1 }
        }

        let bestDayCount = countPerDay.values.max() ?? 0
        let bestDayXP = xpPerDay.values.max() ?? 0
        let bestDeepDay = deepPerDay.values.max() ?? 0

        let currentStreak = PlannerStats.currentStreak(tasks, now: now, calendar: calendar)
        let longestStreak = PlannerStats.longestStreak(tasks, calendar: calendar)

        // Comeback: a completion day preceded by a gap of 3+ empty days.
        let completionDays = countPerDay.keys.sorted()
        let comeback = zip(completionDays, completionDays.dropFirst()).contains { earlier, later in
            (calendar.dateComponents([.day], from: earlier, to: later).day ?? 0) >= 4
        }

        // Planning: the upcoming week is tomorrow through 7 days from now.
        let tomorrow = calendar.dayOffset(1, from: today)
        let upcomingEnd = calendar.dayOffset(8, from: today)
        let upcoming = tasks.filter { task in
            guard let date = task.scheduledDate else { return false }
            return date >= tomorrow && date < upcomingEnd
        }
        let upcomingDays = Set(upcoming.compactMap { task in
            task.scheduledDate.map { calendar.startOfDay(for: $0) }
        }).count

        let overdue = tasks.count { $0.isOverdue(asOf: now, calendar: calendar) }
        let cleanSlate = completedCount >= 10 && overdue == 0

        // Inbox Zero Hero: Monday–Sunday week containing `now`.
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        var weekTotal = 0
        var weekDone = 0
        if let week = mondayCalendar.dateInterval(of: .weekOfYear, for: now) {
            for task in tasks {
                guard let date = task.scheduledDate, week.contains(date) else { continue }
                weekTotal += 1
                if task.isCompleted { weekDone += 1 }
            }
        }
        let inboxZero = weekTotal >= 7 && weekDone == weekTotal

        func result(_ progress: Int, _ earned: Bool) -> RuleResult {
            RuleResult(progress: progress, isEarned: earned)
        }

        return [
            "spark": result(completedCount, completedCount >= 1),
            "hat_trick": result(countPerDay[today] ?? 0, bestDayCount >= 3),
            "momentum": result(currentStreak, longestStreak >= 3),
            "week_warrior": result(currentStreak, longestStreak >= 7),
            "fortnight_focus": result(currentStreak, longestStreak >= 14),
            "unbreakable": result(currentStreak, longestStreak >= 30),

            "architect": result(upcoming.count, upcoming.count >= 5),
            "mastermind": result(upcomingDays, upcomingDays >= 7),
            // While a blocker remains, the bar stops one short so it never reads "full but locked".
            "clean_slate": result(cleanSlate ? 10 : min(completedCount, 9), cleanSlate),
            "inbox_zero_hero": result(inboxZero ? 7 : min(weekDone, 6), inboxZero),

            "getting_rolling": result(completedCount, completedCount >= 10),
            "heavy_lifter": result(deepTotal, deepTotal >= 10),
            "quarter_century": result(completedCount, completedCount >= 25),
            "centurion": result(completedCount, completedCount >= 100),
            "titan_of_focus": result(totalXP, totalXP >= 2500),

            "early_bird": result(early, early >= 5),
            "lunchtime_hustle": result(lunch, lunch >= 5),
            "night_owl": result(night, night >= 5),
            "deep_work_marathon": result(deepPerDay[today] ?? 0, bestDeepDay >= 3),
            "weekend_warrior": result(weekend, weekend >= 10),

            "comeback_kid": result(comeback ? 1 : 0, comeback),
            "speedrunner": result(speedy, speedy >= 5),
            "overachiever": result(xpPerDay[today] ?? 0, bestDayXP >= 250),
            "midnight_oil": result(midnightOil ? 1 : 0, midnightOil),
        ]
    }

    /// Updates progress on every award and unlocks any whose rule is now satisfied.
    /// Unlocked awards are never revoked. Newly unlocked awards are queued for celebration when `announce` is true.
    @discardableResult
    func evaluate(in context: ModelContext, announce: Bool = true, now: Date = .now) -> [AwardUnlock] {
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let awards = (try? context.fetch(FetchDescriptor<Award>())) ?? []
        let results = Self.evaluateRules(tasks: tasks, now: now)

        var unlocked: [AwardUnlock] = []
        for award in awards.sorted(by: { (Self.catalogOrder[$0.id] ?? .max) < (Self.catalogOrder[$1.id] ?? .max) }) {
            guard !award.isUnlocked, let result = results[award.id] else { continue }
            if result.isEarned {
                award.isUnlocked = true
                award.unlockedDate = now
                award.currentProgress = award.targetProgress
                unlocked.append(AwardUnlock(award))
            } else {
                let progress = min(max(result.progress, 0), award.targetProgress)
                if award.currentProgress != progress {
                    award.currentProgress = progress
                }
            }
        }

        if context.hasChanges {
            try? context.save()
        }
        if announce, !unlocked.isEmpty {
            // Celebrate the rarest first.
            queue.append(contentsOf: unlocked.sorted { $0.tier > $1.tier })
            presentNextIfIdle()
        }
        return unlocked
    }

    // MARK: Celebration queue

    func dismissPresentedUnlock() {
        guard presentedUnlock != nil else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            presentedUnlock = nil
        }
        guard !queue.isEmpty else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.presentNextIfIdle()
        }
    }

    func clearPendingUnlocks() {
        queue.removeAll()
        presentedUnlock = nil
    }

    private func presentNextIfIdle() {
        guard presentedUnlock == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        celebrationCount += 1
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            presentedUnlock = next
        }
    }
}
