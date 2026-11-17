#if os(iOS)
import ActivityKit
import AppIntents
import Foundation
import UserNotifications

/// Live Activity for a running Guilt-Free Pass break timer (Lock Screen + Dynamic Island).
/// Compiled into both the app (which starts it) and the widget extension (which draws it).
struct BreakPassAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endTime: Date
        var passTitle: String
        var iconName: String
    }

    /// The `ActivePass` this timer belongs to, so "End Early" can mark it used.
    var passID: String
    /// When the break started; with `endTime` it drives the progress bar.
    var startTime: Date
}

extension BreakPassAttributes {
    /// Identifier of the local "break's over" notification.
    static let completionNotificationID = "momentum.break.complete"
}

/// The Dynamic Island / Lock Screen "End Early" button. Runs in the app's process (as a
/// `LiveActivityIntent`), so the pass is marked used in the live store.
struct EndBreakEarlyIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "End Break Early" }
    static var description: IntentDescription { IntentDescription("Ends the running Guilt-Free Pass timer.") }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Pass ID")
    var passID: String

    init() {}

    init(passID: String) {
        self.passID = passID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: passID) {
            await PlannerIntentActions.perform { store in store.finishPass(id: id) }
        }
        // End the activity even if the store wasn't reachable, so the island never gets stuck.
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [BreakPassAttributes.completionNotificationID]
        )
        for activity in Activity<BreakPassAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}
#endif
