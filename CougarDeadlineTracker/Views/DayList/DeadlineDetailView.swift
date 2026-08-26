import SwiftUI

/// The full record for one item, plus the way back to where it came from.
struct DeadlineDetailView: View {
    @Environment(AppModel.self) private var model
    var deadline: Deadline

    init(deadline: Deadline) {
        self.deadline = deadline
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(deadline.title)
                        .font(.title3.weight(.semibold))
                    Text(deadline.courseName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Due") {
                LabeledContent("Date") {
                    Text(deadline.dueDate, format: .dateTime.weekday(.wide).month().day().year())
                }
                LabeledContent("Time") {
                    Text(deadline.dueDate, format: .dateTime.hour().minute())
                }
                if deadline.isOverdue(asOf: Date()) {
                    Label("Overdue", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }

            Section("Details") {
                LabeledContent("Source") {
                    Label(deadline.source.displayName, systemImage: deadline.source.symbolName)
                }
                LabeledContent("Type") {
                    Label(deadline.type.displayName, systemImage: deadline.type.symbolName)
                }
                if !deadline.courseCode.isEmpty {
                    LabeledContent("Course code", value: deadline.courseCode)
                }
                LabeledContent("Last synced") {
                    Text(deadline.lastSyncedAt, format: .relative(presentation: .named))
                }
            }

            if let details = deadline.details, !details.isEmpty {
                Section("Description") {
                    Text(details)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    model.setCompleted(!deadline.isCompleted, on: deadline)
                } label: {
                    Label(
                        deadline.isCompleted ? "Mark as not done" : "Mark as done",
                        systemImage: deadline.isCompleted ? "arrow.uturn.backward" : "checkmark.circle"
                    )
                }

                if let url = deadline.url {
                    Link(destination: url) {
                        Label("Open in \(deadline.source.displayName)", systemImage: "arrow.up.right.square")
                    }
                }
            } footer: {
                if deadline.url == nil {
                    Text("This item didn't come with a link back to \(deadline.source.displayName).")
                }
            }
        }
        .navigationTitle(deadline.courseLabel)
        .navigationBarTitleDisplayMode(.inline)
    }
}
