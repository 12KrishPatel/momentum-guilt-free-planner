import Foundation
import Observation

// MARK: - Combo rules

/// Which bonus is boosting XP right now.
enum ComboKind: String, Sendable, Equatable {
    /// 2 completions within 45 minutes: 1.5x.
    case momentum
    /// 3+ completions inside the combo window: 2.0x.
    case overdrive
    /// Every task scheduled today done before 5 PM: 1.5x for the rest of the day.
    case earlyFinisher

    var title: String {
        switch self {
        case .momentum: "COMBO"
        case .overdrive: "OVERDRIVE"
        case .earlyFinisher: "EARLY FINISHER"
        }
    }
}

/// The multiplier in effect at a moment in time.
struct ComboStatus: Equatable, Sendable {
    var multiplier: Double
    var kind: ComboKind?
    /// Completions in the current chain (each within 45 minutes of the previous one).
    var chainCount: Int
    /// When the combo window closes (end of day for Early Finisher).
    var expiresAt: Date?

    static let inactive = ComboStatus(multiplier: 1, kind: nil, chainCount: 0, expiresAt: nil)

    var isActive: Bool { multiplier > 1 }

    /// "1.5x", "2x".
    var multiplierText: String { ComboMath.format(multiplier) }
}

/// What a single check-off earned, for the floating "+XP" pill.
struct CompletionReward: Identifiable, Equatable, Sendable {
    let id = UUID()
    let taskID: UUID
    let baseXP: Int
    let xp: Int
    let multiplier: Double
    let kind: ComboKind?
}

/// Pure combo math, shared by the app and the widget extension so a task checked off on the
/// Home Screen earns the same multiplier as one checked off in the app.
enum ComboMath {
    /// Rolling window from the last completed task.
    static let window: TimeInterval = 45 * 60
    /// Early Finisher requires the day's last task done before this hour (5 PM).
    static let earlyFinisherCutoffHour = 17
    static let earlyFinisherMultiplier = 1.5

    /// Multiplied XP, rounded to the nearest integer.
    static func apply(_ multiplier: Double, to points: Int) -> Int {
        Int((Double(points) * multiplier).rounded())
    }

    static func format(_ multiplier: Double) -> String {
        multiplier == multiplier.rounded() ? "\(Int(multiplier)).0x" : "\(multiplier)x"
    }

    /// 1 completion: 1.0x, 2 in a row: 1.5x (Momentum Combo), 3+: 2.0x (Overdrive).
    static func comboMultiplier(chainCount: Int) -> Double {
        switch chainCount {
        case 3...: 2.0
        case 2: 1.5
        default: 1.0
        }
    }

    static func comboKind(chainCount: Int) -> ComboKind? {
        switch chainCount {
        case 3...: .overdrive
        case 2: .momentum
        default: nil
        }
    }

    /// How many completions, newest first from `end`, are each within the window of the next.
    static func chainCount(endingAt end: Date, completions: [Date]) -> Int {
        var count = 0
        var cursor = end
        for date in completions.filter({ $0 <= end }).sorted(by: >) {
            guard cursor.timeIntervalSince(date) <= window else { break }
            count += 1
            cursor = date
        }
        return count
    }

    static func completionDates(_ tasks: [TaskItem]) -> [Date] {
        tasks.compactMap { $0.isCompleted ? $0.completedAt : nil }
    }

    /// True when every (non-archived) task scheduled today is done and the last one was
    /// finished before 5 PM.
    static func qualifiesForEarlyFinisher(tasks: [TaskItem], now: Date = .now, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        let todays = tasks.filter { $0.isScheduled(on: today, calendar: calendar) }
        guard !todays.isEmpty, todays.allSatisfy(\.isCompleted),
              let cutoff = calendar.date(bySettingHour: earlyFinisherCutoffHour, minute: 0, second: 0, of: today)
        else { return false }
        let lastFinish = todays.compactMap(\.completedAt).max() ?? now
        return lastFinish < cutoff && now < cutoff
    }

    static func hasEarlyFinisher(events: [MomentumEvent], on day: Date, calendar: Calendar = .current) -> Bool {
        events.contains { $0.kind == .earlyFinisher && calendar.isDate($0.occurredAt, inSameDayAs: day) }
    }

    /// The multiplier a completion at `date` earns. `completions` must include it.
    static func multiplier(
        forCompletionAt date: Date,
        completions: [Date],
        earlyFinisherActive: Bool
    ) -> (multiplier: Double, kind: ComboKind?) {
        let chain = chainCount(endingAt: date, completions: completions)
        let combo = comboMultiplier(chainCount: chain)
        if earlyFinisherActive, earlyFinisherMultiplier > combo {
            return (earlyFinisherMultiplier, .earlyFinisher)
        }
        return (combo, comboKind(chainCount: chain))
    }

    /// The bonus in effect at `now`.
    static func status(
        completions: [Date],
        earlyFinisherActive: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ComboStatus {
        var result = ComboStatus.inactive
        if let last = completions.filter({ $0 <= now }).max(), now.timeIntervalSince(last) <= window {
            let chain = chainCount(endingAt: last, completions: completions)
            if chain >= 2 {
                result = ComboStatus(
                    multiplier: comboMultiplier(chainCount: chain),
                    kind: comboKind(chainCount: chain),
                    chainCount: chain,
                    expiresAt: last.addingTimeInterval(window)
                )
            }
        }
        if earlyFinisherActive, earlyFinisherMultiplier > result.multiplier {
            let endOfDay = calendar.dayOffset(1, from: now)
            result = ComboStatus(
                multiplier: earlyFinisherMultiplier,
                kind: .earlyFinisher,
                chainCount: result.chainCount,
                expiresAt: endOfDay
            )
        }
        return result
    }
}

// MARK: - Observable engine

/// App-side combo state for the Plan header pill and the floating "+XP" burst. `TaskStore`
/// feeds it after every change; it re-evaluates on its own when a combo window closes.
@MainActor
@Observable
final class ComboEngine {
    /// Completion times from the last day, newest last.
    private(set) var recentCompletionTimestamps: [Date] = []
    /// 1.0, 1.5 or 2.0.
    private(set) var activeMultiplier: Double = 1
    /// When the 45-minute window from the last completion closes (end of day for Early Finisher).
    private(set) var comboExpiresAt: Date?
    private(set) var status: ComboStatus = .inactive
    private(set) var isEarlyFinisherActive = false
    /// The most recent check-off's reward; changes drive the "+XP" animation.
    private(set) var lastReward: CompletionReward?

    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    init() {}

    /// Re-reads combo inputs from the store's data.
    func refresh(tasks: [TaskItem], events: [MomentumEvent], now: Date = .now) {
        let dayAgo = now.addingTimeInterval(-24 * 60 * 60)
        recentCompletionTimestamps = ComboMath.completionDates(tasks).filter { $0 >= dayAgo }.sorted()
        isEarlyFinisherActive = ComboMath.hasEarlyFinisher(events: events, on: now)
        recompute(now: now)
    }

    func register(_ reward: CompletionReward) {
        lastReward = reward
    }

    private func recompute(now: Date = .now) {
        let next = ComboMath.status(
            completions: recentCompletionTimestamps,
            earlyFinisherActive: isEarlyFinisherActive,
            now: now
        )
        if next != status { status = next }
        if activeMultiplier != next.multiplier { activeMultiplier = next.multiplier }
        if comboExpiresAt != next.expiresAt { comboExpiresAt = next.expiresAt }
        scheduleExpiry(next.expiresAt)
    }

    /// Drops the multiplier the moment the window closes, even if nothing else changes.
    private func scheduleExpiry(_ date: Date?) {
        expiryTask?.cancel()
        guard let date else { return }
        let delay = max(0, date.timeIntervalSinceNow) + 0.5
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.recompute()
        }
    }
}
