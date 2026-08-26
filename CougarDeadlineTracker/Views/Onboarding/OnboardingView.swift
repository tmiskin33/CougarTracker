import SwiftUI

/// First-run setup. Canvas and Learning Suite are two separate sign-ins, in two
/// separate steps, because they are two separate systems with nothing shared
/// between them — one succeeding says nothing about the other.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step: Step = .welcome
    @State private var showsLearningSuiteLogin = false

    enum Step: Int, CaseIterable {
        case welcome, canvas, learningSuite, notifications
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcome
                case .canvas: canvasStep
                case .learningSuite: learningSuiteStep
                case .notifications: notificationsStep
                }
            }
            .animation(.default, value: step)
        }
        .sheet(isPresented: $showsLearningSuiteLogin) {
            LearningSuiteLoginSheet(
                startURL: URL(string: "https://\(LearningSuiteClient.defaultHost)")!
            ) { session in
                try? model.saveLearningSuiteSession(session)
                Task { await model.syncLearningSuite() }
            }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Cougar Deadline Tracker")
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Canvas and Learning Suite deadlines in one list, on one calendar.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    step = .canvas
                } label: {
                    Text("Get started").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Text("You'll sign in to each system separately. Nothing leaves your phone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private var canvasStep: some View {
        CanvasTokenSetupView {
            step = .learningSuite
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Skip") { step = .learningSuite }
            }
        }
    }

    private var learningSuiteStep: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Learning Suite has no public API.")
                        .font(.subheadline.weight(.semibold))
                    Text("""
                    To show its deadlines, the app signs in through BYU's own login page \
                    and then reads the assignments page the way a browser would.
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("What that means") {
                bullet("shield.lefthalf.filled", "Your NetID password is typed into BYU's page, not this app. Only the session cookie is kept, in the keychain.")
                bullet("exclamationmark.triangle", "If BYU redesigns Learning Suite, this will stop working until the app is updated. You'll see an error, not silence.")
                bullet("doc.text.magnifyingglass", "Automated reading of a BYU system may fall outside how BYU intends the site to be used, even with your own account. That's your call.")
            }

            Section {
                Button {
                    showsLearningSuiteLogin = true
                } label: {
                    Label("Sign in to Learning Suite", systemImage: "person.badge.key")
                }

                if model.isLearningSuiteConnected {
                    Label("Connected", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }

            Section {
                Button("Continue") { step = .notifications }
                Button("Skip Learning Suite") { step = .notifications }
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Learning Suite")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var notificationsStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "bell.badge")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Reminders")
                    .font(.title2.weight(.semibold))
                Text("""
                A nudge a day before and a few hours before each deadline, plus a \
                morning summary of what's due. All scheduled on this phone — you can \
                change the timings later in Settings.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        await model.requestNotificationPermission()
                        finish()
                    }
                } label: {
                    Text("Turn on reminders").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("Not now") { finish() }
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
        }
    }

    private func finish() {
        model.settings.hasCompletedOnboarding = true
        Task { await model.syncAll() }
    }
}
