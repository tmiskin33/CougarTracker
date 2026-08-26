import SwiftUI

/// A month at a glance. Each day carries its count as dots up to three, then a
/// number — past that, dots stop being countable and start being decoration.
struct MonthGridView: View {
    var anchorDate: Date
    @Binding var selectedDate: Date
    var counts: [Date: Int]
    var overdueDays: Set<Date>
    var calendar: Calendar

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    init(
        anchorDate: Date,
        selectedDate: Binding<Date>,
        counts: [Date: Int],
        overdueDays: Set<Date>,
        calendar: Calendar
    ) {
        self.anchorDate = anchorDate
        self._selectedDate = selectedDate
        self.counts = counts
        self.overdueDays = overdueDays
        self.calendar = calendar
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(CalendarLayout.weekdaySymbols(calendar: calendar), id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(CalendarLayout.monthGrid(containing: anchorDate, calendar: calendar), id: \.self) { day in
                    DayCell(
                        date: day,
                        count: counts[calendar.startOfDay(for: day)] ?? 0,
                        isOverdue: overdueDays.contains(calendar.startOfDay(for: day)),
                        isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                        isToday: calendar.isDateInToday(day),
                        isInMonth: CalendarLayout.isSameMonth(day, anchorDate, calendar: calendar)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedDate = day
                    }
                }
            }
        }
    }

    private struct DayCell: View {
        var date: Date
        var count: Int
        var isOverdue: Bool
        var isSelected: Bool
        var isToday: Bool
        var isInMonth: Bool

        var body: some View {
            VStack(spacing: 3) {
                Text(date, format: .dateTime.day())
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(numberTint)
                    .frame(width: 30, height: 30)
                    .background {
                        if isSelected {
                            Circle().fill(Color.accentColor.opacity(0.22))
                        } else if isToday {
                            Circle().stroke(Color.accentColor, lineWidth: 1)
                        }
                    }

                DeadlineCountBadge(count: count, isOverdue: isOverdue)
                    .frame(height: 14)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        }

        private var numberTint: Color {
            if !isInMonth { return .secondary.opacity(0.5) }
            if isToday { return .accentColor }
            return .primary
        }

        private var accessibilityLabel: String {
            let day = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
            switch count {
            case 0: return "\(day), nothing due"
            case 1: return "\(day), 1 deadline\(isOverdue ? ", overdue" : "")"
            default: return "\(day), \(count) deadlines\(isOverdue ? ", some overdue" : "")"
            }
        }
    }
}

/// One week as a row of tappable days — the middle density between a month grid
/// and a single day.
struct WeekStripView: View {
    var anchorDate: Date
    @Binding var selectedDate: Date
    var counts: [Date: Int]
    var overdueDays: Set<Date>
    var calendar: Calendar

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CalendarLayout.week(containing: anchorDate, calendar: calendar), id: \.self) { day in
                let startOfDay = calendar.startOfDay(for: day)
                VStack(spacing: 4) {
                    Text(day, format: .dateTime.weekday(.narrow))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(day, format: .dateTime.day())
                        .font(.body.monospacedDigit())
                        .frame(width: 32, height: 32)
                        .background {
                            if calendar.isDate(day, inSameDayAs: selectedDate) {
                                Circle().fill(Color.accentColor.opacity(0.22))
                            } else if calendar.isDateInToday(day) {
                                Circle().stroke(Color.accentColor, lineWidth: 1)
                            }
                        }

                    DeadlineCountBadge(
                        count: counts[startOfDay] ?? 0,
                        isOverdue: overdueDays.contains(startOfDay)
                    )
                    .frame(height: 14)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { selectedDate = day }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(for: day, count: counts[startOfDay] ?? 0))
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func label(for day: Date, count: Int) -> String {
        let formatted = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return count == 0 ? "\(formatted), nothing due" : "\(formatted), \(count) deadlines"
    }
}
