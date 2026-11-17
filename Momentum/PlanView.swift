import SwiftData
import SwiftUI

enum PlanScope: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "This Week"
    case upcoming = "Upcoming"

    var id: String { rawValue }
}

/// Requests routed into the Plan tab from outside it (e.g. a widget deep link).
@MainActor
@Observable
final class PlanRouter {
    /// Set to open Today with the Add Task sheet; PlanView clears it once handled.
    var pendingQuickAdd = false
    /// Effort to pre-select in that sheet (from a widget chip).
    var pendingQuickAddEffort: EffortLevel?
}

struct PlanView: View {
    @Environment(PlanRouter.self) private var router: PlanRouter?
    @Environment(TaskStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @Query(sort: \RewardCheckpoint.cost) private var rewards: [RewardCheckpoint]
    @Query private var redemptions: [RewardRedemption]
    @Query private var events: [MomentumEvent]
    @Environment(ComboEngine.self) private var combo: ComboEngine?

    @State private var scope: PlanScope = .today
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var isAddingTask = false
    /// Effort pre-selected by a widget deep link for the next Add Task sheet.
    @State private var newTaskEffort: EffortLevel = .standard
    @State private var editingTask: TaskItem?
    @State private var reschedulingTask: TaskItem?
    @State private var presentedPass: RewardRedemption?
    @State private var activeRitual: RitualMode?

    private var calendar: Calendar { .current }
    private var plan: PlanModel { PlanModel(tasks: tasks) }
    private var today: Date { plan.today }
    private var weekDays: [Date] { plan.weekDays }
    private var weekEnd: Date { plan.weekEnd }
    private var overdueTasks: [TaskItem] { plan.overdue }
    private func tasks(on day: Date) -> [TaskItem] { plan.tasks(on: day) }
    private var weekTasks: [TaskItem] { plan.weekTasks }
    private var laterTasks: [TaskItem] { plan.later }
    private var somedayTasks: [TaskItem] { plan.someday }
    private var weekSummaries: [Date: DaySummary] { plan.weekSummaries }

    /// Deep link from the widget: show Today and open the Add Task sheet, closing any other
    /// sheet first (SwiftUI presents one sheet at a time).
    private func openQuickAdd(effort: EffortLevel?) {
        let hadOtherSheet = editingTask != nil || reschedulingTask != nil || presentedPass != nil || activeRitual != nil
        editingTask = nil
        reschedulingTask = nil
        presentedPass = nil
        activeRitual = nil
        scope = .today
        selectedDay = today
        guard !isAddingTask else { return }
        newTaskEffort = effort ?? .standard
        Task {
            if hadOtherSheet {
                try? await Task.sleep(for: .milliseconds(450))
            }
            isAddingTask = true
        }
    }

    private var defaultDateForNewTask: Date? {
        switch scope {
        case .today: today
        case .week: selectedDay
        case .upcoming: nil
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("View", selection: $scope) {
                        ForEach(PlanScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)

                    RitualPromptSlot { mode in activeRitual = mode }

                    if (combo?.activeMultiplier ?? 1) > 1 {
                        HStack {
                            ComboBadgeSlot()
                            Spacer(minLength: 0)
                        }
                        // Room for the glow, which the list row would otherwise clip.
                        .padding(.vertical, 14)
                        .padding(.horizontal, 6)
                    }

                    headerCard

                    NextCheckpointBar(
                        status: RewardMath.nextCheckpoint(checkpoints: rewards, tasks: tasks, redemptions: redemptions, events: events)
                    ) { checkpoint in
                        if let pass = store.claimDailyCheckpoint(checkpoint) {
                            presentedPass = pass
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .animation(Theme.spring, value: combo?.activeMultiplier)

                switch scope {
                case .today: todaySections
                case .week: weekSections
                case .upcoming: upcomingSections
                }
            }
            .groupedListStyle()
            .themedScreen()
            .contentMargins(.bottom, 96, for: .scrollContent)
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section("Rituals") {
                            RitualMenuItems { mode in activeRitual = mode }
                        }
                    } label: {
                        Label("Rituals", systemImage: "rectangle.stack.fill")
                    }
                }
            }
            .xpBurstOverlay()
            .overlay(alignment: .bottomTrailing) { addButton }
            .sheet(isPresented: $isAddingTask, onDismiss: { newTaskEffort = .standard }) {
                AddTaskSheet(defaultDate: defaultDateForNewTask, effort: newTaskEffort)
            }
            .sheet(item: $editingTask) { task in
                AddTaskSheet(editing: task)
            }
            .sheet(item: $reschedulingTask) { task in
                RescheduleSheet(task: task)
            }
            .sheet(item: $presentedPass) { pass in
                GuiltFreePassView(redemption: pass)
            }
            .sheet(item: $activeRitual) { mode in
                RitualFlowView(mode: mode)
            }
            .sensoryFeedback(.selection, trigger: scope)
            .onChange(of: router?.pendingQuickAdd ?? false, initial: true) { _, isPending in
                guard isPending else { return }
                router?.pendingQuickAdd = false
                openQuickAdd(effort: router?.pendingQuickAddEffort)
                router?.pendingQuickAddEffort = nil
            }
            .onChange(of: scenePhase) { _, phase in
                // After a day rollover the strip's old selection may no longer be in range.
                if phase == .active, selectedDay < today || selectedDay >= weekEnd {
                    selectedDay = today
                }
            }
        }
    }

    // MARK: Header

    private var headerCard: some View {
        let scoped = scope == .today ? tasks(on: today) : weekTasks
        return ProgressHeaderCard(
            title: scope == .today ? "Today's Progress" : "This Week's Progress",
            completed: scoped.count(where: \.isCompleted),
            total: scoped.count,
            totalXP: PlannerStats.totalXP(tasks, events: events),
            points: RewardMath.balance(tasks: tasks, redemptions: redemptions, events: events),
            streak: PlannerStats.currentStreak(tasks)
        )
    }

    // MARK: Sections

    @ViewBuilder
    private var todaySections: some View {
        let overdue = overdueTasks
        let todays = tasks(on: today)

        if !overdue.isEmpty {
            Section {
                taskRows(overdue)
            } header: {
                sectionHeader("Overdue", count: overdue.count, tint: Theme.rose)
            }
            .glassRow()
        }

        Section {
            if todays.isEmpty {
                EmptyStateRow(
                    icon: "sun.max",
                    title: "Nothing planned today",
                    message: "Tap + to add your first priority."
                )
            } else {
                taskRows(todays)
            }
        } header: {
            sectionHeader(today.formatted(.dateTime.weekday(.wide).month().day()), count: todays.count(where: { !$0.isCompleted }))
        }
        .glassRow()
    }

    @ViewBuilder
    private var weekSections: some View {
        let dayTasks = tasks(on: selectedDay)

        Section {
            WeekStripView(days: weekDays, selection: $selectedDay, summaries: weekSummaries)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

        Section {
            if dayTasks.isEmpty {
                EmptyStateRow(
                    icon: "calendar.badge.plus",
                    title: "Open day",
                    message: "Plan ahead—tap + to schedule something here."
                )
            } else {
                taskRows(dayTasks)
            }
        } header: {
            sectionHeader(
                calendar.isDateInToday(selectedDay)
                    ? "Today"
                    : selectedDay.formatted(.dateTime.weekday(.wide).month().day()),
                count: dayTasks.count(where: { !$0.isCompleted })
            )
        }
        .glassRow()
    }

    @ViewBuilder
    private var upcomingSections: some View {
        let later = laterTasks
        let someday = somedayTasks

        Section {
            if later.isEmpty {
                EmptyStateRow(
                    icon: "calendar",
                    title: "Nothing beyond this week",
                    message: "Tasks scheduled more than 7 days out appear here."
                )
            } else {
                taskRows(later, showsDate: true)
            }
        } header: {
            sectionHeader("Later", count: later.count(where: { !$0.isCompleted }))
        }
        .glassRow()

        Section {
            if someday.isEmpty {
                EmptyStateRow(
                    icon: "tray",
                    title: "Backlog is empty",
                    message: "Capture ideas with no date as “Someday”."
                )
            } else {
                taskRows(someday)
            }
        } header: {
            sectionHeader("Someday", count: someday.count(where: { !$0.isCompleted }))
        }
        .glassRow()
    }

    private func sectionHeader(_ title: String, count: Int, tint: Color = Theme.textSecondary) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if count > 0 {
                Text("\(count) open")
                    .font(Theme.rounded(.caption, weight: .semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(value: Double(count)))
            }
        }
    }

    // MARK: Rows

    private func taskRows(_ items: [TaskItem], showsDate: Bool = false) -> some View {
        ForEach(items) { task in
            TaskRowView(
                task: task,
                showsDate: showsDate,
                onToggle: {
                    withAnimation(Theme.spring) {
                        store.toggleCompletion(task)
                    }
                },
                onOpen: { editingTask = task }
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    withAnimation { store.delete(task) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    withAnimation { store.reschedule(task, byDaysFromToday: 1) }
                } label: {
                    Label("Tomorrow", systemImage: "sunrise.fill")
                }
                .tint(Theme.amber)

                Button {
                    withAnimation { store.reschedule(task, byDaysFromToday: 7) }
                } label: {
                    Label("Next Week", systemImage: "calendar.badge.plus")
                }
                .tint(Theme.indigo)

                Button {
                    reschedulingTask = task
                } label: {
                    Label("Pick Date", systemImage: "calendar")
                }
                .tint(Theme.cyan)
            }
            .contextMenu {
                TaskContextMenuItems(task: task)
            }
        }
    }

    // MARK: Add button

    private var addButton: some View {
        Button {
            isAddingTask = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Theme.primaryGradient, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .shadow(color: Theme.violet.opacity(0.55), radius: 14, y: 6)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 18)
        .accessibilityLabel("Add task")
        .keyboardShortcut("n", modifiers: .command)
        .sensoryFeedback(.impact(weight: .medium), trigger: isAddingTask) { _, isPresented in isPresented }
    }
}

// MARK: - Header card

struct ProgressHeaderCard: View {
    let title: String
    let completed: Int
    let total: Int
    let totalXP: Int
    let points: Int
    let streak: Int

    private var fraction: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.3)
                        .foregroundStyle(Theme.textSecondary)
                    Text(total == 0 ? "No tasks yet" : "\(completed) of \(total) done")
                        .font(Theme.rounded(.title2))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                }
                Spacer()
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(Theme.rounded(.title))
                    .monospacedDigit()
                    .foregroundStyle(fraction >= 1 ? Theme.successGradient : Theme.primaryGradient)
                    .contentTransition(.numericText(value: fraction))
            }

            GradientProgressBar(
                value: fraction,
                colors: fraction >= 1 ? Theme.successColors : Theme.primaryColors,
                height: 10
            )

            HStack(spacing: 8) {
                StatPill(icon: "star.fill", value: totalXP, unit: "XP")
                StatPill(icon: "leaf.fill", value: points, unit: "pts", colors: Theme.successColors)
                StatPill(icon: "flame.fill", value: streak, unit: streak == 1 ? "day" : "days", colors: Theme.legendaryColors)
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .glassCard()
        .animation(Theme.spring, value: fraction)
        .animation(Theme.spring, value: totalXP)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Next checkpoint

/// Slim progress bar toward the next daily checkpoint or shop reward.
struct NextCheckpointBar: View {
    let status: RewardMath.NextCheckpoint
    let onClaim: (RewardCheckpoint) -> Void

    var body: some View {
        Group {
            switch status {
            case .claimable(let checkpoint):
                claimable(checkpoint)
            case .daily(let checkpoint, let progress):
                progressRow(
                    label: "Next Checkpoint",
                    current: progress,
                    target: checkpoint.cost,
                    verb: "to unlock",
                    reward: checkpoint
                )
            case .shop(let reward, let balance):
                progressRow(
                    label: "Saving For",
                    current: balance,
                    target: reward.cost,
                    verb: "to afford",
                    reward: reward
                )
            case .allUnlocked:
                HStack(spacing: 10) {
                    GradientIcon(systemName: "crown.fill", colors: Theme.legendaryColors, size: 30)
                    Text("Every checkpoint cleared—treat yourself in Leisure Rewards.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 18)
    }

    private func claimable(_ checkpoint: RewardCheckpoint) -> some View {
        HStack(spacing: 12) {
            GradientIcon(systemName: checkpoint.iconName, colors: Theme.successColors, size: 34)
                .symbolEffect(.bounce, options: .repeat(2), value: checkpoint.id)
            VStack(alignment: .leading, spacing: 2) {
                Text("CHECKPOINT UNLOCKED")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.successGradient)
                Text(checkpoint.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 4)
            Button {
                onClaim(checkpoint)
            } label: {
                Text("Claim")
                    .font(Theme.rounded(.subheadline))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.successGradient, in: Capsule())
                    .shadow(color: Theme.emerald.opacity(0.5), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
        }
    }

    private func progressRow(label: String, current: Int, target: Int, verb: String, reward: RewardCheckpoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: reward.iconName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.successGradient)
                Text(label.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(max(0, target - current)) to go")
                    .font(Theme.rounded(.caption2, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .contentTransition(.numericText())
            }

            GradientProgressBar(
                value: target > 0 ? Double(current) / Double(target) : 0,
                colors: Theme.successColors,
                height: 6
            )

            (
                Text("\(current) / \(target) pts")
                    .font(Theme.rounded(.footnote))
                    .foregroundStyle(Theme.textPrimary)
                + Text(" \(verb): ")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                + Text(reward.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .contentTransition(.numericText())
        }
        .animation(Theme.spring, value: current)
    }
}

// MARK: - Empty state

struct EmptyStateRow: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.primaryGradient)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Reschedule sheet

struct RescheduleSheet: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let task: TaskItem
    @State private var date: Date

    init(task: TaskItem) {
        self.task = task
        _date = State(initialValue: max(task.scheduledDate ?? .now, Calendar.current.startOfDay(for: .now)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("New date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                } header: {
                    Text(task.title)
                }
                .glassRow()

                Section {
                    Button {
                        store.reschedule(task, to: nil)
                        dismiss()
                    } label: {
                        Label("Move to Someday", systemImage: "tray")
                    }
                }
                .glassRow()
            }
            .themedScreen()
            .formStyle(.grouped)
            .navigationTitle("Reschedule")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        store.reschedule(task, to: date)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .macSheetFrame(width: 420, height: 560)
    }
}

// MARK: - Plan model

/// Groups tasks into the Plan views' buckets. Shared by the iOS Plan tab, the macOS
/// workspace and the macOS sidebar's remaining-task badges.
struct PlanModel {
    let tasks: [TaskItem]
    let today: Date
    let calendar: Calendar

    init(tasks: [TaskItem], now: Date = .now, calendar: Calendar = .current) {
        self.tasks = tasks
        self.calendar = calendar
        self.today = calendar.startOfDay(for: now)
    }

    var weekDays: [Date] { (0..<7).map { calendar.dayOffset($0, from: today) } }
    var weekEnd: Date { calendar.dayOffset(7, from: today) }

    var overdue: [TaskItem] {
        Self.ordered(tasks.filter { $0.isOverdue(asOf: today, calendar: calendar) })
    }

    func tasks(on day: Date) -> [TaskItem] {
        Self.ordered(tasks.filter { $0.isScheduled(on: day, calendar: calendar) })
    }

    /// Scheduled from today through the next 6 days.
    var weekTasks: [TaskItem] {
        tasks.filter { task in
            guard !task.isArchived, let date = task.scheduledDate else { return false }
            return date >= today && date < weekEnd
        }
    }

    /// Scheduled more than 7 days out, soonest first.
    var later: [TaskItem] {
        tasks
            .filter { task in
                guard !task.isArchived, let date = task.scheduledDate else { return false }
                return date >= weekEnd
            }
            .sorted { lhs, rhs in
                let l = lhs.scheduledDate ?? .distantFuture
                let r = rhs.scheduledDate ?? .distantFuture
                return l == r ? lhs.createdAt < rhs.createdAt : l < r
            }
    }

    /// Backlog: open items, plus anything checked off today so it doesn't vanish mid-session.
    var someday: [TaskItem] {
        Self.ordered(tasks.filter { task in
            guard !task.isArchived, task.scheduledDate == nil else { return false }
            guard task.isCompleted else { return true }
            return task.completedAt.map { calendar.isDate($0, inSameDayAs: today) } ?? false
        })
    }

    var weekSummaries: [Date: DaySummary] {
        var summaries: [Date: DaySummary] = [:]
        for task in weekTasks {
            guard let date = task.scheduledDate else { continue }
            let day = calendar.startOfDay(for: date)
            summaries[day, default: DaySummary()].total += 1
            if task.isCompleted {
                summaries[day, default: DaySummary()].completed += 1
            }
        }
        return summaries
    }

    /// Open tasks for a scope (Today includes overdue).
    func remainingCount(for scope: PlanScope) -> Int {
        switch scope {
        case .today: (overdue + tasks(on: today)).count { !$0.isCompleted }
        case .week: weekTasks.count { !$0.isCompleted }
        case .upcoming: (later + someday).count { !$0.isCompleted }
        }
    }

    /// Incomplete first, then the Morning Kickoff priority order, then highest effort, then oldest.
    static func ordered(_ items: [TaskItem]) -> [TaskItem] {
        items.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            switch (lhs.priorityRank, rhs.priorityRank) {
            case let (l?, r?) where l != r: return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            if lhs.effort.rank != rhs.effort.rank { return lhs.effort.rank > rhs.effort.rank }
            return lhs.createdAt < rhs.createdAt
        }
    }
}

#Preview("Plan") {
    PlanView()
        .previewEnvironment()
}

#Preview("Header card") {
    VStack(spacing: 12) {
        ProgressHeaderCard(title: "Today's Progress", completed: 2, total: 5, totalXP: 340, points: 290, streak: 6)
    }
    .padding()
    .themedScreen()
    .preferredColorScheme(.dark)
}
