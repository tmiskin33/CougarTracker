import SwiftData
import SwiftUI

@main
struct CougarDeadlineTrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer
    @State private var model: AppModel

    init() {
        let container = Self.makeContainer()
        self.container = container
        let model = AppModel(container: container)
        _model = State(initialValue: model)

        // Registration has to happen before the app finishes launching. The
        // handler is only ever run later, so it can hold the model directly.
        BackgroundRefresh.register { model }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.refreshConnectionStatus()
                Task { await model.syncAll() }
            case .background:
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
    }

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Deadline.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A store that cannot be opened is almost always a schema change
            // during development. Start over rather than refusing to launch.
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            guard let container = try? ModelContainer(for: schema, configurations: [fallback]) else {
                fatalError("Could not create a model container: \(error)")
            }
            return container
        }
    }
}
