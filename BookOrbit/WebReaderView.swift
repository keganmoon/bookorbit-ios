import SwiftUI
import WebKit

struct WebReaderView: UIViewRepresentable {
    let bookId: Int
    let fileId: Int
    let serverURL: String
    let token: String?
    let format: String

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
                localStorage.setItem('token', '\(token)');
                localStorage.setItem('accessToken', '\(token)');
                document.cookie = "auth_token=\(token); path=/";
                document.cookie = "token=\(token); path=/";
                document.cookie = "accessToken=\(token); path=/";
            """
            let userScript = WKUserScript(source: jsString, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userContentController.addUserScript(userScript)
        }

        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground

        if let cleanServerURL = URL(string: serverURL),
           let url = URL(string: "\(cleanServerURL.absoluteString)/read/\(bookId)/\(fileId)?format=\(format)") {
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
    let format: String
    @Environment(\.dismiss) var dismiss

    @State private var serverURL: String = ""
    @State private var token: String? = nil
    @State private var isReady = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                if isReady {
                    WebReaderView(bookId: bookId, fileId: fileId, serverURL: serverURL, token: token, format: format)
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

                    let tokenValue: String?
                    if let authHeader = authHeaders["Authorization"], authHeader.hasPrefix("Bearer ") {
                        tokenValue = String(authHeader.dropFirst(7))
                    } else {
                        tokenValue = nil
                    }

                    // Set cookies in WKWebsiteDataStore before displaying the WKWebView
                    if let token = tokenValue, let host = URL(string: cleanBase)?.host {
                        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
                        let cookieNames = ["auth_token", "token", "accessToken"]
                        
                        for name in cookieNames {
                            let properties: [HTTPCookiePropertyKey: Any] = [
                                .name: name,
                                .value: token,
                                .domain: host,
                                .path: "/",
                                .secure: cleanBase.hasPrefix("https") ? "TRUE" : "FALSE",
                                .expires: Date(timeIntervalSinceNow: 31536000) // 1 year
                            ]
                            if let cookie = HTTPCookie(properties: properties) {
                                await withCheckedContinuation { continuation in
                                    cookieStore.setCookie(cookie) {
                                        continuation.resume()
                                    }
                                }
                            }
                        }
                    }

                    await MainActor.run {
                        self.serverURL = cleanBase
                        self.token = tokenValue
                        self.isReady = true
                    }
                }
            }
        }
    }
}
