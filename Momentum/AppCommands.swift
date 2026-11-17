#if os(macOS)
import Observation
import SwiftUI

/// Destinations in the macOS sidebar.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case today
    case week
    case upcoming
    case trophies
    case rewards
    case insights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "This Week"
        case .upcoming: "Upcoming / Backlog"
        case .trophies: "Trophy Case"
        case .rewards: "Leisure Rewards"
        case .insights: "Stats & Settings"
        }
    }

    var iconName: String {
        switch self {
        case .today: "sun.max.fill"
        case .week: "calendar"
        case .upcoming: "tray.full.fill"
        case .trophies: "trophy.fill"
        case .rewards: "gift.fill"
        case .insights: "chart.bar.xaxis"
        }
    }

    var tint: Color {
        switch self {
        case .today: Theme.amber
        case .week: Theme.indigo
        case .upcoming: Theme.cyan
        case .trophies: Theme.amber
        case .rewards: Theme.emerald
        case .insights: Theme.violet
        }
    }

    /// The Plan scope this item shows, if it is a task list.
    var planScope: PlanScope? {
        switch self {
        case .today: .today
        case .week: .week
        case .upcoming: .upcoming
        default: nil
        }
    }

    /// ⌘1 … ⌘6
    var shortcut: KeyEquivalent {
        switch self {
        case .today: "1"
        case .week: "2"
        case .upcoming: "3"
        case .trophies: "4"
        case .rewards: "5"
        case .insights: "6"
        }
    }
}

/// Window-level navigation state for the macOS desktop shell, shared with the menu bar commands.
@MainActor
@Observable
final class AppNavigation {
    var sidebarSelection: SidebarItem? = .today {
        didSet {
            if oldValue != sidebarSelection { selectedTaskID = nil }
        }
    }
    /// The task highlighted in the current list (target of ⌘↩ and the inspector).
    var selectedTaskID: UUID?
    var isInspectorPresented = true
    /// Set by ⌘N; the visible plan workspace focuses its quick-add field and clears it.
    var wantsQuickAddFocus = false
    /// Effort to pre-select in the quick-add bar (from a widget chip); consumed with the focus request.
    var pendingQuickAddEffort: EffortLevel?
    /// Ritual requested from the menu bar; the plan workspace presents it and clears this.
    var requestedRitual: RitualMode?

    func show(_ item: SidebarItem) {
        sidebarSelection = item
    }

    /// Jumps to a task list if needed (or always to Today), then focuses the quick-add field.
    func requestQuickAdd(inToday: Bool = false, effort: EffortLevel? = nil) {
        pendingQuickAddEffort = effort
        if inToday || sidebarSelection?.planScope == nil {
            sidebarSelection = .today
        }
        selectedTaskID = nil
        wantsQuickAddFocus = true
    }

    /// Opens a planning ritual over the Today workspace.
    func requestRitual(_ mode: RitualMode) {
        if sidebarSelection?.planScope == nil {
            sidebarSelection = .today
        }
        requestedRitual = mode
    }
}

/// Menu bar commands and keyboard shortcuts for the Mac app.
struct AppCommands: Commands {
    let navigation: AppNavigation
    let store: TaskStore

    var body: some Commands {
        // ⌘N replaces "New Window": a planner has one window and ⌘N should mean "new task".
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                navigation.requestQuickAdd()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Go") {
            ForEach(SidebarItem.allCases) { item in
                Button(item.title) {
                    navigation.show(item)
                }
                .keyboardShortcut(item.shortcut, modifiers: .command)

                if item == .upcoming || item == .rewards {
                    Divider()
                }
            }
        }

        CommandMenu("Rituals") {
            Button("Sunday Reset…") {
                navigation.requestRitual(.sundayReset)
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Button("Morning Kickoff…") {
                navigation.requestRitual(.morningKickoff)
            }
            .keyboardShortcut("k", modifiers: [.command, .option])
        }

        CommandMenu("Task") {
            Button("Toggle Completion") {
                withSelectedTask { store.toggleCompletion($0) }
            }
            .keyboardShortcut(.return, modifiers: .command)

            Button("Move to Tomorrow") {
                withSelectedTask { store.reschedule($0, byDaysFromToday: 1) }
            }

            Button("Move to Next Week") {
                withSelectedTask { store.reschedule($0, byDaysFromToday: 7) }
            }

            Button("Move to Someday") {
                withSelectedTask { store.reschedule($0, to: nil) }
            }

            Divider()

            // No shortcut on purpose: ⌘⌫ would fire while editing text in the quick-add field.
            Button("Delete Task") {
                withSelectedTask { store.delete($0) }
                navigation.selectedTaskID = nil
            }

            Divider()

            Button("Toggle Inspector") {
                withAnimation(Theme.spring) {
                    navigation.isInspectorPresented.toggle()
                }
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }

    private func withSelectedTask(_ action: (TaskItem) -> Void) {
        guard let id = navigation.selectedTaskID, let task = store.task(withID: id) else { return }
        withAnimation(Theme.spring) {
            action(task)
        }
    }
}
#endif
