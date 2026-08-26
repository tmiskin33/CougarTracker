import SwiftUI
import WebKit

/// Hosts BYU's own sign-in flow and captures the resulting session cookies.
///
/// The password and any Duo prompt are handled by BYU's pages inside the WebView.
/// This app never sees, collects, or stores the NetID password — a custom login
/// form would both weaken that and break the moment Duo is enforced.
struct LearningSuiteWebLogin: UIViewRepresentable {
    let startURL: URL
    /// Called once the user is back on a Learning Suite page with cookies set.
    var onCapture: (LearningSuiteSession) -> Void
    var onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        // A non-persistent store keeps the login isolated from anything else and
        // means "sign out" genuinely clears it.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: startURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onCapture = onCapture
        context.coordinator.onFailure = onFailure
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onCapture: (LearningSuiteSession) -> Void
        var onFailure: (String) -> Void
        private var hasCaptured = false

        init(
            onCapture: @escaping (LearningSuiteSession) -> Void,
            onFailure: @escaping (String) -> Void
        ) {
            self.onCapture = onCapture
            self.onFailure = onFailure
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasCaptured,
                  let host = webView.url?.host?.lowercased(),
                  host.contains(LearningSuiteClient.defaultHost) else { return }

            // Landing back on Learning Suite is the signal that CAS (and Duo) let
            // the user through.
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                let relevant = cookies.filter { cookie in
                    let domain = cookie.domain.lowercased()
                    return domain.contains("byu.edu")
                }
                guard !relevant.isEmpty else { return }
                self.hasCaptured = true
                self.onCapture(LearningSuiteSession(cookies: relevant))
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            // A cancelled navigation is normal during a redirect chain.
            if (error as NSError).code == NSURLErrorCancelled { return }
            onFailure(error.localizedDescription)
        }
    }
}

/// The sheet the user sees: BYU's login, a cancel button, and an explanation of
/// exactly what the app keeps.
struct LearningSuiteLoginSheet: View {
    @Environment(\.dismiss) private var dismiss

    var startURL: URL
    var onCapture: (LearningSuiteSession) -> Void

    @State private var errorMessage: String?

    init(startURL: URL, onCapture: @escaping (LearningSuiteSession) -> Void) {
        self.startURL = startURL
        self.onCapture = onCapture
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.thinMaterial)
                }

                LearningSuiteWebLogin(
                    startURL: startURL,
                    onCapture: { session in
                        onCapture(session)
                        dismiss()
                    },
                    onFailure: { message in
                        errorMessage = message
                    }
                )
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("Sign in to Learning Suite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("This is BYU's own sign-in page. Your NetID password stays with BYU — the app keeps only the session cookie, in the keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }
}
