import SwiftData
import SwiftUI

enum PlanScope: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "This Week"
    case upcoming = "Upcoming"

    var id: String { rawValue }
}

struct PlanView: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @Query(sort: \RewardCheckpoint.cost) private var rewards: [RewardCheckpoint]
    @Query private var redemptions: [RewardRedemption]

    @State private var scope: PlanScope = .today
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var isAddingTask = false
    @State private var editingTask: TaskItem?
    @State private var reschedulingTask: TaskItem?
    @State private var presentedPass: RewardRedemption?

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: .now) }
    private var weekDays: [Date] { (0..<7).map { calendar.dayOffset($0, from: today) } }
    private var weekEnd: Date { calendar.dayOffset(7, from: today) }

    // MARK: Derived collections

    private var overdueTasks: [TaskItem] {
        ordered(tasks.filter { $0.isOverdue() })
    }

    private func tasks(on day: Date) -> [TaskItem] {
        ordered(tasks.filter { $0.isScheduled(on: day, calendar: calendar) })
    }

    private var weekTasks: [TaskItem] {
        tasks.filter { task in
            guard let date = task.scheduledDate else { return false }
            return date >= today && date < weekEnd
        }
    }

    private var laterTasks: [TaskItem] {
        tasks
            .filter { task in
                guard let date = task.scheduledDate else { return false }
                return date >= weekEnd
            }
            .sorted { lhs, rhs in
                let l = lhs.scheduledDate ?? .distantFuture
                let r = rhs.scheduledDate ?? .distantFuture
                return l == r ? lhs.createdAt < rhs.createdAt : l < r
            }
    }

    /// Backlog: open items, plus anything checked off today so it doesn't vanish mid-session.
    private var somedayTasks: [TaskItem] {
        ordered(tasks.filter { task in
            guard task.scheduledDate == nil else { return false }
            guard task.isCompleted else { return true }
            return task.completedAt.map { calendar.isDateInToday($0) } ?? false
        })
    }

    private var weekSummaries: [Date: DaySummary] {
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

    private func ordered(_ items: [TaskItem]) -> [TaskItem] {
        items.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            if lhs.effort.rank != rhs.effort.rank { return lhs.effort.rank > rhs.effort.rank }
            return lhs.createdAt < rhs.createdAt
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

                    headerCard

                    NextCheckpointBar(
                        status: RewardMath.nextCheckpoint(checkpoints: rewards, tasks: tasks, redemptions: redemptions)
                    ) { checkpoint in
                        if let pass = store.claimDailyCheckpoint(checkpoint) {
                            presentedPass = pass
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))

                switch scope {
                case .today: todaySections
                case .week: weekSections
                case .upcoming: upcomingSections
                }
            }
            .listStyle(.insetGrouped)
            .themedScreen()
            .contentMargins(.bottom, 96, for: .scrollContent)
            .navigationTitle("Plan")
            .overlay(alignment: .bottomTrailing) { addButton }
            .sheet(isPresented: $isAddingTask) {
                AddTaskSheet(defaultDate: defaultDateForNewTask)
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
            .sensoryFeedback(.selection, trigger: scope)
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
            totalXP: PlannerStats.totalXP(tasks),
            points: RewardMath.balance(tasks: tasks, redemptions: redemptions),
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
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
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
