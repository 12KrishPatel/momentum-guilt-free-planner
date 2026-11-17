import Foundation
import Observation
import UserNotifications

/// A fully resolved reminder, ready to hand to `UNUserNotificationCenter`.
struct PlannedNotification: Sendable, Equatable {
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
}

/// Lets reminders show as banners while the app is in the foreground.
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@MainActor
@Observable
final class NotificationManager {
    nonisolated static let identifierPrefix = "momentum.reminder."
    /// iOS keeps at most 64 pending local notifications per app.
    nonisolated static let maximumPending = 60

    private enum Keys {
        static let slots = "reminders.slots"
        static let enabled = "reminders.enabled"
    }

    /// Settings keys, so they can be moved into the App Group defaults the widget reads.
    nonisolated static let persistedKeys = ["reminders.slots", "reminders.enabled"]

    /// User-configurable schedule, persisted as JSON in `UserDefaults`.
    var slots: [ReminderSlot] {
        didSet { persistSlots() }
    }

    /// Master switch for all daily reminders.
    var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: Keys.enabled) }
    }

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Number of reminders currently queued with the system.
    private(set) var scheduledCount = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let presenter = ForegroundNotificationPresenter()
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    /// Defaults to the App Group suite so the widget extension resyncs reminders with the
    /// user's schedule rather than the built-in one.
    init(defaults: UserDefaults = SharedModelContainer.sharedDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.slots),
           let stored = try? JSONDecoder().decode([ReminderSlot].self, from: data) {
            self.slots = stored
        } else {
            self.slots = ReminderSlot.defaultSchedule
        }
        self.remindersEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        UNUserNotificationCenter.current().delegate = presenter
    }

    var isAuthorized: Bool {
        Self.allowsDelivery(authorizationStatus)
    }

    /// `.ephemeral` (App Clips) only exists on iOS.
    nonisolated static func allowsDelivery(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional: return true
        #if os(iOS)
        case .ephemeral: return true
        #endif
        default: return false
        }
    }

    /// Sends the user to iOS Settings or macOS System Settings → Notifications
    /// (used when permission was denied).
    func openSystemNotificationSettings() {
        Platform.openNotificationSettings()
    }

    // MARK: Slot editing

    func addSlot() {
        slots.append(ReminderSlot(label: "Custom Reminder", hour: 18, minute: 0, onlyIfIncomplete: true))
    }

    func removeSlots(at offsets: IndexSet) {
        slots.remove(atOffsets: offsets)
    }

    func resetToDefaultSchedule() {
        slots = ReminderSlot.defaultSchedule
    }

    private func persistSlots() {
        guard let data = try? JSONEncoder().encode(slots) else { return }
        defaults.set(data, forKey: Keys.slots)
    }

    // MARK: Authorization

    func refreshAuthorizationStatus() async {
        authorizationStatus = await Self.currentAuthorizationStatus()
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = await Self.requestSystemAuthorization()
        await refreshAuthorizationStatus()
        return granted
    }

    // MARK: Synchronization

    /// Waits for the most recent resync to reach the system (used by widget intents, whose
    /// process may be suspended as soon as `perform()` returns).
    func waitForPendingSync() async {
        await syncTask?.value
    }

    /// Clears every app-managed pending reminder and reschedules the enabled slots
    /// for today and the next 7 days, with content generated from `tasks`.
    func syncNotifications(tasks: [TaskItem]) {
        let plan: [PlannedNotification]
        if remindersEnabled {
            plan = Self.buildPlan(slots: slots, tasks: tasks.map(TaskSnapshot.init), now: .now, calendar: .current)
        } else {
            plan = []
        }

        // Serialize syncs: the newest one waits for the (cancelled) previous one to unwind.
        let previous = syncTask
        previous?.cancel()
        syncTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            let scheduled = await Self.apply(plan, calendar: .current)
            guard !Task.isCancelled, let self else { return }
            self.scheduledCount = scheduled
            await self.refreshAuthorizationStatus()
        }
    }

    // MARK: Planning (pure)

    /// Builds the list of reminders to schedule from `now` through the end of `now + horizonDays`.
    nonisolated static func buildPlan(
        slots: [ReminderSlot],
        tasks: [TaskSnapshot],
        now: Date,
        calendar: Calendar,
        horizonDays: Int = 7
    ) -> [PlannedNotification] {
        let today = calendar.startOfDay(for: now)
        let enabledSlots = slots.filter(\.isEnabled)
        guard !enabledSlots.isEmpty else { return [] }

        var plan: [PlannedNotification] = []
        for offset in 0...horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let dayTasks = tasks
                .filter { task in
                    guard let scheduled = task.scheduledDate else { return false }
                    return calendar.isDate(scheduled, inSameDayAs: day)
                }
                .sorted { $0.createdAt < $1.createdAt }

            for slot in enabledSlots {
                guard
                    let fireDate = calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: day),
                    fireDate > now,
                    let body = body(for: slot, tasksForDay: dayTasks)
                else { continue }

                let stamp = calendar.dateComponents([.year, .month, .day], from: day)
                let identifier = String(
                    format: "%@%@.%04d%02d%02d",
                    identifierPrefix, slot.id.uuidString, stamp.year ?? 0, stamp.month ?? 0, stamp.day ?? 0
                )
                let title = slot.label.trimmingCharacters(in: .whitespacesAndNewlines)
                plan.append(PlannedNotification(
                    identifier: identifier,
                    title: title.isEmpty ? "Reminder" : title,
                    body: body,
                    fireDate: fireDate
                ))
            }
        }
        return Array(plan.sorted { $0.fireDate < $1.fireDate }.prefix(maximumPending))
    }

    /// Message for one slot on one day, or `nil` when the slot should stay silent.
    nonisolated static func body(for slot: ReminderSlot, tasksForDay: [TaskSnapshot]) -> String? {
        let remaining = tasksForDay.filter { !$0.isCompleted }

        if slot.onlyIfIncomplete {
            guard let highlight = remaining.max(by: { lhs, rhs in
                if lhs.effort.rank != rhs.effort.rank { return lhs.effort.rank < rhs.effort.rank }
                return lhs.createdAt > rhs.createdAt
            }) else { return nil }

            let xp = remaining.reduce(0) { $0 + $1.effort.points }
            if remaining.count == 1 {
                return "1 task remaining today: “\(highlight.title)”. Finish strong to earn \(xp) XP!"
            }
            return "\(remaining.count) tasks remaining today, including “\(highlight.title)”. Finish strong to earn \(xp) XP!"
        }

        let greeting: String
        switch slot.hour {
        case ..<12: greeting = "Good morning!"
        case ..<17: greeting = "Good afternoon!"
        default: greeting = "Good evening!"
        }

        guard !tasksForDay.isEmpty else {
            return "Your schedule is open today—tap to plan your priorities."
        }
        guard let first = remaining.first else {
            let noun = tasksForDay.count == 1 ? "The 1 task" : "All \(tasksForDay.count) tasks"
            return "\(greeting) \(noun) planned for today \(tasksForDay.count == 1 ? "is" : "are") already done—tap to line up what’s next."
        }
        if tasksForDay.count == 1 {
            return "\(greeting) You have 1 task planned today: “\(first.title)”."
        }
        return "\(greeting) You have \(tasksForDay.count) tasks planned today, starting with “\(first.title)”."
    }

    // MARK: System calls (off the main actor)

    /// Replaces all app-managed pending requests with `plan`. Returns how many were scheduled.
    nonisolated private static func apply(_ plan: [PlannedNotification], calendar: Calendar) async -> Int {
        let center = UNUserNotificationCenter.current()
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard !plan.isEmpty, !Task.isCancelled else { return 0 }
        guard allowsDelivery(await center.notificationSettings().authorizationStatus) else { return 0 }

        var scheduled = 0
        for item in plan {
            if Task.isCancelled { break }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
                scheduled += 1
            } catch {
                continue
            }
        }
        return scheduled
    }

    nonisolated private static func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    nonisolated private static func requestSystemAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}
