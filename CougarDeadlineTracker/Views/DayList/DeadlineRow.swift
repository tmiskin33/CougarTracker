import SwiftUI

/// One deadline in the list. Overdue items read differently at a glance — red
/// time, a filled marker — but never by colour alone, so the distinction
/// survives colour blindness and VoiceOver.
struct DeadlineRow: View {
    var deadline: Deadline
    var now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.title3)
                .foregroundStyle(statusTint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(deadline.title)
                    .font(.body)
                    .strikethrough(deadline.isCompleted, color: .secondary)
                    .foregroundStyle(deadline.isCompleted ? .secondary : .primary)
                    .lineLimit(3)

                HStack(spacing: 6) {
                    Label(deadline.courseLabel, systemImage: deadline.type.symbolName)
                        .labelStyle(.titleAndIcon)
                    Text("·")
                    Label(deadline.source.displayName, systemImage: deadline.source.symbolName)
                        .labelStyle(.titleAndIcon)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(deadline.dueDate, format: .dateTime.hour().minute())
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(isOverdue ? Color.red : .secondary)
                if isOverdue {
                    Text("Overdue")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(deadline.accessibilityDescription(asOf: now))
        .accessibilityAddTraits(.isButton)
    }

    private var isOverdue: Bool {
        deadline.isOverdue(asOf: now)
    }

    private var statusSymbol: String {
        if deadline.isCompleted { return "checkmark.circle.fill" }
        return isOverdue ? "exclamationmark.circle.fill" : "circle"
    }

    private var statusTint: Color {
        if deadline.isCompleted { return .secondary }
        return isOverdue ? .red : .accentColor
    }
}
