import SwiftUI
import WebKit

struct WebReaderView: UIViewRepresentable {
    let bookId: Int
    let fileId: Int
    let serverURL: String
    let token: String?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let userContentController = WKUserContentController()

        // Inject token into localStorage or cookies so the Vue webapp auto-authenticates
        if let token = token {
            let jsString = """
                localStorage.setItem('auth_token', '\(token)');
                document.cookie = "auth_token=\(token); path=/";
            """
            let userScript = WKUserScript(source: jsString, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userContentController.addUserScript(userScript)
        }

        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground

        if let cleanServerURL = URL(string: serverURL),
           let url = URL(string: "\(cleanServerURL.absoluteString)/read/\(bookId)/\(fileId)") {
            var request = URLRequest(url: url)
            if let token = token {
                // Also send it in the initial request just in case
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            webView.load(request)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct WebReaderSheetView: View {
    let bookId: Int
    let fileId: Int
    let filename: String
    @Environment(\.dismiss) var dismiss

    @State private var serverURL: String = ""
    @State private var token: String? = nil
    @State private var isReady = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                if isReady {
                    WebReaderView(bookId: bookId, fileId: fileId, serverURL: serverURL, token: token)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ProgressView("Connecting to Reader...")
                }
            }
            .navigationTitle(filename)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button("Close") {
                dismiss()
            })
            .onAppear {
                Task {
                    let authHeaders = await APIClient.shared.getAuthHeaders()
                    let urlStr = await APIClient.shared.getServerURL()
                    let cleanBase = urlStr.hasSuffix("/") ? String(urlStr.dropLast()) : urlStr

                    await MainActor.run {
                        self.serverURL = cleanBase
                        if let authHeader = authHeaders["Authorization"], authHeader.hasPrefix("Bearer ") {
                            self.token = String(authHeader.dropFirst(7))
                        }
                        self.isReady = true
                    }
                }
            }
        }
    }
}
