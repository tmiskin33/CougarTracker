import SwiftData
import SwiftUI

/// Connections, reminder timings, and the destructive options, in that order.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Query private var deadlines: [Deadline]

    @State private var reconnectSource: DeadlineSource?
    @State private var digestTime = Date()
    @State private var showsEraseConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                connectionsSection
                remindersSection
                dataSection
                advancedSection
                aboutSection
            }
            .navigationTitle("Settings")
            .reconnectSheet(for: $reconnectSource)
            .onAppear(perform: loadDigestTime)
            .confirmationDialog(
                "Erase everything?",
                isPresented: $showsEraseConfirmation,
                titleVisibility: .visible
            ) {
                Button("Erase", role: .destructive) {
                    try? model.eraseAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Signs out of both systems, deletes the cached deadlines, and cancels scheduled reminders. Nothing in Canvas or Learning Suite is changed.")
            }
        }
    }

    // MARK: Connections

    private var connectionsSection: some View {
        Section("Connections") {
            connectionRow(
                source: .canvas,
                isConnected: model.isCanvasConnected,
                state: model.canvasState
            )
            connectionRow(
                source: .learningSuite,
                isConnected: model.isLearningSuiteConnected,
                state: model.learningSuiteState
            )

            Button {
                Task { await model.syncAll() }
            } label: {
                Label("Refresh now", systemImage: "arrow.clockwise")
            }
            .disabled(model.canvasState.isSyncing || model.learningSuiteState.isSyncing)
        }
    }

    private func connectionRow(
        source: DeadlineSource,
        isConnected: Bool,
        state: SourceSyncState
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(source.displayName, systemImage: source.symbolName)
                Spacer()
                statusLabel(isConnected: isConnected, state: state)
            }

            if let failure = state.failure {
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 16) {
                Button(isConnected ? "Sign in again" : "Connect") {
                    reconnectSource = source
                }
                .font(.footnote)

                if isConnected {
                    Button("Disconnect", role: .destructive) {
                        try? model.disconnect(source)
                    }
                    .font(.footnote)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusLabel(isConnected: Bool, state: SourceSyncState) -> some View {
        switch state {
        case .syncing:
            ProgressView()
        case .failed:
            Label("Problem", systemImage: "exclamationmark.circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(.red)
        case .idle(let lastSyncedAt, _):
            if let lastSyncedAt {
                Text(lastSyncedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(isConnected ? "Connected" : "Not connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .notConfigured:
            Text("Not connected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Reminders

    private var remindersSection: some View {
        Section {
            ForEach(AppSettings.reminderChoices) { choice in
                Toggle(choice.label, isOn: Binding(
                    get: { model.settings.reminderOffsets.contains(choice.minutes) },
                    set: { isOn in
                        var offsets = Set(model.settings.reminderOffsets)
                        if isOn { offsets.insert(choice.minutes) } else { offsets.remove(choice.minutes) }
                        model.settings.reminderOffsets = offsets.sorted(by: >)
                        Task { await model.rescheduleNotifications() }
                    }
                ))
            }

            Toggle("Daily summary", isOn: Binding(
                get: { model.settings.dailyDigestEnabled },
                set: {
                    model.settings.dailyDigestEnabled = $0
                    Task { await model.rescheduleNotifications() }
                }
            ))

            if model.settings.dailyDigestEnabled {
                DatePicker(
                    "Summary time",
                    selection: $digestTime,
                    displayedComponents: .hourAndMinute
                )
                .onChange(of: digestTime) { _, newValue in
                    model.settings.setDailyDigestTime(newValue)
                    Task { await model.rescheduleNotifications() }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Reminders are scheduled on this device. iOS allows about 60 pending at once, so the soonest ones are scheduled first.")
        }
    }

    // MARK: Data

    private var dataSection: some View {
        Section {
            Toggle("Show completed items", isOn: Binding(
                get: { model.settings.showsCompleted },
                set: { model.settings.showsCompleted = $0 }
            ))

            LabeledContent("Cached deadlines", value: "\(deadlines.count)")
        } header: {
            Text("Data")
        } footer: {
            Text("Deadlines are cached on device, so the list and calendar work offline. Refreshing needs a connection.")
        }
    }

    // MARK: Advanced

    private var advancedSection: some View {
        Section {
            LabeledContent("Canvas site") {
                TextField("byu.instructure.com", text: Binding(
                    get: { model.settings.canvasHost },
                    set: { model.settings.canvasHost = $0 }
                ))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            LabeledContent("Learning Suite path") {
                TextField(AppSettings.defaultLearningSuitePath, text: Binding(
                    get: { model.settings.learningSuiteAssignmentsPath },
                    set: { model.settings.learningSuiteAssignmentsPath = $0 }
                ))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
        } header: {
            Text("Advanced")
        } footer: {
            Text("If Learning Suite moves its assignments page, pointing the app at the new path can be enough to get syncing again.")
        }
    }

    private var aboutSection: some View {
        Section {
            Button(role: .destructive) {
                showsEraseConfirmation = true
            } label: {
                Label("Erase everything", systemImage: "trash")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Credentials live in the iOS keychain and never leave this device. The app talks only to Canvas and Learning Suite.")
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("Version \(version)")
                }
            }
        }
    }

    private func loadDigestTime() {
        var components = DateComponents()
        components.hour = model.settings.dailyDigestHour
        components.minute = model.settings.dailyDigestMinute
        digestTime = Calendar.current.date(from: components) ?? Date()
    }
}
