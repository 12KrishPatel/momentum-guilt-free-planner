import Charts
import SwiftData
import SwiftUI
import UserNotifications

struct StatsView: View {
    @Environment(TaskStore.self) private var store
    @Environment(NotificationManager.self) private var notificationManager
    @Query private var tasks: [TaskItem]
    @Query private var awards: [Award]
    @Query private var redemptions: [RewardRedemption]
    @Query private var events: [MomentumEvent]

    @State private var isConfirmingReset = false
    @State private var eraseCount = 0

    private let cardColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        @Bindable var manager = notificationManager

        NavigationStack {
            List {
                Section {
                    WeeklyCompletionChart(data: PlannerStats.dailyCompletions(tasks))
                        .padding(.vertical, 8)
                } header: {
                    Text("Last 7 Days")
                }
                .glassRow()

                Section {
                    LazyVGrid(columns: cardColumns, spacing: 12) {
                        StatCard(title: "Total XP", value: PlannerStats.totalXP(tasks, events: events), icon: "star.fill", colors: Theme.primaryColors)
                        StatCard(
                            title: "Leisure Points",
                            value: RewardMath.balance(tasks: tasks, redemptions: redemptions, events: events),
                            icon: "leaf.fill",
                            colors: Theme.successColors
                        )
                        StatCard(title: "Longest Streak", value: PlannerStats.longestStreak(tasks), unit: "days", icon: "flame.fill", colors: Theme.legendaryColors)
                        StatCard(title: "Current Streak", value: PlannerStats.currentStreak(tasks), unit: "days", icon: "bolt.fill", colors: Theme.primaryColors)
                        StatCard(title: "Completed", value: PlannerStats.completedCount(tasks), icon: "checkmark.circle.fill", colors: Theme.successColors)
                        StatCard(
                            title: "Badges",
                            value: awards.count(where: \.isUnlocked),
                            unit: "/ \(awards.count)",
                            icon: "trophy.fill",
                            colors: Theme.legendaryColors
                        )
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section {
                    Toggle(isOn: $manager.remindersEnabled) {
                        Label("Daily Reminders", systemImage: "bell.badge.fill")
                    }
                    .tint(Theme.violet)
                    permissionRow
                } header: {
                    Text("Notifications")
                } footer: {
                    if manager.remindersEnabled, notificationManager.isAuthorized {
                        Text("\(notificationManager.scheduledCount) reminders queued for today and the next 7 days.")
                    }
                }
                .glassRow()

                if manager.remindersEnabled {
                    Section {
                        ForEach($manager.slots) { $slot in
                            ReminderSlotRow(slot: $slot)
                        }
                        .onDelete { offsets in
                            notificationManager.removeSlots(at: offsets)
                        }

                        Button {
                            withAnimation { notificationManager.addSlot() }
                        } label: {
                            Label("Add Reminder Time", systemImage: "plus")
                                .foregroundStyle(Theme.primaryGradient)
                        }

                        Button {
                            withAnimation { notificationManager.resetToDefaultSchedule() }
                        } label: {
                            Label("Reset to Default Schedule", systemImage: "arrow.counterclockwise")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } header: {
                        Text("Reminder Schedule")
                    } footer: {
                        Text("Summary reminders always fire. “Only notify if tasks remain” reminders are skipped once the day’s tasks are checked off. Swipe a reminder to delete it.")
                    }
                    .glassRow()
                }

                Section {
                    Button(role: .destructive) {
                        isConfirmingReset = true
                    } label: {
                        Label("Erase All Data", systemImage: "trash")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Deletes all tasks, badges, points, passes and custom rewards, including on your other devices signed in to the same iCloud account. Reminder settings are kept.")
                }
                .glassRow()
            }
            .groupedListStyle()
            .themedScreen()
            .navigationTitle(Platform.isMac ? "Stats & Settings" : "Profile")
            .confirmationDialog(
                "Erase all Momentum data?",
                isPresented: $isConfirmingReset,
                titleVisibility: .visible
            ) {
                Button("Erase All Data", role: .destructive) {
                    withAnimation { store.eraseAllData() }
                    eraseCount += 1
                }
            } message: {
                Text("Every task, badge, point, pass and custom reward will be deleted on all your devices. This can’t be undone.")
            }
            .sensoryFeedback(.success, trigger: eraseCount)
            .onChange(of: manager.slots) {
                store.syncNotifications()
            }
            .onChange(of: manager.remindersEnabled) { _, isEnabled in
                Task {
                    if isEnabled, notificationManager.authorizationStatus == .notDetermined {
                        await notificationManager.requestAuthorization()
                    }
                    store.syncNotifications()
                }
            }
            .task {
                await notificationManager.refreshAuthorizationStatus()
            }
        }
    }

    // MARK: Permission

    private var permissionRow: some View {
        HStack {
            Text("System Permission")
            Spacer()
            PermissionBadge(status: notificationManager.authorizationStatus)

            switch notificationManager.authorizationStatus {
            case .notDetermined:
                Button("Allow") {
                    Task {
                        await notificationManager.requestAuthorization()
                        store.syncNotifications()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.violet)
                .controlSize(.small)
            case .denied:
                Button("Settings") {
                    notificationManager.openSystemNotificationSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - Permission badge

struct PermissionBadge: View {
    let status: UNAuthorizationStatus

    private var appearance: (text: String, icon: String, tint: Color) {
        switch status {
        case .authorized: ("Allowed", "checkmark.circle.fill", Theme.emerald)
        case .provisional: ("Quiet Delivery", "moon.circle.fill", Theme.cyan)
        #if os(iOS)
        case .ephemeral: ("Temporary", "clock.fill", Theme.cyan)
        #endif
        case .denied: ("Denied", "xmark.circle.fill", Theme.rose)
        case .notDetermined: ("Not Requested", "questionmark.circle.fill", Theme.amber)
        @unknown default: ("Unknown", "questionmark.circle.fill", .gray)
        }
    }

    var body: some View {
        let appearance = appearance
        Label(appearance.text, systemImage: appearance.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(appearance.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(appearance.tint.opacity(0.15), in: Capsule())
    }
}

// MARK: - Reminder row

struct ReminderSlotRow: View {
    @Binding var slot: ReminderSlot

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: .now) ?? .now
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                var updated = slot
                updated.hour = components.hour ?? slot.hour
                updated.minute = components.minute ?? slot.minute
                slot = updated
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Label", text: $slot.label)
                    .font(.headline)
                    .submitLabel(.done)
                Toggle("Enabled", isOn: $slot.isEnabled)
                    .labelsHidden()
                    .tint(Theme.violet)
            }

            Group {
                DatePicker(selection: time, displayedComponents: .hourAndMinute) {
                    Label("Time", systemImage: "clock")
                }
                .datePickerStyle(.compact)

                Toggle(isOn: $slot.onlyIfIncomplete) {
                    Label("Only notify if tasks remain", systemImage: "checklist.unchecked")
                }
                .tint(Theme.emerald)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .disabled(!slot.isEnabled)
            .opacity(slot.isEnabled ? 1 : 0.5)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Chart

struct WeeklyCompletionChart: View {
    let data: [DayCompletion]

    private var total: Int { data.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(total)")
                    .font(Theme.rounded(.largeTitle, weight: .heavy))
                    .foregroundStyle(Theme.primaryGradient)
                    .contentTransition(.numericText(value: Double(total)))
                Text(total == 1 ? "task completed" : "tasks completed")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            Chart(data) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Completed", day.count),
                    width: .ratio(0.6)
                )
                .cornerRadius(6)
                .foregroundStyle(
                    Calendar.current.isDateInToday(day.date)
                        ? Theme.vertical(Theme.successColors)
                        : Theme.vertical(Theme.primaryColors)
                )
                .opacity(Calendar.current.isDateInToday(day.date) ? 1 : 0.85)
                .annotation(position: .top, spacing: 4) {
                    if day.count > 0 {
                        Text("\(day.count)")
                            .font(Theme.rounded(.caption2, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                        .foregroundStyle(Theme.separator)
                    if let count = value.as(Int.self) {
                        AxisValueLabel("\(count)")
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .chartYScale(domain: 0...max(4, (data.map(\.count).max() ?? 0) + 1))
            .frame(height: 180)
            .animation(Theme.spring, value: data)
            .accessibilityLabel("Tasks completed per day over the last 7 days")
        }
    }
}

// MARK: - Stat card

struct StatCard: View {
    let title: String
    let value: Int
    var unit: String?
    let icon: String
    var colors: [Color] = Theme.primaryColors

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GradientIcon(systemName: icon, colors: colors, size: 34)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(Theme.rounded(.title2, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: Double(value)))
                if let unit {
                    Text(unit)
                        .font(Theme.rounded(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text(title)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 18)
        .animation(Theme.spring, value: value)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Profile") {
    StatsView()
        .previewEnvironment()
}

#Preview("Reminder row") {
    @Previewable @State var slot = ReminderSlot.defaultSchedule[1]
    Form {
        ReminderSlotRow(slot: $slot)
            .glassRow()
    }
    .themedScreen()
    .preferredColorScheme(.dark)
}
