import SwiftUI

/// Decides between onboarding and the app proper.
///
/// Both sources are separate gates: the app is usable with one connected, but
/// setup is not "done" until the user has had the chance to connect both, and a
/// lapsed session sends them back to exactly the one that lapsed.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.settings.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .animation(.default, value: model.settings.hasCompletedOnboarding)
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Tab = .deadlines

    enum Tab: Hashable {
        case deadlines, calendar, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            DayListView()
                .tabItem {
                    Label("Deadlines", systemImage: "list.bullet")
                }
                .tag(Tab.deadlines)

            CalendarScreen()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(Tab.calendar)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
        .task {
            // A session that lapsed while the app was closed should be obvious
            // immediately, not on the first pull-to-refresh.
            model.refreshConnectionStatus()
            await model.syncAll()
        }
    }
}
