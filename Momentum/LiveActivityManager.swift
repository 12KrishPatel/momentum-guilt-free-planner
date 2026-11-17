import Foundation
import OSLog
import UserNotifications
#if os(iOS)
import ActivityKit
#endif

/// Starts and ends break-timer Live Activities and the "break's over" alert.
///
/// iPhone: a Lock Screen / Dynamic Island countdown plus a local notification at `endTime`.
/// macOS has no Live Activities, so it only schedules the notification; the activity calls
/// are no-ops there.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private let logger = Logger(subsystem: "com.krishpatel.momentum", category: "LiveActivity")
    private init() {}

    /// Starts a break countdown of at least 30 minutes, replacing any running one.
    func startBreakActivity(passID: UUID = UUID(), title: String, iconName: String, durationMinutes: Int) {
        let minutes = max(BreakPolicy.minimumMinutes, durationMinutes)
        let start = Date.now
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        scheduleCompletionAlert(title: title, at: end)

        #if os(iOS)
        let state = BreakPassAttributes.ContentState(endTime: end, passTitle: title, iconName: iconName)
        let attributes = BreakPassAttributes(passID: passID.uuidString, startTime: start)
        Task {
            await endAllActivities()
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                logger.notice("Live Activities are turned off for Momentum; only the alert was scheduled.")
                return
            }
            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: end),
                    pushType: nil
                )
            } catch {
                logger.error("Live Activity request failed: \(error.localizedDescription)")
            }
        }
        #endif
    }

    /// "End Break Early": ends the countdown immediately and cancels the alert.
    func endBreakActivity() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.completionNotificationID]
        )
        #if os(iOS)
        Task { await endAllActivities() }
        #endif
    }

    /// Ends activities whose pass is no longer running (finished elsewhere, expired, or
    /// deleted), e.g. when the app returns to the foreground.
    func sync(with passes: [ActivePass], now: Date = .now) {
        #if os(iOS)
        let runningIDs = Set(passes.compactMap { pass -> String? in
            if case .running = pass.status(at: now) { return pass.id.uuidString }
            return nil
        })
        Task {
            for activity in Activity<BreakPassAttributes>.activities
            where !runningIDs.contains(activity.attributes.passID) || activity.content.state.endTime <= now {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }

    // MARK: Private

    private static var completionNotificationID: String {
        #if os(iOS)
        BreakPassAttributes.completionNotificationID
        #else
        "momentum.break.complete"
        #endif
    }

    private func scheduleCompletionAlert(title: String, at end: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Break complete"
        content.body = "Your “\(title)” pass is up. Ready to build some momentum?"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: Self.completionNotificationID, content: content, trigger: trigger)
        let logger = logger
        UNUserNotificationCenter.current().add(request) { error in
            if let error { logger.error("Break alert failed: \(error.localizedDescription)") }
        }
    }

    #if os(iOS)
    private func endAllActivities() async {
        for activity in Activity<BreakPassAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
    #endif
}
