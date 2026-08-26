import SwiftUI

/// One place that knows how to re-authenticate either source, so every "sign in
/// again" button in the app behaves the same.
struct ReconnectSheet: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var source: DeadlineSource?

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: { source.map(ReconnectTarget.init) },
                set: { source = $0?.source }
            )) { target in
                switch target.source {
                case .canvas:
                    NavigationStack {
                        CanvasTokenSetupView {
                            source = nil
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { source = nil }
                            }
                        }
                    }
                case .learningSuite:
                    LearningSuiteLoginSheet(startURL: learningSuiteStartURL) { session in
                        try? model.saveLearningSuiteSession(session)
                        Task { await model.syncLearningSuite() }
                    }
                }
            }
    }

    private var learningSuiteStartURL: URL {
        URL(string: "https://\(LearningSuiteClient.defaultHost)")!
    }
}

private struct ReconnectTarget: Identifiable {
    var source: DeadlineSource
    var id: String { source.rawValue }

    init(_ source: DeadlineSource) {
        self.source = source
    }
}

extension View {
    /// Presents the right sign-in flow for whichever source is set.
    func reconnectSheet(for source: Binding<DeadlineSource?>) -> some View {
        modifier(ReconnectSheet(source: source))
    }
}
