#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

// MARK: - Desktop shell

/// macOS layout: a sidebar of destinations and a detail workspace. Plan destinations add a
/// trailing inspector for inline task creation and editing.
struct MacRootView: View {
    @Bindable var navigation: AppNavigation

    var body: some View {
        NavigationSplitView {
            MacSidebar(navigation: navigation)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            detail
                .id(navigation.sidebarSelection)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, minHeight: 580)
        .background(Theme.background.ignoresSafeArea())
        .appLifecycle()
        // taskplanner://quick-add (Large widget's "New Task"): bring the window forward,
        // switch to Today and focus the quick-add field. Routed to this window rather than
        // opening a new one.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL { url in
            guard DeepLink.isQuickAdd(url) else { return }
            NSApp.activate()
            if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            }
            navigation.requestQuickAdd(inToday: true, effort: DeepLink.effort(in: url))
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.sidebarSelection ?? .today {
        case .today: MacPlanWorkspace(scope: .today, navigation: navigation)
        case .week: MacPlanWorkspace(scope: .week, navigation: navigation)
        case .upcoming: MacPlanWorkspace(scope: .upcoming, navigation: navigation)
        case .trophies: AwardsView(fixedTab: .badges)
        case .rewards: AwardsView(fixedTab: .rewards)
        case .insights: StatsView()
        }
    }
}

// MARK: - Sidebar

struct MacSidebar: View {
    @Bindable var navigation: AppNavigation
    @Query private var tasks: [TaskItem]
    @Query private var awards: [Award]
    @Query private var redemptions: [RewardRedemption]
    @Query private var events: [MomentumEvent]

    var body: some View {
        let plan = PlanModel(tasks: tasks)

        List(selection: $navigation.sidebarSelection) {
            Section("Plan") {
                row(.today, count: plan.remainingCount(for: .today))
                row(.week, count: plan.remainingCount(for: .week))
                row(.upcoming, count: plan.remainingCount(for: .upcoming))
            }
            Section("Gamification") {
                row(.trophies, badgeText: "\(awards.count(where: \.isUnlocked))/\(awards.count)")
                row(.rewards, count: 0)
            }
            Section("Insights") {
                row(.insights, count: 0)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.obsidianTop.opacity(0.55))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter(
                points: RewardMath.balance(tasks: tasks, redemptions: redemptions, events: events),
                lifetimeXP: PlannerStats.totalXP(tasks, events: events),
                streak: PlannerStats.currentStreak(tasks)
            )
        }
    }

    private func row(_ item: SidebarItem, count: Int) -> some View {
        Label {
            Text(item.title)
        } icon: {
            Image(systemName: item.iconName)
                .foregroundStyle(item.tint)
        }
        .badge(count)
        .tag(item)
    }

    private func row(_ item: SidebarItem, badgeText: String) -> some View {
        Label {
            Text(item.title)
        } icon: {
            Image(systemName: item.iconName)
                .foregroundStyle(item.tint)
        }
        .badge(Text(badgeText))
        .tag(item)
    }
}

/// Glass card pinned to the bottom of the sidebar: spendable points, lifetime XP, streak.
struct SidebarFooter: View {
    let points: Int
    let lifetimeXP: Int
    let streak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                GradientIcon(systemName: "leaf.fill", colors: Theme.successColors, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(points)")
                        .font(Theme.rounded(.title2, weight: .heavy))
                        .foregroundStyle(Theme.successGradient)
                        .contentTransition(.numericText(value: Double(points)))
                    Text("Available Leisure Points")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: 6) {
                StatPill(icon: "star.fill", value: lifetimeXP, unit: "XP")
                StatPill(icon: "flame.fill", value: streak, unit: streak == 1 ? "day" : "days", colors: Theme.legendaryColors)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(cornerRadius: 16)
        .padding(12)
        .animation(Theme.spring, value: points)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Plan workspace

/// A section of task rows in the Mac workspace.
private struct TaskSection: Identifiable {
    let id: String
    let title: String
    var tint: Color = Theme.textSecondary
    let tasks: [TaskItem]
    var showsDate = false
    let emptyIcon: String
    let emptyTitle: String
    let emptyMessage: String
}

struct MacPlanWorkspace: View {
    let scope: PlanScope
    @Bindable var navigation: AppNavigation

    @Environment(TaskStore.self) private var store
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @Query(sort: \RewardCheckpoint.cost) private var rewards: [RewardCheckpoint]
    @Query private var redemptions: [RewardRedemption]
    @Query private var events: [MomentumEvent]
    @Environment(ComboEngine.self) private var combo: ComboEngine?

    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var activeRitual: RitualMode?
    @State private var quickAddTitle = ""
    @State private var quickAddEffort: EffortLevel = .standard
    @State private var presentedPass: RewardRedemption?
    @FocusState private var isQuickAddFocused: Bool
    @FocusState private var isListFocused: Bool

    private var plan: PlanModel { PlanModel(tasks: tasks) }

    private var selectedTask: TaskItem? {
        guard let id = navigation.selectedTaskID else { return nil }
        return tasks.first { $0.id == id }
    }

    /// Date given to tasks created from this view.
    private var defaultDate: Date? {
        switch scope {
        case .today: plan.today
        case .week: selectedDay
        case .upcoming: nil
        }
    }

    private var sections: [TaskSection] {
        let calendar = Calendar.current
        switch scope {
        case .today:
            var result: [TaskSection] = []
            let overdue = plan.overdue
            if !overdue.isEmpty {
                result.append(TaskSection(
                    id: "overdue", title: "Overdue", tint: Theme.rose, tasks: overdue,
                    emptyIcon: "", emptyTitle: "", emptyMessage: ""
                ))
            }
            result.append(TaskSection(
                id: "today", title: plan.today.formatted(.dateTime.weekday(.wide).month().day()),
                tasks: plan.tasks(on: plan.today),
                emptyIcon: "sun.max", emptyTitle: "Nothing planned today",
                emptyMessage: "Type above and press Return to add your first priority."
            ))
            return result
        case .week:
            return [TaskSection(
                id: "day",
                title: calendar.isDateInToday(selectedDay) ? "Today" : selectedDay.formatted(.dateTime.weekday(.wide).month().day()),
                tasks: plan.tasks(on: selectedDay),
                emptyIcon: "calendar.badge.plus", emptyTitle: "Open day",
                emptyMessage: "Plan ahead—add something for this day above."
            )]
        case .upcoming:
            return [
                TaskSection(
                    id: "later", title: "Later", tasks: plan.later, showsDate: true,
                    emptyIcon: "calendar", emptyTitle: "Nothing beyond this week",
                    emptyMessage: "Tasks scheduled more than 7 days out appear here."
                ),
                TaskSection(
                    id: "someday", title: "Someday", tasks: plan.someday,
                    emptyIcon: "tray", emptyTitle: "Backlog is empty",
                    emptyMessage: "Anything added here has no date yet."
                ),
            ]
        }
    }

    private var visibleTasks: [TaskItem] { sections.flatMap(\.tasks) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if scope == .today {
                    RitualPromptSlot { mode in activeRitual = mode }
                }

                ProgressHeaderCard(
                    title: scope == .today ? "Today's Progress" : "This Week's Progress",
                    completed: progressTasks.count(where: \.isCompleted),
                    total: progressTasks.count,
                    totalXP: PlannerStats.totalXP(tasks, events: events),
                    points: RewardMath.balance(tasks: tasks, redemptions: redemptions, events: events),
                    streak: PlannerStats.currentStreak(tasks)
                )

                NextCheckpointBar(
                    status: RewardMath.nextCheckpoint(checkpoints: rewards, tasks: tasks, redemptions: redemptions, events: events)
                ) { checkpoint in
                    if let pass = store.claimDailyCheckpoint(checkpoint) {
                        presentedPass = pass
                    }
                }

                quickAddBar

                if scope == .week {
                    WeekStripView(days: plan.weekDays, selection: $selectedDay, summaries: plan.weekSummaries)
                }

                ForEach(sections) { section in
                    sectionView(section)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .xpBurstOverlay()
        .focusable()
        .focused($isListFocused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
        .onKeyPress(.escape) {
            guard navigation.selectedTaskID != nil else { return .ignored }
            navigation.selectedTaskID = nil
            return .handled
        }
        .inspector(isPresented: $navigation.isInspectorPresented) {
            TaskInspector(task: selectedTask, defaultDate: defaultDate, scope: scope)
                .id(inspectorIdentity)
                .inspectorColumnWidth(min: 290, ideal: 330, max: 440)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    RitualMenuItems { mode in activeRitual = mode }
                } label: {
                    Label("Rituals", systemImage: "rectangle.stack.fill")
                }
                .help("Sunday Reset (⌥⌘R) or Morning Kickoff (⌥⌘K)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(Theme.spring) { navigation.isInspectorPresented.toggle() }
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the task inspector (⌥⌘I)")
            }
        }
        .sheet(item: $presentedPass) { pass in
            GuiltFreePassView(redemption: pass)
        }
        .sheet(item: $activeRitual) { mode in
            RitualFlowView(mode: mode)
        }
        .onChange(of: navigation.requestedRitual, initial: true) { _, mode in
            guard let mode else { return }
            navigation.requestedRitual = nil
            activeRitual = mode
        }
        .onChange(of: navigation.wantsQuickAddFocus, initial: true) { _, wantsFocus in
            guard wantsFocus else { return }
            navigation.wantsQuickAddFocus = false
            if let effort = navigation.pendingQuickAddEffort {
                quickAddEffort = effort
                navigation.pendingQuickAddEffort = nil
            }
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                isQuickAddFocused = true
            }
        }
        .onChange(of: tasks.map(\.id)) { _, ids in
            if let selected = navigation.selectedTaskID, !ids.contains(selected) {
                navigation.selectedTaskID = nil
            }
        }
    }

    private var progressTasks: [TaskItem] {
        scope == .today ? plan.tasks(on: plan.today) : plan.weekTasks
    }

    private var inspectorIdentity: String {
        let taskPart = navigation.selectedTaskID?.uuidString ?? "new"
        let datePart = defaultDate.map { String($0.timeIntervalSince1970) } ?? "someday"
        return "\(taskPart)-\(datePart)"
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scope == .upcoming ? "Upcoming" : scope.rawValue)
                    .font(Theme.rounded(size: 32, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if (combo?.activeMultiplier ?? 1) > 1 {
                ComboBadgeSlot()
                    .padding(.trailing, 6)
            }
            let remaining = plan.remainingCount(for: scope)
            Text(remaining == 1 ? "1 open task" : "\(remaining) open tasks")
                .font(Theme.rounded(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText(value: Double(remaining)))
        }
    }

    private var subtitle: String {
        switch scope {
        case .today: plan.today.formatted(.dateTime.weekday(.wide).month(.wide).day())
        case .week: "Next 7 days"
        case .upcoming: "More than a week out, plus your Someday backlog"
        }
    }

    // MARK: Quick add

    private var quickAddPlaceholder: String {
        switch scope {
        case .today: "Add a task for today…"
        case .week:
            Calendar.current.isDateInToday(selectedDay)
                ? "Add a task for today…"
                : "Add a task for \(selectedDay.formatted(.dateTime.weekday(.wide)))…"
        case .upcoming: "Add to your Someday backlog…"
        }
    }

    private var quickAddBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.primaryGradient)

            TextField(quickAddPlaceholder, text: $quickAddTitle)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isQuickAddFocused)
                .onSubmit(addQuickTask)

            Menu {
                ForEach(EffortLevel.allCases) { level in
                    Button {
                        quickAddEffort = level
                    } label: {
                        Label("\(level.label) · \(level.points) XP", systemImage: level.iconName)
                    }
                }
            } label: {
                EffortBadge(effort: quickAddEffort)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Effort for new tasks")

            Text("⌘N")
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.chipBackground, in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassCard(cornerRadius: 14)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.primaryGradient, lineWidth: 1.5)
                .opacity(isQuickAddFocused ? 0.9 : 0)
        }
        .animation(.easeOut(duration: 0.15), value: isQuickAddFocused)
    }

    private func addQuickTask() {
        let title = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        withAnimation(Theme.spring) {
            store.addTask(title: title, notes: "", scheduledDate: defaultDate, effort: quickAddEffort)
        }
        quickAddTitle = ""
        isQuickAddFocused = true
    }

    // MARK: Sections

    private func sectionView(_ section: TaskSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(section.title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(section.tint == Theme.textSecondary ? Theme.textSecondary : section.tint)
                Spacer()
                let open = section.tasks.count { !$0.isCompleted }
                if open > 0 {
                    Text("\(open) open")
                        .font(Theme.rounded(.caption, weight: .semibold))
                        .foregroundStyle(section.tint)
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 2) {
                if section.tasks.isEmpty {
                    EmptyStateRow(icon: section.emptyIcon, title: section.emptyTitle, message: section.emptyMessage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                } else {
                    ForEach(section.tasks) { task in
                        MacTaskRow(
                            task: task,
                            showsDate: section.showsDate,
                            isSelected: navigation.selectedTaskID == task.id
                        ) {
                            navigation.selectedTaskID = task.id
                            isListFocused = true
                        }
                    }
                }
            }
            .padding(6)
            .glassCard(cornerRadius: 18)
        }
    }

    // MARK: Keyboard

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        let ids = visibleTasks.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let next: Int
        if let current = navigation.selectedTaskID, let index = ids.firstIndex(of: current) {
            next = min(max(index + offset, 0), ids.count - 1)
        } else {
            next = offset > 0 ? 0 : ids.count - 1
        }
        navigation.selectedTaskID = ids[next]
        return .handled
    }
}

// MARK: - Row

/// Task row with hover and selection highlights, quick-complete checkbox and right-click menu.
struct MacTaskRow: View {
    let task: TaskItem
    let showsDate: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(TaskStore.self) private var store
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        TaskRowView(
            task: task,
            showsDate: showsDate,
            onToggle: {
                withAnimation(Theme.spring) { store.toggleCompletion(task) }
            },
            onOpen: onSelect
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                shape.fill(Theme.indigo.opacity(0.22))
                    .overlay(shape.strokeBorder(Theme.primaryGradient, lineWidth: 1).opacity(0.8))
            } else if isHovered {
                shape.fill(Color.white.opacity(0.055))
            }
        }
        .contentShape(shape)
        .macHover { isHovered = $0 }
        .contextMenu {
            TaskContextMenuItems(task: task)
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

// MARK: - Inspector

/// Trailing inspector: edits the selected task inline, or creates a new one when nothing is selected.
struct TaskInspector: View {
    let task: TaskItem?
    let scope: PlanScope

    @Environment(TaskStore.self) private var store
    @State private var draft: TaskDraft
    @FocusState private var isTitleFocused: Bool
    private let defaultDate: Date?

    init(task: TaskItem?, defaultDate: Date?, scope: PlanScope) {
        self.task = task
        self.scope = scope
        self.defaultDate = defaultDate
        _draft = State(initialValue: task.map(TaskDraft.init(task:)) ?? TaskDraft(defaultDate: defaultDate))
    }

    private var hasChanges: Bool {
        guard let task else { return false }
        return draft.differs(from: task)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    GradientIcon(
                        systemName: task == nil ? "plus" : "square.and.pencil",
                        colors: task == nil ? Theme.primaryColors : Theme.successColors,
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task == nil ? "New Task" : "Edit Task")
                            .font(Theme.rounded(.title3))
                            .foregroundStyle(Theme.textPrimary)
                        Text(task == nil ? "Fill in the details, then press Return." : "Changes apply when you save (⌘S).")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 4)

                if let task {
                    Button {
                        withAnimation(Theme.spring) { store.toggleCompletion(task) }
                    } label: {
                        HStack(spacing: 10) {
                            AnimatedCheckbox(isOn: task.isCompleted, tint: task.effort.tint, size: 22)
                            Text(completionText(for: task))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(task.isCompleted ? Theme.emerald : Theme.textPrimary)
                            Spacer()
                            Text("⌘↩")
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .glassRow()

            TaskEditorFields(draft: $draft, titleFocus: $isTitleFocused, onSubmitTitle: primaryAction)

            Section {
                if let task {
                    actionButton("Save Changes", systemImage: "checkmark", colors: Theme.primaryColors, isEnabled: draft.isValid && hasChanges) {
                        primaryAction()
                    }
                    .keyboardShortcut("s", modifiers: .command)

                    HStack {
                        Button("Revert") { draft = TaskDraft(task: task) }
                            .disabled(!hasChanges)
                        Spacer()
                        Button("Delete Task", role: .destructive) {
                            withAnimation(Theme.spring) { store.delete(task) }
                        }
                        .foregroundStyle(Theme.rose)
                    }
                    .buttonStyle(.borderless)
                } else {
                    actionButton("Add Task", systemImage: "plus", colors: Theme.primaryColors, isEnabled: draft.isValid) {
                        primaryAction()
                    }
                }
            }
            .glassRow()
        }
        .formStyle(.grouped)
        .themedScreen()
    }

    private func completionText(for task: TaskItem) -> String {
        if task.isCompleted, let completedAt = task.completedAt {
            return "Completed \(completedAt.formatted(date: .omitted, time: .shortened))"
        }
        return "Mark complete · +\(task.effort.points) XP"
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        colors: [Color],
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Theme.rounded(.headline))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Theme.diagonal(colors), in: Capsule())
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func primaryAction() {
        guard draft.isValid else { return }
        if let task {
            guard hasChanges else { return }
            store.update(task, title: draft.title, notes: draft.notes, scheduledDate: draft.resolvedDate, effort: draft.effort)
            draft = TaskDraft(task: task)
        } else {
            withAnimation(Theme.spring) {
                store.addTask(title: draft.title, notes: draft.notes, scheduledDate: draft.resolvedDate, effort: draft.effort)
            }
            draft = TaskDraft(defaultDate: defaultDate)
            isTitleFocused = true
        }
    }
}

#Preview("Mac shell") {
    MacRootView(navigation: AppNavigation())
        .previewEnvironment()
        .frame(width: 1080, height: 740)
}
#endif
