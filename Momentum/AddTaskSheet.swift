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

/// Creates a new task, or edits an existing one when initialized with `editing:`.
struct AddTaskSheet: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let editingTask: TaskItem?

    @State private var title: String
    @State private var notes: String
    @State private var dateChoice: DateChoice
    @State private var customDate: Date
    @State private var effort: EffortLevel
    @FocusState private var isTitleFocused: Bool

    init(defaultDate: Date?) {
        editingTask = nil
        _title = State(initialValue: "")
        _notes = State(initialValue: "")
        _dateChoice = State(initialValue: DateChoice.matching(defaultDate))
        _customDate = State(initialValue: defaultDate ?? .now)
        _effort = State(initialValue: .standard)
    }

    init(editing task: TaskItem) {
        editingTask = task
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes)
        _dateChoice = State(initialValue: DateChoice.matching(task.scheduledDate))
        _customDate = State(initialValue: task.scheduledDate ?? .now)
        _effort = State(initialValue: task.effort)
    }

    private var resolvedDate: Date? {
        let calendar = Calendar.current
        switch dateChoice {
        case .today: return calendar.dayOffset(0)
        case .tomorrow: return calendar.dayOffset(1)
        case .nextWeek: return calendar.dayOffset(7)
        case .someday: return nil
        case .custom: return calendar.startOfDay(for: customDate)
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing?", text: $title)
                        .font(.headline)
                        .focused($isTitleFocused)
                        .submitLabel(.done)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
                .glassRow()

                Section("When") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(DateChoice.allCases) { choice in
                                DateChip(choice: choice, isSelected: dateChoice == choice) {
                                    withAnimation(Theme.spring) {
                                        dateChoice = choice
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                    if dateChoice == .custom {
                        DatePicker("Date", selection: $customDate, displayedComponents: .date)
                    } else {
                        LabeledContent("Scheduled") {
                            Text(resolvedDate?.formatted(.dateTime.weekday(.wide).month().day()) ?? "Unscheduled backlog")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .glassRow()

                Section {
                    HStack(spacing: 10) {
                        ForEach(EffortLevel.allCases) { level in
                            EffortOptionCard(level: level, isSelected: effort == level) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    effort = level
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                } header: {
                    Text("Effort")
                } footer: {
                    Text("Completing this task earns \(effort.points) XP and \(effort.points) Leisure Points.")
                        .contentTransition(.numericText())
                }
                .glassRow()
            }
            .themedScreen()
            .navigationTitle(editingTask == nil ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingTask == nil ? "Add" : "Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .sensoryFeedback(.selection, trigger: dateChoice)
            .sensoryFeedback(.selection, trigger: effort)
            .onAppear {
                if editingTask == nil {
                    isTitleFocused = true
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        guard canSave else { return }
        if let editingTask {
            store.update(editingTask, title: title, notes: notes, scheduledDate: resolvedDate, effort: effort)
        } else {
            store.addTask(title: title, notes: notes, scheduledDate: resolvedDate, effort: effort)
        }
        dismiss()
    }
}

// MARK: - Components

private struct DateChip: View {
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
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct EffortOptionCard: View {
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
