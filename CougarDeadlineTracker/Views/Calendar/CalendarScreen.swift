import SwiftData
import SwiftUI

/// The same deadlines, laid out by date.
///
/// Day, week, and month are three densities of one thing, and all three read
/// their counts from the same grouping helper the list uses, so a badge can
/// never disagree with the list it opens.
struct CalendarScreen: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Deadline.dueDate, order: .forward) private var deadlines: [Deadline]

    @State private var mode: Mode = .month
    @State private var selectedDate = Date()
    @State private var anchorDate = Date()

    private let calendar = Calendar.current

    enum Mode: String, CaseIterable, Identifiable {
        case day, week, month
        var id: String { rawValue }
        var title: String {
            switch self {
            case .day: return "Day"
            case .week: return "Week"
            case .month: return "Month"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                header

                switch mode {
                case .month:
                    MonthGridView(
                        anchorDate: anchorDate,
                        selectedDate: $selectedDate,
                        counts: counts,
                        overdueDays: overdueDays,
                        calendar: calendar
                    )
                    .padding(.horizontal, 8)
                case .week:
                    WeekStripView(
                        anchorDate: anchorDate,
                        selectedDate: $selectedDate,
                        counts: counts,
                        overdueDays: overdueDays,
                        calendar: calendar
                    )
                    .padding(.horizontal, 8)
                case .day:
                    EmptyView()
                }

                Divider()
                    .padding(.top, 8)

                DayListView(focusDate: selectedDate)
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today") {
                        withAnimation {
                            selectedDate = Date()
                            anchorDate = Date()
                        }
                    }
                }
            }
            .onChange(of: mode) { _, _ in
                anchorDate = selectedDate
            }
            .onChange(of: selectedDate) { _, newValue in
                if mode == .month, !CalendarLayout.isSameMonth(newValue, anchorDate, calendar: calendar) {
                    anchorDate = newValue
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button {
                step(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .padding(.horizontal, 6)
            }
            .accessibilityLabel("Previous \(mode.title.lowercased())")

            Spacer()

            Text(headerTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                step(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .padding(.horizontal, 6)
            }
            .accessibilityLabel("Next \(mode.title.lowercased())")
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private var headerTitle: String {
        switch mode {
        case .month:
            return anchorDate.formatted(.dateTime.month(.wide).year())
        case .week:
            let days = CalendarLayout.week(containing: anchorDate, calendar: calendar)
            guard let first = days.first, let last = days.last else { return "" }
            return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
        case .day:
            return selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
    }

    private func step(by amount: Int) {
        withAnimation(.easeInOut(duration: 0.15)) {
            switch mode {
            case .month:
                if let next = calendar.date(byAdding: .month, value: amount, to: anchorDate) {
                    anchorDate = next
                    // Keep the selection inside the month on screen.
                    if !CalendarLayout.isSameMonth(selectedDate, next, calendar: calendar),
                       let interval = calendar.dateInterval(of: .month, for: next) {
                        selectedDate = interval.start
                    }
                }
            case .week:
                if let next = calendar.date(byAdding: .weekOfYear, value: amount, to: anchorDate) {
                    anchorDate = next
                    if let shifted = calendar.date(byAdding: .weekOfYear, value: amount, to: selectedDate) {
                        selectedDate = shifted
                    }
                }
            case .day:
                if let next = calendar.date(byAdding: .day, value: amount, to: selectedDate) {
                    selectedDate = next
                    anchorDate = next
                }
            }
        }
    }

    // MARK: Counts

    private var visibleDeadlines: [Deadline] {
        model.settings.showsCompleted ? deadlines : deadlines.filter { !$0.isCompleted }
    }

    private var counts: [Date: Int] {
        DeadlineGrouping.countsByDay(
            visibleDeadlines,
            includingCompleted: model.settings.showsCompleted,
            calendar: calendar
        )
    }

    /// Days that hold something already past due, so the badge can say so.
    private var overdueDays: Set<Date> {
        let now = Date()
        var days: Set<Date> = []
        for deadline in visibleDeadlines where deadline.isOverdue(asOf: now) {
            days.insert(calendar.startOfDay(for: deadline.dueDate))
        }
        return days
    }
}
