import SwiftUI

struct DaySummary: Equatable {
    var total = 0
    var completed = 0

    var isAllDone: Bool { total > 0 && completed == total }
}

/// Horizontal 7-day selector showing each day's task status.
struct WeekStripView: View {
    let days: [Date]
    @Binding var selection: Date
    var summaries: [Date: DaySummary] = [:]

    @Namespace private var selectionNamespace
    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                dayCell(day)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)
        let summary = summaries[day] ?? DaySummary()
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        return Button {
            withAnimation(Theme.spring) {
                selection = day
            }
        } label: {
            VStack(spacing: 6) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Theme.textTertiary)

                Text(day.formatted(.dateTime.day()))
                    .font(Theme.rounded(.title3, weight: isToday ? .heavy : .semibold))
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Theme.violet : Theme.textPrimary))

                statusIndicator(summary, isSelected: isSelected)
                    .frame(height: 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    shape
                        .fill(Theme.primaryGradient)
                        .shadow(color: Theme.violet.opacity(0.5), radius: 10, y: 4)
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                } else {
                    shape
                        .fill(Theme.rowBackground)
                        .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month().day()))
        .accessibilityValue(summary.total == 0 ? "No tasks" : "\(summary.completed) of \(summary.total) tasks done")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func statusIndicator(_ summary: DaySummary, isSelected: Bool) -> some View {
        if summary.total == 0 {
            Circle()
                .fill(.clear)
                .frame(width: 6, height: 6)
        } else if summary.isAllDone {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.successGradient))
        } else {
            HStack(spacing: 3) {
                ForEach(0..<min(summary.total - summary.completed, 3), id: \.self) { _ in
                    Circle()
                        .fill(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.violet))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var selection = Calendar.current.startOfDay(for: .now)
    let days = (0..<7).map { Calendar.current.dayOffset($0) }

    WeekStripView(
        days: days,
        selection: $selection,
        summaries: [
            days[0]: DaySummary(total: 4, completed: 1),
            days[1]: DaySummary(total: 2, completed: 0),
            days[2]: DaySummary(total: 1, completed: 1),
            days[4]: DaySummary(total: 1, completed: 0),
        ]
    )
    .padding()
    .themedScreen()
    .preferredColorScheme(.dark)
}
