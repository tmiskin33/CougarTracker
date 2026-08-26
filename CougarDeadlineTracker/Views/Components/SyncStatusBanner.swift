import SwiftUI

/// Surfaces a failed sync where the user will actually see it, with the one
/// action that fixes it. A scraper that silently returns nothing is the failure
/// mode this exists to prevent.
struct SyncStatusBanner: View {
    var source: DeadlineSource
    var failure: SyncFailure
    var onReconnect: () -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(source.displayName)
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: failure.symbolName)
            }

            Text(failure.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = failure.underlyingDescription {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                if failure.requiresReauthentication {
                    Button("Sign in again", action: onReconnect)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                } else {
                    Button("Try again", action: onRetry)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(source.displayName) sync problem. \(failure.message)")
    }
}

/// A count badge for a calendar day. Past three or four dots the eye cannot count
/// them, so anything above the threshold becomes a number.
struct DeadlineCountBadge: View {
    var count: Int
    var isOverdue: Bool
    var dotThreshold = 3

    var body: some View {
        Group {
            if count <= 0 {
                Color.clear.frame(width: 1, height: 6)
            } else if count <= dotThreshold {
                HStack(spacing: 2) {
                    ForEach(0..<count, id: \.self) { _ in
                        Circle().frame(width: 5, height: 5)
                    }
                }
            } else {
                Text("\(count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(tint.opacity(0.18)))
            }
        }
        .foregroundStyle(tint)
        .accessibilityHidden(true)
    }

    private var tint: Color {
        isOverdue ? .red : .accentColor
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
    }
}

/// Pairs a source with its failure so the banners can be driven by a `ForEach`.
struct SourceFailure: Identifiable {
    var source: DeadlineSource
    var failure: SyncFailure

    var id: String { source.rawValue }

    static func list(canvas: SyncFailure?, learningSuite: SyncFailure?) -> [SourceFailure] {
        var result: [SourceFailure] = []
        if let canvas { result.append(SourceFailure(source: .canvas, failure: canvas)) }
        if let learningSuite {
            result.append(SourceFailure(source: .learningSuite, failure: learningSuite))
        }
        return result
    }
}
