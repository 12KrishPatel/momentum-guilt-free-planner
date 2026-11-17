#if os(macOS)
import AppKit
#endif
import SwiftData
import SwiftUI

@main
struct MomentumApp: App {
    private let container: ModelContainer
    @State private var notificationManager: NotificationManager
    @State private var awardEngine: AwardEngine
    @State private var comboEngine: ComboEngine
    @State private var store: TaskStore
    #if os(macOS)
    @State private var navigation = AppNavigation()
    #endif

    init() {
        #if os(macOS)
        // Dark-first: force AppKit-backed chrome (sidebar, forms, menus) to match the theme.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        #endif
        #if DEBUG
        SharedModelContainer.initializeCloudKitSchemaIfRequested()
        #endif
        // One store shared with the widget extension through the App Group.
        let container = SharedModelContainer.makeAppContainer()
        SharedModelContainer.migrateDefaultsToAppGroup(keys: NotificationManager.persistedKeys)
        SharedModelContainer.observeExternalChanges()
        let notificationManager = NotificationManager()
        let awardEngine = AwardEngine()
        let comboEngine = ComboEngine()
        RewardCatalog.seedIfNeeded(in: container.mainContext)
        awardEngine.seedAwardsIfNeeded(in: container.mainContext)

        self.container = container
        _notificationManager = State(initialValue: notificationManager)
        _awardEngine = State(initialValue: awardEngine)
        _comboEngine = State(initialValue: comboEngine)
        let store = TaskStore(
            context: container.mainContext,
            awardEngine: awardEngine,
            notificationManager: notificationManager,
            comboEngine: comboEngine
        )
        store.refreshCombo()
        _store = State(initialValue: store)
        // Widget intents that the system runs inside this process use the live store.
        PlannerIntentActions.appStore = store
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if os(macOS)
                MacRootView(navigation: navigation)
                #else
                RootView()
                #endif
            }
            .environment(store)
            .environment(awardEngine)
            .environment(comboEngine)
            .environment(notificationManager)
            .tint(Theme.indigo)
            .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultSize(width: 1080, height: 740)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(navigation: navigation, store: store)
        }
        #endif
        .modelContainer(container)
    }
}

// MARK: - iOS shell

enum RootTab: Hashable {
    case plan
    case awards
    case profile
}

struct RootView: View {
    @State private var selectedTab: RootTab = .plan
    @State private var planRouter = PlanRouter()

    var body: some View {
        TabView(selection: $selectedTab) {
            PlanView()
                .tabItem { Label("Plan", systemImage: "checklist") }
                .tag(RootTab.plan)

            AwardsView()
                .tabItem { Label("Awards", systemImage: "trophy.fill") }
                .tag(RootTab.awards)

            StatsView()
                .tabItem { Label("Profile", systemImage: "chart.bar.xaxis") }
                .tag(RootTab.profile)
        }
        .environment(planRouter)
        .appLifecycle()
        // taskplanner://quick-add (Large widget's "New Task") → Plan › Today › Add Task sheet.
        .onOpenURL { url in
            guard DeepLink.isQuickAdd(url) else { return }
            selectedTab = .plan
            planRouter.pendingQuickAddEffort = DeepLink.effort(in: url)
            planRouter.pendingQuickAdd = true
        }
    }
}

// MARK: - Shared lifecycle

/// Behavior both shells share: the badge-unlock celebration, refreshing when the app becomes
/// active, and re-evaluating badges and reminders when tasks change from another device.
private struct AppLifecycleModifier: ViewModifier {
    @Environment(TaskStore.self) private var store
    @Environment(AwardEngine.self) private var awardEngine
    @Environment(\.scenePhase) private var scenePhase
    @Query private var tasks: [TaskItem]

    func body(content: Content) -> some View {
        content
            .overlay {
                if let unlock = awardEngine.presentedUnlock {
                    AwardUnlockedBanner(unlock: unlock) {
                        awardEngine.dismissPresentedUnlock()
                    }
                    .id(unlock.id)
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .sensoryFeedback(.success, trigger: awardEngine.celebrationCount)
            // The widget checked off or added a task in the shared store.
            .onReceive(NotificationCenter.default.publisher(for: .momentumStoreDidChangeExternally)) { _ in
                store.handleExternalChanges()
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    store.refresh()
                }
            }
            // Debounced: rapid local edits or a burst of iCloud imports trigger one refresh.
            .task(id: taskFingerprint) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                store.handleExternalChanges()
            }
    }

    /// Changes whenever any task is added, removed, renamed, rescheduled or (un)completed.
    private var taskFingerprint: Int {
        var hasher = Hasher()
        for task in tasks {
            hasher.combine(task.id)
            hasher.combine(task.title)
            hasher.combine(task.isCompleted)
            hasher.combine(task.scheduledDate)
            hasher.combine(task.effort)
            hasher.combine(task.archivedAt)
            hasher.combine(task.priorityRank)
        }
        return hasher.finalize()
    }
}

extension View {
    func appLifecycle() -> some View {
        modifier(AppLifecycleModifier())
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}
