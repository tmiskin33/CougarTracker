import SwiftData
import SwiftUI

/// Everything due, grouped by day, oldest first.
///
/// Overdue work stays at the top rather than scrolling away, because the item
/// you already missed is the one you most need to see.
struct DayListView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Deadline.dueDate, order: .forward) private var deadlines: [Deadline]

    /// When set, the list shows only this day — how the calendar drills in.
    var focusDate: Date?

    init(focusDate: Date? = nil) {
        self.focusDate = focusDate
    }

    @State private var reconnectSource: DeadlineSource?
    @State private var now = Date()

    private let calendar = Calendar.current

    var body: some View {
        Group {
            if focusDate == nil {
                NavigationStack {
                    content
                        .navigationTitle("Deadlines")
                        .toolbar { toolbarContent }
                }
            } else {
                content
            }
        }
        .reconnectSheet(for: $reconnectSource)
    }

    private var content: some View {
        List {
            if focusDate == nil {
                bannerSection
            }

            if visibleDays.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            ForEach(visibleDays) { day in
                Section {
                    ForEach(day.deadlines) { deadline in
                        NavigationLink(value: deadline) {
                            DeadlineRow(deadline: deadline, now: now)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                model.setCompleted(!deadline.isCompleted, on: deadline)
                            } label: {
                                Label(
                                    deadline.isCompleted ? "Not done" : "Done",
                                    systemImage: deadline.isCompleted ? "arrow.uturn.backward" : "checkmark"
                                )
                            }
                            .tint(deadline.isCompleted ? .gray : .green)
                        }
                    }
                } header: {
                    DayHeader(date: day.date, count: day.incompleteCount, now: now)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: Deadline.self) { deadline in
            DeadlineDetailView(deadline: deadline)
        }
        .refreshable {
            await model.syncAll()
            now = Date()
        }
        .task(id: focusDate) {
            now = Date()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle(isOn: Binding(
                    get: { model.settings.showsCompleted },
                    set: { model.settings.showsCompleted = $0 }
                )) {
                    Label("Show completed", systemImage: "checkmark.circle")
                }

                Button {
                    Task { await model.syncAll() }
                } label: {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                }
            } label: {
                Label("Options", systemImage: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var bannerSection: some View {
        let failures = SourceFailure.list(
            canvas: model.canvasState.failure,
            learningSuite: model.learningSuiteState.failure
        )

        if !failures.isEmpty {
            Section {
                ForEach(failures) { entry in
                    SyncStatusBanner(
                        source: entry.source,
                        failure: entry.failure,
                        onReconnect: { reconnectSource = entry.source },
                        onRetry: {
                            Task {
                                switch entry.source {
                                case .canvas: await model.syncCanvas()
                                case .learningSuite: await model.syncLearningSuite()
                                }
                            }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.isCanvasConnected && !model.isLearningSuiteConnected {
            EmptyStateView(
                symbol: "person.badge.key",
                title: "Nothing connected",
                message: "Connect Canvas and Learning Suite in Settings to see your deadlines here."
            )
        } else if let focusDate {
            EmptyStateView(
                symbol: "checkmark.circle",
                title: "Nothing due",
                message: "You have no deadlines on \(focusDate.formatted(date: .abbreviated, time: .omitted))."
            )
        } else {
            EmptyStateView(
                symbol: "checkmark.circle",
                title: "All clear",
                message: model.settings.showsCompleted
                    ? "Nothing is due right now."
                    : "Nothing outstanding. Turn on “Show completed” to see finished work."
            )
        }
    }

    // MARK: Data

    private var visibleDays: [DeadlineDay] {
        var items = deadlines
        if !model.settings.showsCompleted {
            items = items.filter { !$0.isCompleted }
        }
        if let focusDate {
            let day = calendar.startOfDay(for: focusDate)
            items = items.filter { calendar.isDate($0.dueDate, inSameDayAs: day) }
        }
        return DeadlineGrouping.byDay(items, calendar: calendar)
    }
}

/// Section header: a friendly day name, plus how many items are still open.
struct DayHeader: View {
    var date: Date
    var count: Int
    var now: Date

    private let calendar = Calendar.current

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(isPast ? .red : .secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count > 0 ? "\(title), \(count) outstanding" : title)
    }

    private var isPast: Bool {
        date < calendar.startOfDay(for: now)
    }

    private var title: String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let formatted = date.formatted(
            .dateTime.weekday(.abbreviated).month(.abbreviated).day()
        )
        if sameYear { return formatted }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }
}
