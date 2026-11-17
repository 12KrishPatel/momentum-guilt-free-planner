import AppIntents
import Foundation
import SwiftData

// MARK: - Deep links

enum DeepLink {
    static let scheme = "taskplanner"
    /// Opens the app straight into task creation (iOS: Add Task sheet; macOS: quick-add bar).
    static let quickAddURL = URL(string: "taskplanner://quick-add")!

    /// Quick-add link that also pre-selects an effort level, e.g. `taskplanner://quick-add?effort=deepWork`.
    static func quickAddURL(effort: EffortLevel) -> URL {
        var components = URLComponents(url: quickAddURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "effort", value: effort.rawValue)]
        return components?.url ?? quickAddURL
    }

    static func isQuickAdd(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host()?.lowercased() == "quick-add"
    }

    /// The effort requested by a quick-add link, if any.
    static func effort(in url: URL) -> EffortLevel? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "effort" }?
            .value
            .flatMap(EffortLevel.init(rawValue:))
    }
}

// MARK: - Quick-add presets

/// One-tap task templates offered on the Large widget.
enum QuickAddPreset: String, AppEnum, CaseIterable, Identifiable, Sendable {
    case quickFocus
    case deepWork

    var id: String { rawValue }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Quick-Add Preset" }

    static var caseDisplayRepresentations: [QuickAddPreset: DisplayRepresentation] {
        [
            .quickFocus: DisplayRepresentation(title: "Quick Focus", subtitle: "10 XP"),
            .deepWork: DisplayRepresentation(title: "Deep Work Block", subtitle: "50 XP"),
        ]
    }

    /// Title of the task the preset creates.
    var taskTitle: String {
        switch self {
        case .quickFocus: "Quick focus sprint"
        case .deepWork: "Deep work block"
        }
    }

    /// Short label for the widget chip.
    var chipTitle: String {
        switch self {
        case .quickFocus: "Quick Focus"
        case .deepWork: "Deep Work"
        }
    }

    var effort: EffortLevel {
        switch self {
        case .quickFocus: .quick
        case .deepWork: .deepWork
        }
    }
}

// MARK: - Shared execution

/// Runs a widget action against the right store for the current process.
@MainActor
enum PlannerIntentActions {
    /// Set by the app at launch. When the system runs an intent inside the app's own process,
    /// the change goes through the live store and every open view updates immediately.
    static var appStore: TaskStore?

    /// In the widget extension: opens the shared store with a fresh context (so nothing cached
    /// from an earlier run is stale), applies `body` through `TaskStore` (which saves,
    /// re-evaluates badges, resyncs reminders and reloads widget timelines), then waits for
    /// the reminder resync before the extension is suspended.
    static func perform(_ body: (TaskStore) -> Void) async {
        if let appStore {
            body(appStore)
            return
        }
        guard let container = SharedModelContainer.widgetContainer() else { return }
        let notificationManager = NotificationManager()
        let store = TaskStore(
            context: ModelContext(container),
            awardEngine: AwardEngine(),
            notificationManager: notificationManager
        )
        body(store)
        await notificationManager.waitForPendingSync()
    }
}

// MARK: - Intents

/// Checks off (or re-opens) a task from a widget without launching the app.
struct ToggleTaskCompletionIntent: AppIntent {
    static var title: LocalizedStringResource { "Complete Task" }
    static var description: IntentDescription {
        IntentDescription("Marks a Momentum task complete, awarding its XP and Leisure Points.")
    }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Task ID")
    var taskID: String

    /// The completion state to apply. Setting a state (rather than flipping it) keeps a quick
    /// double tap on the widget from completing and then un-completing the task.
    @Parameter(title: "Completed", default: true)
    var markCompleted: Bool

    init() {}

    init(taskID: UUID, markCompleted: Bool = true) {
        self.taskID = taskID.uuidString
        self.markCompleted = markCompleted
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        let target = markCompleted
        await PlannerIntentActions.perform { store in
            guard let task = store.task(withID: id), task.isCompleted != target else { return }
            store.toggleCompletion(task)
        }
        return .result()
    }
}

/// Adds a preset task for today straight from the Large widget.
struct QuickAddPresetTaskIntent: AppIntent {
    static var title: LocalizedStringResource { "Quick-Add Task for Today" }
    static var description: IntentDescription {
        IntentDescription("Adds a preset Momentum task scheduled for today.")
    }

    @Parameter(title: "Preset", default: .quickFocus)
    var preset: QuickAddPreset

    init() {}

    init(preset: QuickAddPreset) {
        self.preset = preset
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let preset = preset
        await PlannerIntentActions.perform { store in
            store.addTask(title: preset.taskTitle, notes: "", scheduledDate: .now, effort: preset.effort)
        }
        return .result()
    }
}
