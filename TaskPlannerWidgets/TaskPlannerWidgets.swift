import SwiftUI
import WidgetKit

@main
struct TaskPlannerWidgets: WidgetBundle {
    var body: some Widget {
        FocusGlanceWidget()
        TodaysQueueWidget()
        CommandCenterWidget()
        #if os(iOS)
        BreakPassLiveActivity()
        #endif
    }
}

/// Small: progress ring, tasks left, streak and the next task.
struct FocusGlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MomentumFocusGlance", provider: TaskTimelineProvider()) { entry in
            PlannerWidgetView(entry: entry) { SmallWidgetView(snapshot: entry.snapshot) }
        }
        .configurationDisplayName("Focus Glance")
        .description("Today's progress, your streak and the next task to check off.")
        .supportedFamilies([.systemSmall])
    }
}

/// Medium: progress, XP and next checkpoint beside your next three tasks.
struct TodaysQueueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MomentumTodaysQueue", provider: TaskTimelineProvider()) { entry in
            PlannerWidgetView(entry: entry) { MediumWidgetView(snapshot: entry.snapshot) }
        }
        .configurationDisplayName("Today's Queue")
        .description("Check off your next three tasks and track today's XP and Leisure checkpoint.")
        .supportedFamilies([.systemMedium])
    }
}

/// Large: the full day plus one-tap quick add.
struct CommandCenterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MomentumCommandCenter", provider: TaskTimelineProvider()) { entry in
            PlannerWidgetView(entry: entry) { LargeWidgetView(snapshot: entry.snapshot, date: entry.date) }
        }
        .configurationDisplayName("Command Center")
        .description("Today's tasks with check-off buttons, points, streak and one-tap quick add.")
        .supportedFamilies([.systemLarge])
    }
}

/// Shared chrome: the obsidian container background and the disconnected state.
struct PlannerWidgetView<Content: View>: View {
    let entry: PlannerEntry
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if entry.snapshot.isConnected {
                content
            } else {
                WidgetDisconnectedView()
            }
        }
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) {
            WidgetBackground()
        }
    }
}
