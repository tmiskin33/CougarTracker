import SwiftUI

/// Collects and verifies a Canvas personal access token.
///
/// A token rather than a password: Canvas issues it, the user can revoke it from
/// their account page at any time, and it never gives this app their BYU login.
struct CanvasTokenSetupView: View {
    @Environment(AppModel.self) private var model

    var onConnected: () -> Void

    init(onConnected: @escaping () -> Void) {
        self.onConnected = onConnected
    }

    @State private var token = ""
    @State private var host = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @State private var connectedName: String?
    @State private var showsInstructions = false

    var body: some View {
        Form {
            Section {
                DisclosureGroup("How to get a token", isExpanded: $showsInstructions) {
                    VStack(alignment: .leading, spacing: 10) {
                        instruction(1, "Open Canvas in a browser and sign in.")
                        instruction(2, "Go to Account › Settings.")
                        instruction(3, "Under Approved Integrations, tap “+ New Access Token”.")
                        instruction(4, "Give it a purpose (“Deadline tracker”) and leave the expiry blank.")
                        instruction(5, "Copy the token — Canvas shows it only once — and paste it below.")

                        Link(destination: canvasSettingsURL) {
                            Label("Open Canvas settings", systemImage: "safari")
                        }
                        .font(.footnote)
                        .padding(.top, 2)
                    }
                    .font(.footnote)
                    .padding(.vertical, 4)
                }
            }

            Section {
                SecureField("Paste your Canvas token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { Task { await connect() } }
            } header: {
                Text("Access token")
            } footer: {
                Text("Stored in the iOS keychain, on this device only. Revoke it any time from Canvas › Account › Settings.")
            }

            Section {
                TextField("byu.instructure.com", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("Canvas site")
            } footer: {
                Text("Change this only if your Canvas lives somewhere other than byu.instructure.com.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let connectedName {
                Section {
                    Label("Connected as \(connectedName)", systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }

            Section {
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Text("Connect Canvas")
                        Spacer()
                        if isVerifying { ProgressView() }
                    }
                }
                .disabled(token.trimmed.isEmpty || isVerifying)
            }
        }
        .navigationTitle("Canvas")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if host.isEmpty { host = model.settings.canvasHost }
        }
    }

    private var canvasSettingsURL: URL {
        URL(string: "https://\(host.trimmed.nilIfBlank ?? AppSettings.defaultCanvasHost)/profile/settings")
            ?? URL(string: "https://byu.instructure.com/profile/settings")!
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(text)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func connect() async {
        let trimmedToken = token.trimmed
        let trimmedHost = host.trimmed.nilIfBlank ?? AppSettings.defaultCanvasHost
        guard !trimmedToken.isEmpty else { return }

        isVerifying = true
        errorMessage = nil
        defer { isVerifying = false }

        do {
            // Verify before saving, so a typo never becomes a stored credential
            // that fails quietly later.
            let name = try await CanvasSyncService.verify(host: trimmedHost, token: trimmedToken)
            model.settings.canvasHost = trimmedHost
            try model.saveCanvasToken(trimmedToken)
            connectedName = name
            await model.syncCanvas()
            onConnected()
        } catch let failure as SyncFailure {
            errorMessage = failure.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
