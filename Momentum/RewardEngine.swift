import Foundation
import SwiftData
import SwiftUI

/// Built-in real-world rewards seeded on first launch.
enum RewardCatalog {
    struct Seed: Sendable {
        let slug: String
        let title: String
        let details: String
        let iconName: String
        let cost: Int
        let kind: RewardKind
        /// At least 30 for timed breaks; `nil` for untimed rewards.
        var durationMinutes: Int?
    }

    // Slugs are stable ids: V1–V3 rewards keep theirs (so past passes still point at them)
    // and pick up the V4 titles, prices and durations below on the next launch.
    static let seeds: [Seed] = [
        // Daily checkpoints (free once today's XP reaches the threshold)
        Seed(
            slug: "daily_snack_break",
            title: "30-Min Guilt-Free Snack & Recharge Break",
            details: "Step away for a coffee, tea, or favorite snack and properly recharge. No guilt attached.",
            iconName: "cup.and.saucer.fill",
            cost: 50,
            kind: .dailyCheckpoint,
            durationMinutes: 30
        ),
        Seed(
            slug: "daily_leisure_hour",
            title: "1-Hour Guilt-Free Leisure / Gaming Session",
            details: "Gaming, a show, or anything fun for a full hour. You earned it today.",
            iconName: "gamecontroller.fill",
            cost: 100,
            kind: .dailyCheckpoint,
            durationMinutes: 60
        ),

        // Rewards shop (spend Leisure Points)
        Seed(
            slug: "shop_treat",
            title: "30-Min Guilt-Free Snack & Coffee Break",
            details: "A specialty coffee or favorite snack, enjoyed slowly.",
            iconName: "birthday.cake.fill",
            cost: 50,
            kind: .shopReward,
            durationMinutes: 30
        ),
        Seed(
            slug: "shop_leisure_30",
            title: "45-Min Guilt-Free Hobby / Lounge Pass",
            details: "Read, sketch, scroll or lounge. Your time, completely guilt-free.",
            iconName: "paintpalette.fill",
            cost: 75,
            kind: .shopReward,
            durationMinutes: 45
        ),
        Seed(
            slug: "shop_hobby_hour",
            title: "1-Hour Gaming / Movie Session",
            details: "A full hour of games or a movie, earned through deep focus.",
            iconName: "tv.fill",
            cost: 120,
            kind: .shopReward,
            durationMinutes: 60
        ),
        Seed(
            slug: "shop_recharge_90",
            title: "90-Min Deep Recharge Block",
            details: "A long, restorative break: nap, walk, bath, or nothing at all.",
            iconName: "battery.100percent.bolt",
            cost: 180,
            kind: .shopReward,
            durationMinutes: 90
        ),
        Seed(
            slug: "shop_takeout",
            title: "Takeout / Favorite Meal Night",
            details: "Skip cooking tonight. You crushed your week.",
            iconName: "takeoutbag.and.cup.and.straw.fill",
            cost: 300,
            kind: .shopReward
        ),
        Seed(
            slug: "shop_half_day",
            title: "Half-Day Off / Lazy Afternoon",
            details: "Major reward: clear your afternoon and recharge.",
            iconName: "sun.haze.fill",
            cost: 500,
            kind: .shopReward,
            durationMinutes: 240
        ),
    ]

    /// Inserts any built-in rewards that are missing (custom rewards are untouched) and merges
    /// duplicate built-ins that appear when two devices seed before their first iCloud sync.
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        var existing = (try? context.fetch(FetchDescriptor<RewardCheckpoint>())) ?? []
        existing = mergeDuplicateBuiltIns(existing, in: context)
        let bySlug = Dictionary(existing.filter { !$0.isCustom && !$0.slug.isEmpty }.map { ($0.slug, $0) }) { first, _ in first }
        for (index, seed) in seeds.enumerated() {
            if let reward = bySlug[seed.slug] {
                apply(seed, to: reward, sortOrder: index)
            } else {
                context.insert(RewardCheckpoint(
                    slug: seed.slug,
                    title: seed.title,
                    details: seed.details,
                    iconName: seed.iconName,
                    cost: seed.cost,
                    kind: seed.kind,
                    isCustom: false,
                    sortOrder: index,
                    durationMinutes: seed.durationMinutes
                ))
            }
        }
        // The 30-minute standard applies to custom rewards too (e.g. ones synced from a device
        // running an older build).
        for reward in existing where reward.isCustom {
            let clamped = BreakPolicy.clamped(reward.durationMinutes)
            if reward.durationMinutes != clamped { reward.durationMinutes = clamped }
        }
        if context.hasChanges {
            try? context.save()
        }
    }

    /// Brings a built-in reward in line with its seed (writes only real changes, so a launch
    /// with nothing new doesn't touch iCloud).
    @MainActor
    private static func apply(_ seed: Seed, to reward: RewardCheckpoint, sortOrder: Int) {
        if reward.title != seed.title { reward.title = seed.title }
        if reward.details != seed.details { reward.details = seed.details }
        if reward.iconName != seed.iconName { reward.iconName = seed.iconName }
        if reward.cost != seed.cost { reward.cost = seed.cost }
        if reward.kind != seed.kind { reward.kind = seed.kind }
        if reward.sortOrder != sortOrder { reward.sortOrder = sortOrder }
        let duration = BreakPolicy.clamped(seed.durationMinutes)
        if reward.durationMinutes != duration { reward.durationMinutes = duration }
    }

    /// Keeps the oldest copy of each built-in reward (a choice every device agrees on) and
    /// re-points passes that referenced a removed copy. Returns the surviving rewards.
    @MainActor
    private static func mergeDuplicateBuiltIns(_ rewards: [RewardCheckpoint], in context: ModelContext) -> [RewardCheckpoint] {
        let builtIns = Dictionary(grouping: rewards.filter { !$0.isCustom && !$0.slug.isEmpty }, by: \.slug)
        guard builtIns.values.contains(where: { $0.count > 1 }) else { return rewards }

        let redemptions = (try? context.fetch(FetchDescriptor<RewardRedemption>())) ?? []
        var removed = Set<UUID>()
        for copies in builtIns.values where copies.count > 1 {
            let ordered = copies.sorted {
                $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
            }
            let keeper = ordered[0]
            for duplicate in ordered.dropFirst() {
                for redemption in redemptions where redemption.rewardID == duplicate.id {
                    redemption.rewardID = keeper.id
                }
                removed.insert(duplicate.id)
                context.delete(duplicate)
            }
        }
        return rewards.filter { !removed.contains($0.id) }
    }

    /// Icons offered when creating a custom reward.
    static let customIcons: [String] = [
        "gift.fill", "cup.and.saucer.fill", "birthday.cake.fill", "fork.knife",
        "gamecontroller.fill", "tv.fill", "film.fill", "music.note",
        "book.fill", "headphones", "paintpalette.fill", "bag.fill",
        "figure.walk", "bed.double.fill", "leaf.fill", "airplane",
    ]
}

/// Pure calculations for Leisure Points and checkpoints.
enum RewardMath {
    enum NextCheckpoint {
        /// A daily checkpoint has been reached today but not yet claimed.
        case claimable(RewardCheckpoint)
        /// Working toward a daily checkpoint; `progress` is today's XP.
        case daily(RewardCheckpoint, progress: Int)
        /// All daily checkpoints done; saving toward a shop reward.
        case shop(RewardCheckpoint, balance: Int)
        /// Every checkpoint claimed and every reward affordable.
        case allUnlocked
    }

    static func pointsSpent(_ redemptions: [RewardRedemption]) -> Int {
        redemptions.reduce(0) { $0 + $1.pointsSpent }
    }

    /// Spendable Leisure Points: lifetime XP (combo multipliers and ritual bonuses included)
    /// minus points spent in the shop and on crates, never below zero.
    static func balance(tasks: [TaskItem], redemptions: [RewardRedemption], events: [MomentumEvent] = []) -> Int {
        max(0, PlannerStats.totalXP(tasks, events: events) - pointsSpent(redemptions))
    }

    static func isClaimed(
        _ checkpoint: RewardCheckpoint,
        on day: Date = .now,
        redemptions: [RewardRedemption],
        calendar: Calendar = .current
    ) -> Bool {
        redemptions.contains { redemption in
            redemption.rewardID == checkpoint.id
                && redemption.kind == .dailyCheckpoint
                && calendar.isDate(redemption.redeemedAt, inSameDayAs: day)
        }
    }

    static func nextCheckpoint(
        checkpoints: [RewardCheckpoint],
        tasks: [TaskItem],
        redemptions: [RewardRedemption],
        events: [MomentumEvent] = [],
        now: Date = .now
    ) -> NextCheckpoint {
        let todayXP = PlannerStats.xpEarned(on: now, tasks: tasks, events: events)
        let dailies = checkpoints
            .filter { $0.kind == .dailyCheckpoint }
            .sorted { $0.cost < $1.cost }

        if let ready = dailies.first(where: { todayXP >= $0.cost && !isClaimed($0, on: now, redemptions: redemptions) }) {
            return .claimable(ready)
        }
        if let next = dailies.first(where: { todayXP < $0.cost }) {
            return .daily(next, progress: todayXP)
        }

        let balance = balance(tasks: tasks, redemptions: redemptions, events: events)
        let shop = checkpoints
            .filter { $0.kind == .shopReward }
            .sorted { $0.cost < $1.cost }
        if let next = shop.first(where: { $0.cost > balance }) {
            return .shop(next, balance: balance)
        }
        return .allUnlocked
    }
}

// MARK: - Mystery Loot Boxes

/// One possible prize in a crate. Every timed drop is at least 30 minutes.
struct LootDrop: Sendable, Identifiable, Equatable {
    let id: String
    let title: String
    let details: String
    let iconName: String
    /// `nil` for untimed passes (Skip a Chore, Takeout Night).
    let durationMinutes: Int?
    let rarity: PassRarity
    /// Relative chance, in percent.
    let weight: Int

    var breakMinutes: Int? { BreakPolicy.clamped(durationMinutes) }
}

/// A purchasable crate with a weighted loot table.
struct MysteryCrate: Sendable, Identifiable, Equatable {
    let id: String
    let title: String
    let tagline: String
    let iconName: String
    let cost: Int
    let colors: [Color]
    let drops: [LootDrop]

    /// Weighted random pick. Takes any generator so tests can use a seeded one.
    func roll<G: RandomNumberGenerator>(using generator: inout G) -> LootDrop {
        let total = drops.reduce(0) { $0 + $1.weight }
        var ticket = Int.random(in: 0..<max(total, 1), using: &generator)
        for drop in drops {
            if ticket < drop.weight { return drop }
            ticket -= drop.weight
        }
        return drops[drops.count - 1]
    }

    func roll() -> LootDrop {
        var generator = SystemRandomNumberGenerator()
        return roll(using: &generator)
    }

    static func == (lhs: MysteryCrate, rhs: MysteryCrate) -> Bool { lhs.id == rhs.id }
}

extension LootDrop {
    static let snackBreak = LootDrop(
        id: "snack_30", title: "30-Min Guilt-Free Snack & Recharge Break",
        details: "Coffee, tea or a favorite snack. Step away and recharge.",
        iconName: "cup.and.saucer.fill", durationMinutes: 30, rarity: .common, weight: 0
    )
    static let hobbyPass = LootDrop(
        id: "hobby_45", title: "45-Min Guilt-Free Hobby Pass",
        details: "Read, sketch, play or tinker. Pure hobby time.",
        iconName: "paintpalette.fill", durationMinutes: 45, rarity: .rare, weight: 0
    )
    static let gamingSession = LootDrop(
        id: "gaming_60", title: "1-Hour Gaming / Movie Session",
        details: "A full hour of games or a movie.",
        iconName: "gamecontroller.fill", durationMinutes: 60, rarity: .epic, weight: 0
    )
    static let deepRecharge = LootDrop(
        id: "recharge_90", title: "90-Min Deep Recharge Block",
        details: "A long, restorative break: nap, walk, bath, or nothing at all.",
        iconName: "battery.100percent.bolt", durationMinutes: 90, rarity: .legendary, weight: 0
    )
    static let skipChore = LootDrop(
        id: "skip_chore", title: "Skip a Chore Pass",
        details: "Skip one chore today, guilt-free. Someone else's turn (or tomorrow's).",
        iconName: "sparkles", durationMinutes: nil, rarity: .epic, weight: 0
    )
    static let takeoutNight = LootDrop(
        id: "takeout", title: "Takeout / Favorite Meal Night",
        details: "Skip cooking tonight. Order the good stuff.",
        iconName: "takeoutbag.and.cup.and.straw.fill", durationMinutes: nil, rarity: .legendary, weight: 0
    )

    func weighted(_ weight: Int) -> LootDrop {
        LootDrop(id: id, title: title, details: details, iconName: iconName,
                 durationMinutes: durationMinutes, rarity: rarity, weight: weight)
    }
}

extension MysteryCrate {
    static let momentum = MysteryCrate(
        id: "momentum_crate",
        title: "Momentum Mystery Crate",
        tagline: "A guaranteed break, 30 to 90 minutes.",
        iconName: "shippingbox.fill",
        cost: 45,
        colors: Theme.primaryColors,
        drops: [
            LootDrop.snackBreak.weighted(55),
            LootDrop.hobbyPass.weighted(25),
            LootDrop.gamingSession.weighted(15),
            LootDrop.deepRecharge.weighted(5),
        ]
    )

    static let obsidianJackpot = MysteryCrate(
        id: "obsidian_vault",
        title: "Obsidian Jackpot Vault",
        tagline: "Big breaks only, with a shot at Takeout Night.",
        iconName: "cube.transparent.fill",
        cost: 110,
        colors: Theme.legendaryColors,
        drops: [
            LootDrop.gamingSession.weighted(45),
            LootDrop.deepRecharge.weighted(30),
            LootDrop.skipChore.weighted(15),
            LootDrop.takeoutNight.weighted(10),
        ]
    )

    static let all: [MysteryCrate] = [.momentum, .obsidianJackpot]
}
