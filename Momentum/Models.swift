import Foundation
import SwiftData
import SwiftUI

// MARK: - Enums

enum EffortLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case quick
    case standard
    case deepWork

    var id: String { rawValue }

    /// XP (and Leisure Points) earned when a task of this effort is completed.
    var points: Int {
        switch self {
        case .quick: 10
        case .standard: 25
        case .deepWork: 50
        }
    }

    var label: String {
        switch self {
        case .quick: "Quick"
        case .standard: "Standard"
        case .deepWork: "Deep Work"
        }
    }

    var iconName: String {
        switch self {
        case .quick: "hare.fill"
        case .standard: "bolt.fill"
        case .deepWork: "brain.head.profile"
        }
    }

    var tint: Color {
        switch self {
        case .quick: Theme.cyan
        case .standard: Theme.indigo
        case .deepWork: Theme.violet
        }
    }

    /// Ordering used to find the "highest effort" task.
    var rank: Int {
        switch self {
        case .quick: 0
        case .standard: 1
        case .deepWork: 2
        }
    }
}

enum AwardCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case consistency
    case planning
    case volume
    case behavioral
    case secret

    var id: String { rawValue }

    var title: String {
        switch self {
        case .consistency: "Consistency & Streaks"
        case .planning: "Planning & Foresight"
        case .volume: "Volume & Effort"
        case .behavioral: "Time & Behavior"
        case .secret: "Secret Milestones"
        }
    }

    var iconName: String {
        switch self {
        case .consistency: "flame.fill"
        case .planning: "calendar"
        case .volume: "chart.bar.fill"
        case .behavioral: "clock.fill"
        case .secret: "eye.slash.fill"
        }
    }

    /// Core gradient stops for medallions in this category.
    var colors: [Color] {
        switch self {
        case .consistency: [Color(hex: 0xFB923C), Color(hex: 0xE11D48)]
        case .planning: [Color(hex: 0x22D3EE), Theme.indigo]
        case .volume: [Color(hex: 0xA78BFA), Color(hex: 0xDB2777)]
        case .behavioral: [Color(hex: 0x34D399), Color(hex: 0x0891B2)]
        case .secret: [Color(hex: 0x818CF8), Color(hex: 0x312E81)]
        }
    }

    var gradient: LinearGradient {
        Theme.diagonal(colors)
    }
}

enum AwardTier: String, Codable, CaseIterable, Identifiable, Sendable, Comparable {
    case bronze
    case silver
    case gold
    case obsidian

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .obsidian: "Obsidian"
        }
    }

    var rank: Int {
        switch self {
        case .bronze: 0
        case .silver: 1
        case .gold: 2
        case .obsidian: 3
        }
    }

    static func < (lhs: AwardTier, rhs: AwardTier) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Angular-gradient stops for the metallic rim (first and last match for a seamless loop).
    var rimColors: [Color] {
        switch self {
        case .bronze:
            [Color(hex: 0xF0B47A), Color(hex: 0x8C4A1C), Color(hex: 0xCD7F32), Color(hex: 0x5E3110), Color(hex: 0xF0B47A)]
        case .silver:
            [Color(hex: 0xF8FAFC), Color(hex: 0x94A3B8), Color(hex: 0xE2E8F0), Color(hex: 0x64748B), Color(hex: 0xF8FAFC)]
        case .gold:
            [Color(hex: 0xFDE68A), Color(hex: 0xB45309), Color(hex: 0xFCD34D), Color(hex: 0x92400E), Color(hex: 0xFDE68A)]
        case .obsidian:
            [Theme.amber, Theme.rose, Theme.violet, Theme.indigo, Theme.amber]
        }
    }

    var glowColor: Color {
        switch self {
        case .bronze: Color(hex: 0xCD7F32)
        case .silver: Color(hex: 0xCBD5E1)
        case .gold: Color(hex: 0xFBBF24)
        case .obsidian: Theme.rose
        }
    }

    var labelColors: [Color] {
        switch self {
        case .bronze: [Color(hex: 0xF0B47A), Color(hex: 0xB8692E)]
        case .silver: [Color(hex: 0xF1F5F9), Color(hex: 0x94A3B8)]
        case .gold: [Color(hex: 0xFDE68A), Theme.amber]
        case .obsidian: Theme.legendaryColors
        }
    }
}

enum RewardKind: String, Codable, CaseIterable, Sendable {
    /// Free to claim once per day after earning `cost` XP that day.
    case dailyCheckpoint
    /// Bought with spendable Leisure Points.
    case shopReward
    /// Won from a Mystery Loot Box (the redemption records the crate's price).
    case mysteryCrate
}

/// The 30-minute minimum break standard: every timed leisure reward, crate drop and Live
/// Activity lasts at least this long.
enum BreakPolicy {
    static let minimumMinutes = 30

    /// `nil` stays `nil` (an untimed reward); anything else is raised to the minimum.
    static func clamped(_ minutes: Int?) -> Int? {
        minutes.map { max(minimumMinutes, $0) }
    }

    /// "30 min", "1 hr", "90 min", "4 hr".
    static func label(for minutes: Int) -> String {
        minutes >= 60 && minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes) min"
    }
}

/// How rare a Guilt-Free Pass is; drives crate styling.
enum PassRarity: String, Codable, CaseIterable, Sendable, Comparable {
    case common
    case rare
    case epic
    case legendary

    var title: String {
        switch self {
        case .common: "Common"
        case .rare: "Rare"
        case .epic: "Epic"
        case .legendary: "Legendary"
        }
    }

    var rank: Int {
        switch self {
        case .common: 0
        case .rare: 1
        case .epic: 2
        case .legendary: 3
        }
    }

    static func < (lhs: PassRarity, rhs: PassRarity) -> Bool { lhs.rank < rhs.rank }

    var colors: [Color] {
        switch self {
        case .common: [Color(hex: 0x94A3B8), Color(hex: 0x475569)]
        case .rare: Theme.successColors
        case .epic: Theme.primaryColors
        case .legendary: Theme.legendaryColors
        }
    }

    var glowColor: Color { colors.last ?? Theme.violet }
}

/// Where a saved pass came from.
enum PassSource: String, Codable, Sendable {
    case dailyCheckpoint
    case shop
    case mysteryCrate
}

/// Non-task events that matter to XP, combos or badges.
enum MomentumEventKind: String, Codable, CaseIterable, Sendable {
    /// Finished the Sunday Reset ritual (+25 XP).
    case sundayReset
    /// Finished the Morning Kickoff ritual (+25 XP).
    case morningKickoff
    /// Cleared 100% of today's tasks before 5 PM: 1.5x for the rest of the day (0 XP itself).
    case earlyFinisher

    var title: String {
        switch self {
        case .sundayReset: "Sunday Reset"
        case .morningKickoff: "Morning Kickoff"
        case .earlyFinisher: "Early Finisher Bonus"
        }
    }
}

// MARK: - SwiftData models

// CloudKit-compatible models: every attribute has a default or is optional, and there are
// no `.unique` constraints (CloudKit can't enforce them). Duplicates that can appear when
// two devices seed the same data are merged in `AwardEngine` / `RewardCatalog`.

@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    /// `nil` means the task lives in the unscheduled "Someday" backlog.
    var scheduledDate: Date?
    var isCompleted: Bool = false
    var completedAt: Date?
    var effort: EffortLevel = EffortLevel.standard
    var createdAt: Date = Date.now
    // Added in V4 (optional, so older rows and CloudKit records decode as "not set").
    /// Combo multiplier locked in when the task was completed (1.0, 1.5 or 2.0).
    var storedXPMultiplier: Double?
    /// Set when the Sunday Reset clears the task: it leaves every list but isn't deleted.
    var archivedAt: Date?
    /// Order chosen in Morning Kickoff (lower first) for tasks of the same day.
    var priorityRank: Int?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        scheduledDate: Date? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        effort: EffortLevel = .standard,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.scheduledDate = scheduledDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.effort = effort
        self.createdAt = createdAt
    }

    var isArchived: Bool { archivedAt != nil }

    func isScheduled(on day: Date, calendar: Calendar = .current) -> Bool {
        guard !isArchived, let scheduledDate else { return false }
        return calendar.isDate(scheduledDate, inSameDayAs: day)
    }

    /// Incomplete, not archived, and scheduled before the start of today.
    func isOverdue(asOf now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !isCompleted, !isArchived, let scheduledDate else { return false }
        return scheduledDate < calendar.startOfDay(for: now)
    }

    var xpMultiplier: Double { storedXPMultiplier ?? 1 }

    /// XP (and Leisure Points) this task earned: its effort value times the combo multiplier
    /// it was completed under, rounded. Zero while incomplete.
    var earnedXP: Int {
        guard isCompleted else { return 0 }
        return ComboMath.apply(xpMultiplier, to: effort.points)
    }
}

@Model
final class Award {
    /// Catalog slug, e.g. `"week_warrior"`.
    var id: String = ""
    var title: String = ""
    var details: String = ""
    var category: AwardCategory = AwardCategory.consistency
    var iconName: String = "star.fill"
    var isUnlocked: Bool = false
    var unlockedDate: Date?
    var currentProgress: Int = 0
    var targetProgress: Int = 1
    // Added in V2. Stored as optionals so rows from a V1 store (which have NULL here
    // after lightweight migration) decode safely; use `tier` / `isSecret` instead.
    var storedTier: AwardTier?
    var storedIsSecret: Bool?

    var tier: AwardTier {
        get { storedTier ?? .bronze }
        set { storedTier = newValue }
    }

    var isSecret: Bool {
        get { storedIsSecret ?? false }
        set { storedIsSecret = newValue }
    }

    init(
        id: String,
        title: String,
        details: String,
        category: AwardCategory,
        iconName: String,
        tier: AwardTier = .bronze,
        isSecret: Bool = false,
        isUnlocked: Bool = false,
        unlockedDate: Date? = nil,
        currentProgress: Int = 0,
        targetProgress: Int
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.category = category
        self.iconName = iconName
        self.storedTier = tier
        self.storedIsSecret = isSecret
        self.isUnlocked = isUnlocked
        self.unlockedDate = unlockedDate
        self.currentProgress = currentProgress
        self.targetProgress = targetProgress
    }

    var progressFraction: Double {
        guard targetProgress > 0 else { return 0 }
        return min(1, Double(currentProgress) / Double(targetProgress))
    }

    /// Secret awards hide their name and description until unlocked.
    var isHidden: Bool { isSecret && !isUnlocked }
}

/// A real-world reward: either a daily XP checkpoint or a shop item bought with Leisure Points.
@Model
final class RewardCheckpoint {
    var id: UUID = UUID()
    /// Stable identifier for built-in rewards; empty for user-created ones.
    var slug: String = ""
    var title: String = ""
    var details: String = ""
    var iconName: String = "gift.fill"
    /// Points spent (shop) or XP needed today (daily checkpoint).
    var cost: Int = 0
    var kind: RewardKind = RewardKind.shopReward
    var isCustom: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    /// Break length for timed rewards (at least 30); `nil` for untimed ones like Takeout Night.
    var durationMinutes: Int?

    init(
        id: UUID = UUID(),
        slug: String = "",
        title: String,
        details: String,
        iconName: String,
        cost: Int,
        kind: RewardKind,
        isCustom: Bool,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        durationMinutes: Int? = nil
    ) {
        self.id = id
        self.slug = slug
        self.title = title
        self.details = details
        self.iconName = iconName
        self.cost = cost
        self.kind = kind
        self.isCustom = isCustom
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.durationMinutes = BreakPolicy.clamped(durationMinutes)
    }

    /// Break length with the 30-minute minimum applied.
    var breakMinutes: Int? { BreakPolicy.clamped(durationMinutes) }
}

/// A claimed reward, shown as a timestamped "Guilt-Free Pass". Copies the reward's
/// details so the pass survives the reward being edited or deleted.
@Model
final class RewardRedemption {
    var id: UUID = UUID()
    var rewardID: UUID?
    var title: String = ""
    var details: String = ""
    var iconName: String = "ticket.fill"
    /// Leisure Points spent (0 for daily checkpoints).
    var pointsSpent: Int = 0
    var kind: RewardKind = RewardKind.shopReward
    var redeemedAt: Date = Date.now
    /// Break length copied from the reward (V4); `nil` for untimed and older passes.
    var durationMinutes: Int?

    init(
        id: UUID = UUID(),
        rewardID: UUID?,
        title: String,
        details: String,
        iconName: String,
        pointsSpent: Int,
        kind: RewardKind,
        redeemedAt: Date = .now,
        durationMinutes: Int? = nil
    ) {
        self.id = id
        self.rewardID = rewardID
        self.title = title
        self.details = details
        self.iconName = iconName
        self.pointsSpent = pointsSpent
        self.kind = kind
        self.redeemedAt = redeemedAt
        self.durationMinutes = BreakPolicy.clamped(durationMinutes)
    }

    convenience init(reward: RewardCheckpoint, pointsSpent: Int, redeemedAt: Date = .now) {
        self.init(
            rewardID: reward.id,
            title: reward.title,
            details: reward.details,
            iconName: reward.iconName,
            pointsSpent: pointsSpent,
            kind: reward.kind,
            redeemedAt: redeemedAt,
            durationMinutes: reward.breakMinutes
        )
    }

    /// Short voucher code derived from the id, e.g. `GF-8F3A-21C9`.
    var passCode: String {
        let raw = id.uuidString.replacingOccurrences(of: "-", with: "")
        return "GF-\(raw.prefix(4))-\(raw.dropFirst(4).prefix(4))"
    }
}

/// A claimed Guilt-Free Pass in the Saved Passes wallet. Timed passes wait here until the
/// user starts the break timer (a Live Activity on iPhone); untimed ones until marked used.
@Model
final class ActivePass {
    var id: UUID = UUID()
    /// The `RewardRedemption` (voucher) this pass belongs to.
    var redemptionID: UUID?
    var title: String = ""
    var details: String = ""
    var iconName: String = "ticket.fill"
    /// Break length (at least 30); `nil` for untimed passes.
    var durationMinutes: Int?
    var source: PassSource = PassSource.shop
    var rarity: PassRarity = PassRarity.common
    var createdAt: Date = Date.now
    /// When the break timer started.
    var startedAt: Date?
    /// When the break timer ends.
    var endsAt: Date?
    /// Ended early, marked used, or seen expired.
    var finishedAt: Date?

    init(
        id: UUID = UUID(),
        redemptionID: UUID?,
        title: String,
        details: String,
        iconName: String,
        durationMinutes: Int?,
        source: PassSource,
        rarity: PassRarity = .common,
        createdAt: Date = .now
    ) {
        self.id = id
        self.redemptionID = redemptionID
        self.title = title
        self.details = details
        self.iconName = iconName
        self.durationMinutes = BreakPolicy.clamped(durationMinutes)
        self.source = source
        self.rarity = rarity
        self.createdAt = createdAt
    }

    enum Status: Equatable {
        /// In the wallet, timer not started (or an unused untimed pass).
        case saved
        /// Break timer running until `endsAt`.
        case running(endsAt: Date)
        case used
    }

    func status(at now: Date = .now) -> Status {
        if finishedAt != nil { return .used }
        if let endsAt {
            return endsAt > now ? .running(endsAt: endsAt) : .used
        }
        return .saved
    }

    var isTimed: Bool { durationMinutes != nil }
    var breakMinutes: Int? { BreakPolicy.clamped(durationMinutes) }
}

/// Non-task XP and markers: ritual completions (+25 XP) and the Early Finisher bonus.
@Model
final class MomentumEvent {
    var id: UUID = UUID()
    var kind: MomentumEventKind = MomentumEventKind.sundayReset
    var xp: Int = 0
    var occurredAt: Date = Date.now
    /// Cards reviewed in a ritual.
    var itemCount: Int = 0

    init(id: UUID = UUID(), kind: MomentumEventKind, xp: Int, occurredAt: Date = .now, itemCount: Int = 0) {
        self.id = id
        self.kind = kind
        self.xp = xp
        self.occurredAt = occurredAt
        self.itemCount = itemCount
    }
}

// MARK: - Reminder preferences

struct ReminderSlot: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var label: String
    /// 0–23
    var hour: Int
    /// 0–59
    var minute: Int
    var isEnabled: Bool = true
    /// `false` sends a summary of the day regardless; `true` only fires while tasks remain.
    var onlyIfIncomplete: Bool

    static var defaultSchedule: [ReminderSlot] {
        [
            ReminderSlot(label: "Morning Kickoff", hour: 8, minute: 0, onlyIfIncomplete: false),
            ReminderSlot(label: "Midday Check-In", hour: 12, minute: 0, onlyIfIncomplete: true),
            ReminderSlot(label: "Afternoon Final Push", hour: 16, minute: 0, onlyIfIncomplete: true),
        ]
    }
}

// MARK: - Value snapshots & stats

/// Sendable copy of the task fields the notification scheduler needs.
struct TaskSnapshot: Sendable, Equatable {
    let title: String
    let scheduledDate: Date?
    let isCompleted: Bool
    let effort: EffortLevel
    let createdAt: Date

    init(title: String, scheduledDate: Date?, isCompleted: Bool, effort: EffortLevel, createdAt: Date) {
        self.title = title
        self.scheduledDate = scheduledDate
        self.isCompleted = isCompleted
        self.effort = effort
        self.createdAt = createdAt
    }

    init(_ task: TaskItem) {
        self.init(
            title: task.title,
            scheduledDate: task.scheduledDate,
            isCompleted: task.isCompleted,
            effort: task.effort,
            createdAt: task.createdAt
        )
    }
}

struct DayCompletion: Identifiable, Equatable {
    let date: Date
    let count: Int
    var id: Date { date }
}

extension Calendar {
    /// Start of the day `offset` days away from `date`.
    func dayOffset(_ offset: Int, from date: Date = .now) -> Date {
        let start = startOfDay(for: date)
        return self.date(byAdding: .day, value: offset, to: start) ?? start
    }
}

enum PlannerStats {
    /// Lifetime XP: completed tasks (with their combo multipliers) plus ritual bonuses.
    static func totalXP(_ tasks: [TaskItem], events: [MomentumEvent] = []) -> Int {
        tasks.reduce(0) { $0 + $1.earnedXP } + events.reduce(0) { $0 + $1.xp }
    }

    /// XP earned on the calendar day containing `day`.
    static func xpEarned(on day: Date, tasks: [TaskItem], events: [MomentumEvent] = [], calendar: Calendar = .current) -> Int {
        let taskXP = tasks.reduce(0) { sum, task in
            guard task.isCompleted, let completedAt = task.completedAt,
                  calendar.isDate(completedAt, inSameDayAs: day) else { return sum }
            return sum + task.earnedXP
        }
        let bonusXP = events.reduce(0) { sum, event in
            calendar.isDate(event.occurredAt, inSameDayAs: day) ? sum + event.xp : sum
        }
        return taskXP + bonusXP
    }

    static func completedCount(_ tasks: [TaskItem]) -> Int {
        tasks.count(where: \.isCompleted)
    }

    /// Distinct days (start of day) on which at least one task was completed.
    static func completionDays(_ tasks: [TaskItem], calendar: Calendar = .current) -> Set<Date> {
        Set(tasks.compactMap { task in
            guard task.isCompleted, let completedAt = task.completedAt else { return nil }
            return calendar.startOfDay(for: completedAt)
        })
    }

    /// Consecutive days with a completion, ending today (or yesterday if today has none yet).
    static func currentStreak(_ tasks: [TaskItem], now: Date = .now, calendar: Calendar = .current) -> Int {
        let days = completionDays(tasks, calendar: calendar)
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            cursor = calendar.dayOffset(-1, from: cursor)
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = calendar.dayOffset(-1, from: cursor)
        }
        return streak
    }

    static func longestStreak(_ tasks: [TaskItem], calendar: Calendar = .current) -> Int {
        let days = completionDays(tasks, calendar: calendar).sorted()
        var longest = 0
        var run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.dayOffset(1, from: previous) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }
        return longest
    }

    /// Completions per day for the trailing `days` days, oldest first, ending today.
    static func dailyCompletions(
        _ tasks: [TaskItem],
        days: Int = 7,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DayCompletion] {
        var counts: [Date: Int] = [:]
        for task in tasks where task.isCompleted {
            guard let completedAt = task.completedAt else { continue }
            counts[calendar.startOfDay(for: completedAt), default: 0] += 1
        }
        return (0..<days).reversed().map { offset in
            let day = calendar.dayOffset(-offset, from: now)
            return DayCompletion(date: day, count: counts[day] ?? 0)
        }
    }
}

// MARK: - Sample data (previews & demo re-seed)

@MainActor
enum PreviewSampleData {
    static let modelTypes: [any PersistentModel.Type] = [
        TaskItem.self, Award.self, RewardCheckpoint.self, RewardRedemption.self,
        ActivePass.self, MomentumEvent.self,
    ]

    /// In-memory container pre-filled with sample tasks, rewards, passes and evaluated awards.
    static let container: ModelContainer = {
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: Schema(modelTypes), configurations: configuration)
            let context = container.mainContext
            insertSampleTasks(into: context)
            RewardCatalog.seedIfNeeded(in: context)
            insertSampleRedemptions(into: context)
            awardEngine.seedAwardsIfNeeded(in: context)
            awardEngine.evaluate(in: context, announce: false)
            return container
        } catch {
            fatalError("Unable to create preview container: \(error)")
        }
    }()

    static let awardEngine = AwardEngine()

    static let comboEngine = ComboEngine()

    static let notificationManager = NotificationManager(
        defaults: UserDefaults(suiteName: "momentum.preview") ?? .standard
    )

    static let store = TaskStore(
        context: container.mainContext,
        awardEngine: awardEngine,
        notificationManager: notificationManager,
        comboEngine: comboEngine
    )

    static var sampleTask: TaskItem {
        TaskItem(
            title: "Draft Q4 roadmap",
            notes: "Outline the three big bets and owners.",
            scheduledDate: Calendar.current.startOfDay(for: .now),
            effort: .deepWork
        )
    }

    static var sampleUnlock: AwardUnlock {
        AwardUnlock(AwardEngine.definitions[AwardEngine.definitions.count - 1])
    }

    static var sampleRedemption: RewardRedemption {
        RewardRedemption(
            rewardID: nil,
            title: "1-Hour Gaming / Movie Session",
            details: "A full hour of games or a movie, earned through deep focus.",
            iconName: "gamecontroller.fill",
            pointsSpent: 120,
            kind: .shopReward,
            durationMinutes: 60
        )
    }

    static func insertSampleTasks(into context: ModelContext, now: Date = .now) {
        for task in makeSampleTasks(now: now) {
            context.insert(task)
        }
    }

    /// A couple of past passes so the Rewards tab shows history and a non-trivial balance.
    static func insertSampleRedemptions(into context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        let rewards = (try? context.fetch(FetchDescriptor<RewardCheckpoint>())) ?? []
        func at(daysAgo: Int, hour: Int) -> Date {
            let day = calendar.dayOffset(-daysAgo, from: now)
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        if let treat = rewards.first(where: { $0.slug == "shop_treat" }) {
            context.insert(RewardRedemption(reward: treat, pointsSpent: treat.cost, redeemedAt: at(daysAgo: 2, hour: 15)))
        }
        if let snack = rewards.first(where: { $0.slug == "daily_snack_break" }) {
            context.insert(RewardRedemption(reward: snack, pointsSpent: 0, redeemedAt: at(daysAgo: 1, hour: 14)))
        }
    }

    /// A realistic history: an 8-day streak, a 3-task day, deep work, early and late finishes,
    /// today's plan, one overdue task, a well-planned week ahead, and a backlog.
    static func makeSampleTasks(now: Date = .now, calendar: Calendar = .current) -> [TaskItem] {
        var sequence = 0
        let baseCreation = calendar.dayOffset(-21, from: now)

        func nextCreationDate() -> Date {
            sequence += 1
            return baseCreation.addingTimeInterval(TimeInterval(sequence * 60))
        }

        func done(_ title: String, _ effort: EffortLevel, daysAgo: Int, hour: Int, minute: Int = 0, notes: String = "") -> TaskItem {
            let day = calendar.dayOffset(-daysAgo, from: now)
            let finished = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            return TaskItem(
                title: title,
                notes: notes,
                scheduledDate: day,
                isCompleted: true,
                completedAt: min(finished, now),
                effort: effort,
                createdAt: nextCreationDate()
            )
        }

        func open(_ title: String, _ effort: EffortLevel, inDays: Int?, notes: String = "") -> TaskItem {
            TaskItem(
                title: title,
                notes: notes,
                scheduledDate: inDays.map { calendar.dayOffset($0, from: now) },
                effort: effort,
                createdAt: nextCreationDate()
            )
        }

        return [
            // History
            done("Set up project board", .standard, daysAgo: 8, hour: 14),
            done("Book dentist appointment", .quick, daysAgo: 7, hour: 11, minute: 45),
            done("Write onboarding guide", .deepWork, daysAgo: 6, hour: 15, minute: 45),
            done("Inbox zero", .quick, daysAgo: 5, hour: 10),
            done("Review pull requests", .standard, daysAgo: 5, hour: 12, minute: 30),
            done("Prepare sprint demo", .standard, daysAgo: 5, hour: 17),
            done("Refactor sync engine", .deepWork, daysAgo: 4, hour: 7, minute: 30, notes: "Early focus block before standup."),
            done("Plan team offsite agenda", .standard, daysAgo: 3, hour: 16),
            done("Research analytics vendors", .deepWork, daysAgo: 2, hour: 11),
            done("Pay electricity bill", .quick, daysAgo: 2, hour: 20, minute: 15),
            done("1:1 prep notes", .standard, daysAgo: 1, hour: 8, minute: 30),
            done("Water the plants", .quick, daysAgo: 1, hour: 21),
            done("Morning stretch routine", .quick, daysAgo: 0, hour: 23),

            // Overdue
            open("Reply to landlord email", .quick, inDays: -1, notes: "Confirm the renewal dates."),

            // Today
            open("Draft Q4 roadmap", .deepWork, inDays: 0, notes: "Outline the three big bets and owners."),
            open("Review design mockups", .standard, inDays: 0),
            open("Order birthday gift", .quick, inDays: 0),

            // The week ahead
            open("Write release notes", .standard, inDays: 1),
            open("Gym: leg day", .quick, inDays: 1),
            open("Prototype widget extension", .deepWork, inDays: 2, notes: "Timebox to two hours."),
            open("Call grandma", .quick, inDays: 3),
            open("Quarterly budget review", .standard, inDays: 4),
            open("Meal prep for the week", .standard, inDays: 5),

            // Later
            open("Renew passport", .standard, inDays: 10),
            open("Plan winter trip itinerary", .deepWork, inDays: 21),

            // Someday backlog
            open("Learn Swift Charts in depth", .deepWork, inDays: nil),
            open("Organize photo library", .standard, inDays: nil),
            open("Try the new ramen place", .quick, inDays: nil),
        ]
    }
}

extension View {
    /// Injects the sample container and services so previews render realistic data.
    @MainActor
    func previewEnvironment() -> some View {
        self
            .modelContainer(PreviewSampleData.container)
            .environment(PreviewSampleData.store)
            .environment(PreviewSampleData.awardEngine)
            .environment(PreviewSampleData.notificationManager)
            .environment(PreviewSampleData.comboEngine)
            .tint(Theme.indigo)
            .preferredColorScheme(.dark)
    }
}
