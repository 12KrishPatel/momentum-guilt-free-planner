import Foundation
import SwiftData

/// Built-in real-world rewards seeded on first launch.
enum RewardCatalog {
    struct Seed: Sendable {
        let slug: String
        let title: String
        let details: String
        let iconName: String
        let cost: Int
        let kind: RewardKind
    }

    static let seeds: [Seed] = [
        // Daily checkpoints (free once today's XP reaches the threshold)
        Seed(
            slug: "daily_snack_break",
            title: "15-Min Guilt-Free Snack Break",
            details: "Step away for a coffee, tea, or favorite snack—no guilt attached.",
            iconName: "cup.and.saucer.fill",
            cost: 50,
            kind: .dailyCheckpoint
        ),
        Seed(
            slug: "daily_leisure_hour",
            title: "1 Hour of Guilt-Free Leisure",
            details: "Gaming, a show, or anything fun for a full hour—you earned it today.",
            iconName: "gamecontroller.fill",
            cost: 100,
            kind: .dailyCheckpoint
        ),

        // Rewards shop (spend Leisure Points)
        Seed(
            slug: "shop_treat",
            title: "Tasty Treat / Favorite Snack",
            details: "You earned a guilt-free snack or specialty coffee.",
            iconName: "birthday.cake.fill",
            cost: 50,
            kind: .shopReward
        ),
        Seed(
            slug: "shop_leisure_30",
            title: "30 Minutes of Guilt-Free Leisure",
            details: "Scroll, game, read, or watch a show completely guilt-free.",
            iconName: "tv.fill",
            cost: 75,
            kind: .shopReward
        ),
        Seed(
            slug: "shop_hobby_hour",
            title: "1 Hour Gaming / Hobby Session",
            details: "Uninterrupted personal hobby time earned through deep focus.",
            iconName: "paintpalette.fill",
            cost: 150,
            kind: .shopReward
        ),
        Seed(
            slug: "shop_takeout",
            title: "Takeout / Favorite Meal Night",
            details: "Skip cooking tonight—you crushed your week.",
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
            kind: .shopReward
        ),
    ]

    /// Inserts any built-in rewards that are missing (custom rewards are untouched).
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<RewardCheckpoint>())) ?? []
        let slugs = Set(existing.map(\.slug))
        for (index, seed) in seeds.enumerated() where !slugs.contains(seed.slug) {
            context.insert(RewardCheckpoint(
                slug: seed.slug,
                title: seed.title,
                details: seed.details,
                iconName: seed.iconName,
                cost: seed.cost,
                kind: seed.kind,
                isCustom: false,
                sortOrder: index
            ))
        }
        if context.hasChanges {
            try? context.save()
        }
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

    /// Spendable Leisure Points: lifetime XP minus points spent, never below zero.
    static func balance(tasks: [TaskItem], redemptions: [RewardRedemption]) -> Int {
        max(0, PlannerStats.totalXP(tasks) - pointsSpent(redemptions))
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
        now: Date = .now
    ) -> NextCheckpoint {
        let todayXP = PlannerStats.xpEarned(on: now, tasks: tasks)
        let dailies = checkpoints
            .filter { $0.kind == .dailyCheckpoint }
            .sorted { $0.cost < $1.cost }

        if let ready = dailies.first(where: { todayXP >= $0.cost && !isClaimed($0, on: now, redemptions: redemptions) }) {
            return .claimable(ready)
        }
        if let next = dailies.first(where: { todayXP < $0.cost }) {
            return .daily(next, progress: todayXP)
        }

        let balance = balance(tasks: tasks, redemptions: redemptions)
        let shop = checkpoints
            .filter { $0.kind == .shopReward }
            .sorted { $0.cost < $1.cost }
        if let next = shop.first(where: { $0.cost > balance }) {
            return .shop(next, balance: balance)
        }
        return .allUnlocked
    }
}
