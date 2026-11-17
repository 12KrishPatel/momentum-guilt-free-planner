import SwiftData
import SwiftUI

@main
struct MomentumApp: App {
    private let container: ModelContainer
    @State private var notificationManager: NotificationManager
    @State private var awardEngine: AwardEngine
    @State private var store: TaskStore

    init() {
        let container = Self.makeContainer()
        let notificationManager = NotificationManager()
        let awardEngine = AwardEngine()
        RewardCatalog.seedIfNeeded(in: container.mainContext)
        awardEngine.seedAwardsIfNeeded(in: container.mainContext)

        self.container = container
        _notificationManager = State(initialValue: notificationManager)
        _awardEngine = State(initialValue: awardEngine)
        _store = State(initialValue: TaskStore(
            context: container.mainContext,
            awardEngine: awardEngine,
            notificationManager: notificationManager
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(awardEngine)
                .environment(notificationManager)
                .tint(Theme.indigo)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }

    /// Opens the on-disk store (V1 stores migrate automatically), falling back to an
    /// in-memory store if it can't be loaded.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([TaskItem.self, Award.self, RewardCheckpoint.self, RewardRedemption.self])
        do {
            return try ModelContainer(for: schema)
        } catch {
            do {
                let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: configuration)
            } catch {
                fatalError("Unable to create a ModelContainer: \(error)")
            }
        }
    }
}

struct RootView: View {
    @Environment(TaskStore.self) private var store
    @Environment(AwardEngine.self) private var awardEngine
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            PlanView()
                .tabItem { Label("Plan", systemImage: "checklist") }

            AwardsView()
                .tabItem { Label("Awards", systemImage: "trophy.fill") }

            StatsView()
                .tabItem { Label("Profile", systemImage: "chart.bar.xaxis") }
        }
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
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                store.refresh()
            }
        }
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}
