import SwiftData
import SwiftUI

// MARK: - Modes

/// The two guided planning rituals.
enum RitualMode: String, Identifiable, CaseIterable {
    /// Swipe through overdue leftovers: right → Today, left → archive, up → Someday.
    case sundayReset
    /// Step through today's plan: right → lock in, left → tomorrow, up → top priority.
    case morningKickoff

    var id: String { rawValue }

    var eventKind: MomentumEventKind {
        switch self {
        case .sundayReset: .sundayReset
        case .morningKickoff: .morningKickoff
        }
    }

    var title: String {
        switch self {
        case .sundayReset: "Sunday Reset"
        case .morningKickoff: "Morning Kickoff"
        }
    }

    var iconName: String {
        switch self {
        case .sundayReset: "arrow.counterclockwise.circle.fill"
        case .morningKickoff: "sunrise.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .sundayReset: [Theme.indigo, Theme.cyan]
        case .morningKickoff: Theme.legendaryColors
        }
    }

    var instructions: String {
        switch self {
        case .sundayReset: "Swipe right to move to Today, left to clear it, up for Someday."
        case .morningKickoff: "Swipe right to lock it in, left to push to tomorrow, up to make it #1."
        }
    }

    func action(for direction: SwipeDirection) -> RitualAction {
        switch (self, direction) {
        case (.sundayReset, .right): .moveToToday
        case (.sundayReset, .left): .archive
        case (.sundayReset, .up): .someday
        case (.morningKickoff, .right): .lockIn
        case (.morningKickoff, .left): .deferToTomorrow
        case (.morningKickoff, .up): .topPriority
        }
    }
}

enum SwipeDirection: CaseIterable {
    case left, up, right
}

enum RitualAction: Equatable {
    case moveToToday, archive, someday
    case lockIn, deferToTomorrow, topPriority

    var label: String {
        switch self {
        case .moveToToday: "Today"
        case .archive: "Archive"
        case .someday: "Someday"
        case .lockIn: "Lock In"
        case .deferToTomorrow: "Tomorrow"
        case .topPriority: "Top Priority"
        }
    }

    var iconName: String {
        switch self {
        case .moveToToday, .lockIn: "checkmark"
        case .archive: "archivebox.fill"
        case .someday: "tray.and.arrow.up.fill"
        case .deferToTomorrow: "sunrise.fill"
        case .topPriority: "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .moveToToday, .lockIn: Theme.indigo
        case .archive: Color(hex: 0x64748B)
        case .someday: Color(hex: 0x14B8A6)
        case .deferToTomorrow: Theme.amber
        case .topPriority: Theme.rose
        }
    }
}

// MARK: - When to suggest a ritual

enum RitualSchedule {
    /// The ritual worth suggesting right now, if any:
    /// - Sunday Reset: Sundays from 9 AM while overdue leftovers exist.
    /// - Morning Kickoff: 5–11 AM while today has open tasks.
    /// Each is suggested only until it's been done that day.
    static func suggestion(
        plan: PlanModel,
        completedToday: Set<MomentumEventKind>,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> RitualMode? {
        let hour = calendar.component(.hour, from: now)
        let isSunday = calendar.component(.weekday, from: now) == 1
        if isSunday, hour >= 9, !plan.overdue.isEmpty, !completedToday.contains(.sundayReset) {
            return .sundayReset
        }
        let openToday = plan.tasks(on: plan.today).contains { !$0.isCompleted }
        if (5..<11).contains(hour), openToday, !completedToday.contains(.morningKickoff) {
            return .morningKickoff
        }
        return nil
    }

    static func dayKey(_ date: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}

/// Non-intrusive "Ready for your Sunday Reset?" / "Start Morning Kickoff" card for the Plan
/// screen. Dismissing hides it until tomorrow.
struct RitualPromptSlot: View {
    @Query private var tasks: [TaskItem]
    @Query private var events: [MomentumEvent]
    @AppStorage("ritualPrompt.dismissed") private var dismissedKey = ""
    let onStart: (RitualMode) -> Void

    @Environment(\.scenePhase) private var scenePhase

    // No TimelineView here: when there's nothing to suggest this must render nothing at all, so
    // it doesn't leave an empty row in the Plan list. It re-evaluates when tasks or events
    // change and when the app returns to the foreground.
    var body: some View {
        let now = Date.now
        let completed = Set(events.filter { Calendar.current.isDate($0.occurredAt, inSameDayAs: now) }.map(\.kind))
        let plan = PlanModel(tasks: tasks, now: now)
        if scenePhase != .background,
           let mode = RitualSchedule.suggestion(plan: plan, completedToday: completed, now: now),
           dismissedKey != "\(RitualSchedule.dayKey(now))|\(mode.rawValue)" {
            RitualPromptCard(mode: mode, detail: detail(for: mode, plan: plan)) {
                onStart(mode)
            } onDismiss: {
                withAnimation(Theme.spring) {
                    dismissedKey = "\(RitualSchedule.dayKey(now))|\(mode.rawValue)"
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func detail(for mode: RitualMode, plan: PlanModel) -> String {
        switch mode {
        case .sundayReset:
            let count = plan.overdue.count
            return "\(count) leftover task\(count == 1 ? "" : "s") from last week. Sort them in a minute · +\(TaskStore.ritualXP) XP"
        case .morningKickoff:
            let count = plan.tasks(on: plan.today).count { !$0.isCompleted }
            return "Confirm today's \(count) task\(count == 1 ? "" : "s") and lock in your target · +\(TaskStore.ritualXP) XP"
        }
    }
}

struct RitualPromptCard: View {
    let mode: RitualMode
    let detail: String
    let onStart: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            GradientIcon(systemName: mode.iconName, colors: mode.colors, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode == .sundayReset ? "Ready for your Sunday Reset?" : "Start Morning Kickoff")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(action: onStart) {
                Text("Start")
                    .font(Theme.rounded(.subheadline))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.diagonal(mode.colors), in: Capsule())
            }
            .buttonStyle(.plain)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 26, height: 26)
                    .background(Theme.chipBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss until tomorrow")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 18, tint: mode.colors.first)
    }
}

/// Menu items that launch either ritual on demand (Plan toolbar).
struct RitualMenuItems: View {
    let onStart: (RitualMode) -> Void

    var body: some View {
        ForEach(RitualMode.allCases) { mode in
            Button {
                onStart(mode)
            } label: {
                Label(mode.title, systemImage: mode.iconName)
            }
        }
    }
}

// MARK: - Flow

/// The card-swipe ritual. Each swipe applies immediately (with Undo); finishing the deck
/// records the ritual (+25 XP once per day, Sunday Planner badge) and shows a summary.
struct RitualFlowView: View {
    let mode: RitualMode

    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var tasks: [TaskItem]

    private struct Decision {
        let taskID: UUID
        let action: RitualAction
        let previousDate: Date?
        let previousArchivedAt: Date?
    }

    @State private var deck: [UUID] = []
    @State private var hasLoaded = false
    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var flyOut: CGSize = .zero
    @State private var decisions: [Decision] = []
    @State private var outcome: TaskStore.RitualOutcome?
    @State private var swipeCount = 0
    @State private var finishCount = 0

    private let threshold: CGFloat = 110

    private func task(_ id: UUID) -> TaskItem? { tasks.first { $0.id == id } }
    private var remaining: [TaskItem] { deck.dropFirst(index).compactMap(task) }
    private var isFinished: Bool { hasLoaded && index >= deck.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if isFinished {
                    RitualSummaryCard(mode: mode, decisions: decisions.map(\.action), outcome: outcome, plan: summaryPlan) {
                        dismiss()
                    }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else if hasLoaded {
                    header
                    cardStack
                        .frame(maxWidth: 440)
                        .frame(maxHeight: .infinity)
                    actionButtons
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(mode.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isFinished ? "Done" : "Close") { dismiss() }
                }
                if !isFinished {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            undo()
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(decisions.isEmpty)
                        .keyboardShortcut("z", modifiers: .command)
                    }
                }
            }
        }
        .presentationBackground(Theme.obsidianTop)
        .presentationDetents([.large])
        .macSheetFrame(width: 520, height: 720)
        .sensoryFeedback(.impact(weight: .medium), trigger: swipeCount)
        .sensoryFeedback(.success, trigger: finishCount)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.rightArrow) { commit(.right); return .handled }
        .onKeyPress(.leftArrow) { commit(.left); return .handled }
        .onKeyPress(.upArrow) { commit(.up); return .handled }
        .onAppear(perform: loadDeck)
    }

    // MARK: Deck

    private func loadDeck() {
        guard !hasLoaded else { return }
        let plan = PlanModel(tasks: tasks)
        switch mode {
        case .sundayReset:
            deck = plan.overdue
                .sorted { ($0.scheduledDate ?? .distantPast) < ($1.scheduledDate ?? .distantPast) }
                .map(\.id)
        case .morningKickoff:
            deck = plan.tasks(on: plan.today).filter { !$0.isCompleted }.map(\.id)
        }
        hasLoaded = true
        if deck.isEmpty { finish() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Text(mode.instructions)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                Text("\(min(index + 1, deck.count)) of \(deck.count)")
                    .font(Theme.rounded(.footnote, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .contentTransition(.numericText())
            }
            GradientProgressBar(value: deck.isEmpty ? 1 : Double(index) / Double(deck.count), colors: mode.colors, height: 6)
        }
        .frame(maxWidth: 440)
    }

    private var cardStack: some View {
        ZStack {
            ForEach(Array(remaining.prefix(3).enumerated().reversed()), id: \.element.id) { depth, task in
                let isTop = depth == 0
                RitualTaskCard(
                    task: task,
                    mode: mode,
                    direction: isTop ? direction(for: drag) : nil,
                    strength: isTop ? strength(for: drag) : 0
                )
                .scaleEffect(1 - CGFloat(depth) * 0.05)
                .offset(y: CGFloat(depth) * 14)
                .opacity(depth == 2 ? 0.6 : 1)
                .offset(isTop ? (flyOut == .zero ? drag : flyOut) : .zero)
                .rotationEffect(.degrees(isTop ? Double((flyOut == .zero ? drag : flyOut).width / 18) : 0))
                .gesture(isTop ? dragGesture : nil)
                .zIndex(Double(3 - depth))
                .accessibilityAction(named: mode.action(for: .right).label) { commit(.right) }
                .accessibilityAction(named: mode.action(for: .left).label) { commit(.left) }
                .accessibilityAction(named: mode.action(for: .up).label) { commit(.up) }
            }
        }
        .animation(Theme.spring, value: index)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in drag = value.translation }
            .onEnded { value in
                let predicted = value.predictedEndTranslation
                if let direction = direction(for: value.translation, minimum: threshold)
                    ?? direction(for: predicted, minimum: threshold * 2.2) {
                    commit(direction)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = .zero }
                }
            }
    }

    private func direction(for translation: CGSize, minimum: CGFloat = 24) -> SwipeDirection? {
        if -translation.height > abs(translation.width), -translation.height > minimum { return .up }
        if translation.width > minimum { return .right }
        if translation.width < -minimum { return .left }
        return nil
    }

    private func strength(for translation: CGSize) -> Double {
        min(1, max(abs(translation.width), -translation.height) / threshold)
    }

    private var actionButtons: some View {
        HStack(spacing: 22) {
            ForEach([SwipeDirection.left, .up, .right], id: \.self) { direction in
                let action = mode.action(for: direction)
                Button {
                    commit(direction)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: action.iconName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: direction == .up ? 52 : 60, height: direction == .up ? 52 : 60)
                            .background(action.color.gradient, in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                            .shadow(color: action.color.opacity(0.5), radius: 10, y: 4)
                        Text(action.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.label)
            }
        }
    }

    // MARK: Decisions

    private func commit(_ direction: SwipeDirection) {
        guard !isFinished, index < deck.count, let task = task(deck[index]) else { return }
        let action = mode.action(for: direction)
        decisions.append(Decision(taskID: task.id, action: action, previousDate: task.scheduledDate, previousArchivedAt: task.archivedAt))
        swipeCount += 1

        let distance: CGFloat = 700
        let target: CGSize = switch direction {
        case .left: CGSize(width: -distance, height: drag.height)
        case .right: CGSize(width: distance, height: drag.height)
        case .up: CGSize(width: drag.width, height: -distance)
        }
        withAnimation(.easeIn(duration: reduceMotion ? 0.01 : 0.22)) { flyOut = target }

        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 10 : 220))
            apply(action, to: task)
            drag = .zero
            flyOut = .zero
            withAnimation(Theme.spring) { index += 1 }
            if index >= deck.count { finish() }
        }
    }

    private func apply(_ action: RitualAction, to task: TaskItem) {
        switch action {
        case .moveToToday: store.reschedule(task, byDaysFromToday: 0)
        case .archive: store.archive(task)
        case .someday: store.reschedule(task, to: nil)
        case .deferToTomorrow: store.reschedule(task, byDaysFromToday: 1)
        case .lockIn, .topPriority: break // ordered when the deck is finished
        }
    }

    private func undo() {
        guard let last = decisions.popLast(), let task = task(last.taskID) else { return }
        switch last.action {
        case .moveToToday, .someday, .deferToTomorrow: store.reschedule(task, to: last.previousDate)
        case .archive: store.unarchive(task)
        case .lockIn, .topPriority: break
        }
        withAnimation(Theme.spring) { index = max(0, index - 1) }
    }

    private func finish() {
        if mode == .morningKickoff {
            // Top picks first (in the order chosen), then the rest of the locked-in tasks.
            let tops = decisions.filter { $0.action == .topPriority }.compactMap { task($0.taskID) }
            let kept = decisions.filter { $0.action == .lockIn }.compactMap { task($0.taskID) }
            if !(tops + kept).isEmpty { store.setPriorityOrder(tops + kept) }
        }
        if !deck.isEmpty {
            outcome = store.completeRitual(mode.eventKind, itemCount: deck.count)
        }
        finishCount += 1
    }

    /// Today's open tasks after a Morning Kickoff, in their new order.
    private var summaryPlan: [TaskItem] {
        let plan = PlanModel(tasks: tasks)
        return plan.tasks(on: plan.today).filter { !$0.isCompleted }
    }
}

// MARK: - Card

struct RitualTaskCard: View {
    let task: TaskItem
    let mode: RitualMode
    let direction: SwipeDirection?
    let strength: Double

    private var action: RitualAction? { direction.map(mode.action(for:)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                EffortBadge(effort: task.effort)
                Spacer()
                Text(dateText)
                    .font(Theme.rounded(.caption, weight: .semibold))
                    .foregroundStyle(task.isOverdue() ? Theme.rose : Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Text(task.title)
                .font(Theme.rounded(.title2, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !task.notes.isEmpty {
                Text(task.notes)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(4)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "star.fill").foregroundStyle(Theme.primaryGradient)
                Text("\(task.effort.points) XP")
                    .font(Theme.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 300, maxHeight: 380)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Theme.obsidianBottom, Theme.obsidianTop], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill((action?.color ?? .clear).opacity(0.22 * strength))
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    action.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(Color.white.opacity(0.14)),
                    lineWidth: 1 + 1.5 * strength
                )
        }
        .overlay(alignment: .top) {
            if let action, strength > 0.15 {
                Label(action.label, systemImage: action.iconName)
                    .font(Theme.rounded(.headline, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(action.color, in: Capsule())
                    .rotationEffect(.degrees(direction == .left ? 8 : direction == .right ? -8 : 0))
                    .opacity(strength)
                    .padding(.top, 18)
            }
        }
        .shadow(color: (action?.color ?? .black).opacity(0.25 + 0.4 * strength), radius: 22, y: 10)
        .accessibilityElement(children: .combine)
    }

    private var dateText: String {
        guard let date = task.scheduledDate else { return "Someday" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        return "Due " + date.formatted(.relative(presentation: .named))
    }
}

// MARK: - Summary

struct RitualSummaryCard: View {
    let mode: RitualMode
    let decisions: [RitualAction]
    let outcome: TaskStore.RitualOutcome?
    let plan: [TaskItem]
    let onDone: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Image(systemName: decisions.isEmpty ? "checkmark.seal.fill" : mode.iconName)
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 110, height: 110)
                .background(Theme.diagonal(mode.colors), in: Circle())
                .shadow(color: (mode.colors.last ?? Theme.violet).opacity(0.6), radius: 24)
                .scaleEffect(appeared ? 1 : 0.5)

            VStack(spacing: 6) {
                Text(title)
                    .font(Theme.rounded(.title, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if !counts.isEmpty {
                HStack(spacing: 8) {
                    ForEach(counts, id: \.action.label) { item in
                        Label("\(item.count) \(item.action.label)", systemImage: item.action.iconName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(item.action.color.opacity(0.8), in: Capsule())
                    }
                }
            }

            if mode == .morningKickoff, !plan.isEmpty {
                kickoffTarget
            }

            if let outcome {
                Text(outcome.xpAwarded > 0 ? "+\(outcome.xpAwarded) XP" : "XP already earned today")
                    .font(Theme.rounded(outcome.xpAwarded > 0 ? .title2 : .subheadline, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(outcome.xpAwarded > 0 ? Theme.primaryGradient : LinearGradient(colors: [Theme.chipBackground], startPoint: .top, endPoint: .bottom), in: Capsule())
                    .shadow(color: Theme.violet.opacity(outcome.xpAwarded > 0 ? 0.6 : 0), radius: 14)
                    .offset(y: appeared ? 0 : 20)
                    .opacity(appeared ? 1 : 0)
            }

            Spacer(minLength: 0)

            Button(action: onDone) {
                Text("Done")
                    .font(Theme.rounded(.headline))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 440)
                    .padding(.vertical, 14)
                    .background(Theme.diagonal(mode.colors), in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62).delay(0.05)) { appeared = true }
        }
    }

    private var kickoffTarget: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TODAY'S TARGET")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(plan.count) tasks · \(plan.reduce(0) { $0 + $1.effort.points }) XP")
                    .font(Theme.rounded(.caption, weight: .bold))
                    .foregroundStyle(Theme.legendaryGradient)
            }
            ForEach(Array(plan.prefix(3).enumerated()), id: \.element.id) { offset, task in
                HStack(spacing: 10) {
                    Text("\(offset + 1)")
                        .font(Theme.rounded(.caption, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Theme.legendaryGradient, in: Circle())
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 440)
        .glassCard(cornerRadius: 16)
    }

    private var counts: [(action: RitualAction, count: Int)] {
        var result: [(RitualAction, Int)] = []
        for action in [RitualAction.moveToToday, .someday, .archive, .topPriority, .lockIn, .deferToTomorrow] {
            let count = decisions.count { $0 == action }
            if count > 0 { result.append((action, count)) }
        }
        return result.map { (action: $0.0, count: $0.1) }
    }

    private var title: String {
        if decisions.isEmpty {
            return mode == .sundayReset ? "Already reset" : "Nothing to kick off"
        }
        return mode == .sundayReset ? "Reset complete" : "Day locked in"
    }

    private var subtitle: String {
        if decisions.isEmpty {
            return mode == .sundayReset
                ? "No overdue tasks. You're starting the week clean."
                : "Nothing is scheduled for today yet. Add a task to plan your day."
        }
        return mode == .sundayReset
            ? "Last week's leftovers are sorted. Fresh week, clear head."
            : "Your priorities are set. Go build some momentum."
    }
}

#Preview("Sunday Reset") {
    RitualFlowView(mode: .sundayReset)
        .previewEnvironment()
}

#Preview("Morning Kickoff") {
    RitualFlowView(mode: .morningKickoff)
        .previewEnvironment()
}
