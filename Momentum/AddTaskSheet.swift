import SwiftData
import SwiftUI

enum DateChoice: String, CaseIterable, Identifiable {
    case today = "Today"
    case tomorrow = "Tomorrow"
    case nextWeek = "Next Week"
    case someday = "Someday"
    case custom = "Pick Date"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .today: "sun.max.fill"
        case .tomorrow: "sunrise.fill"
        case .nextWeek: "calendar.badge.plus"
        case .someday: "tray.fill"
        case .custom: "calendar"
        }
    }

    /// The chip that represents `date`, falling back to `.custom`.
    static func matching(_ date: Date?, calendar: Calendar = .current) -> DateChoice {
        guard let date else { return .someday }
        let day = calendar.startOfDay(for: date)
        if day == calendar.dayOffset(0) { return .today }
        if day == calendar.dayOffset(1) { return .tomorrow }
        if day == calendar.dayOffset(7) { return .nextWeek }
        return .custom
    }
}

/// Editable copy of a task's fields, shared by the iOS sheet and the macOS inspector.
struct TaskDraft: Equatable {
    var title = ""
    var notes = ""
    var dateChoice: DateChoice = .today
    var customDate = Date.now
    var effort: EffortLevel = .standard

    init(defaultDate: Date?) {
        dateChoice = DateChoice.matching(defaultDate)
        customDate = defaultDate ?? .now
    }

    init(task: TaskItem) {
        title = task.title
        notes = task.notes
        dateChoice = DateChoice.matching(task.scheduledDate)
        customDate = task.scheduledDate ?? .now
        effort = task.effort
    }

    var resolvedDate: Date? {
        let calendar = Calendar.current
        switch dateChoice {
        case .today: return calendar.dayOffset(0)
        case .tomorrow: return calendar.dayOffset(1)
        case .nextWeek: return calendar.dayOffset(7)
        case .someday: return nil
        case .custom: return calendar.startOfDay(for: customDate)
        }
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether saving would change `task`.
    func differs(from task: TaskItem) -> Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines) != task.title
            || notes.trimmingCharacters(in: .whitespacesAndNewlines) != task.notes
            || resolvedDate != task.scheduledDate.map { Calendar.current.startOfDay(for: $0) }
            || effort != task.effort
    }
}

/// The title / notes, date and effort sections used to create or edit a task.
/// Place inside a `Form`.
struct TaskEditorFields: View {
    @Binding var draft: TaskDraft
    var titleFocus: FocusState<Bool>.Binding
    var onSubmitTitle: () -> Void = {}

    var body: some View {
        Section {
            TextField("Title", text: $draft.title, prompt: Text("What needs doing?"))
                .labelsHidden()
                .font(.headline)
                .focused(titleFocus)
                .submitLabel(.done)
                .onSubmit(onSubmitTitle)
            TextField("Notes", text: $draft.notes, prompt: Text("Notes (optional)"), axis: .vertical)
                .labelsHidden()
                .lineLimit(2...5)
        }
        .glassRow()

        Section("When") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DateChoice.allCases) { choice in
                        DateChip(choice: choice, isSelected: draft.dateChoice == choice) {
                            withAnimation(Theme.spring) {
                                draft.dateChoice = choice
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

            if draft.dateChoice == .custom {
                DatePicker("Date", selection: $draft.customDate, displayedComponents: .date)
            } else {
                LabeledContent("Scheduled") {
                    Text(draft.resolvedDate?.formatted(.dateTime.weekday(.wide).month().day()) ?? "Unscheduled backlog")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .glassRow()

        Section {
            HStack(spacing: 10) {
                ForEach(EffortLevel.allCases) { level in
                    EffortOptionCard(level: level, isSelected: draft.effort == level) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            draft.effort = level
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        } header: {
            Text("Effort")
        } footer: {
            Text("Completing this task earns \(draft.effort.points) XP and \(draft.effort.points) Leisure Points.")
                .contentTransition(.numericText())
        }
        .glassRow()
        .sensoryFeedback(.selection, trigger: draft.dateChoice)
        .sensoryFeedback(.selection, trigger: draft.effort)
    }
}

/// Creates a new task, or edits an existing one when initialized with `editing:`.
struct AddTaskSheet: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let editingTask: TaskItem?

    @State private var draft: TaskDraft
    @FocusState private var isTitleFocused: Bool

    init(defaultDate: Date?, effort: EffortLevel = .standard) {
        editingTask = nil
        var draft = TaskDraft(defaultDate: defaultDate)
        draft.effort = effort
        _draft = State(initialValue: draft)
    }

    init(editing task: TaskItem) {
        editingTask = task
        _draft = State(initialValue: TaskDraft(task: task))
    }

    var body: some View {
        NavigationStack {
            Form {
                TaskEditorFields(draft: $draft, titleFocus: $isTitleFocused)
            }
            .formStyle(.grouped)
            .themedScreen()
            .navigationTitle(editingTask == nil ? "New Task" : "Edit Task")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingTask == nil ? "Add" : "Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!draft.isValid)
                }
            }
            .onAppear {
                if editingTask == nil {
                    isTitleFocused = true
                }
            }
        }
        .presentationDetents([.large])
        .macSheetFrame()
    }

    private func save() {
        guard draft.isValid else { return }
        if let editingTask {
            store.update(editingTask, title: draft.title, notes: draft.notes, scheduledDate: draft.resolvedDate, effort: draft.effort)
        } else {
            store.addTask(title: draft.title, notes: draft.notes, scheduledDate: draft.resolvedDate, effort: draft.effort)
        }
        dismiss()
    }
}

// MARK: - Components

struct DateChip: View {
    let choice: DateChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(choice.rawValue, systemImage: choice.iconName)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .background {
                    if isSelected {
                        Capsule().fill(Theme.primaryGradient)
                            .shadow(color: Theme.violet.opacity(0.45), radius: 8, y: 3)
                    } else {
                        Capsule().fill(Theme.chipBackground)
                            .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct EffortOptionCard: View {
    let level: EffortLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: level.iconName)
                    .font(.title3)
                    .symbolEffect(.bounce, value: isSelected)
                Text(level.label)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(level.points) XP")
                    .font(Theme.rounded(.caption2, weight: .semibold))
                    .opacity(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(isSelected ? Color.white : level.tint)
            .background {
                if isSelected {
                    shape.fill(Theme.diagonal([level.tint, level.tint.opacity(0.65)]))
                        .shadow(color: level.tint.opacity(0.5), radius: 10, y: 4)
                } else {
                    shape.fill(level.tint.opacity(0.12))
                        .overlay(shape.strokeBorder(level.tint.opacity(0.25), lineWidth: 1))
                }
            }
            .scaleEffect(isSelected ? 1.03 : 1)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(level.label), \(level.points) XP")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("New task") {
    AddTaskSheet(defaultDate: .now)
        .previewEnvironment()
}

#Preview("Edit task") {
    AddTaskSheet(editing: PreviewSampleData.sampleTask)
        .previewEnvironment()
}
