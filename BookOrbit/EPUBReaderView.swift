import SwiftUI
import EpubReaderLight

@Observable
class EPUBReaderViewModel {
    let fileId: Int
    let filename: String
    
    var isLoading = true
    var loadError: String? = nil
    var activeURL: URL? = nil
    
    @ObservationIgnored
    lazy var readerController = ReaderViewController(theme: .dark, eventsHandler: self)
    
    init(fileId: Int, filename: String) {
        self.fileId = fileId
        self.filename = filename
    }
    
    func downloadAndPrepare() {
        Task {
            let fileManager = FileManager.default
            let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!.standardizedFileURL
            let previewDir = cacheDir.appendingPathComponent("Previews", isDirectory: true).standardizedFileURL
            let targetURL = previewDir.appendingPathComponent(filename).standardizedFileURL
            
            do {
                if !fileManager.fileExists(atPath: previewDir.path) {
                    try fileManager.createDirectory(at: previewDir, withIntermediateDirectories: true, attributes: nil)
                }
                
                if await APIClient.shared.isMockMode {
                    if !fileManager.fileExists(atPath: targetURL.path) {
                        let dummyContent = "Mock EPUB data"
                        try dummyContent.write(to: targetURL, atomically: true, encoding: .utf8)
                    }
                    await MainActor.run {
                        self.activeURL = targetURL
                    }
                    try? await self.readerController.loadBook(url: targetURL)
                    return
                }
                
                if !fileManager.fileExists(atPath: targetURL.path) {
                    let headers = await APIClient.shared.getAuthHeaders()
                    let serverURLString = await APIClient.shared.getServerURL()
                    let cleanBase = serverURLString.hasSuffix("/") ? String(serverURLString.dropLast()) : serverURLString
                    guard let downloadURL = URL(string: "\(cleanBase)/api/v1/books/files/\(fileId)/serve") else {
                        throw APIError.invalidURL
                    }
                    var request = URLRequest(url: downloadURL)
                    for (key, value) in headers {
                        request.setValue(value, forHTTPHeaderField: key)
                    }
                    
                    let (tempURL, response) = try await URLSession.shared.download(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.badResponse
                    }
                    if httpResponse.statusCode != 200 {
                        throw NSError(domain: "EPUBReader", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status code \(httpResponse.statusCode)"])
                    }
                    
                    if fileManager.fileExists(atPath: targetURL.path) {
                        try fileManager.removeItem(at: targetURL)
                    }
                    try fileManager.moveItem(at: tempURL.standardizedFileURL, to: targetURL)
                }
                
                await MainActor.run {
                    self.activeURL = targetURL
                }
                try? await self.readerController.loadBook(url: targetURL)
                
            } catch {
                await MainActor.run {
                    var errorMsg = error.localizedDescription
                    if let data = try? Data(contentsOf: targetURL), data.count > 0 {
                        let hexSig = data.prefix(4).map { String(format: "%02X", $0) }.joined()
                        let prefix = String(data: data.prefix(150), encoding: .utf8) ?? "binary data"
                        errorMsg += "\nFile size: \(data.count) bytes\nHex signature: \(hexSig)\nFile preview: \(prefix)"
                    }
                    self.loadError = errorMsg
                    self.isLoading = false
                }
                let fileManager = FileManager.default
                try? fileManager.removeItem(at: targetURL)
            }
        }
    }
}

extension EPUBReaderViewModel: ReaderEventsHandler {
    func onSelect(word: String) {}
    
    func onBookLoaded() {
        Task { @MainActor in
            self.isLoading = false
        }
    }
    
    func onUpdated(savedData: EpubReaderLight.BookSavedData) {}
}

struct EPUBReaderView: View {
    @State private var viewModel: EPUBReaderViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var isControlsVisible = true
    
    init(fileId: Int, filename: String) {
        _viewModel = State(wrappedValue: EPUBReaderViewModel(fileId: fileId, filename: filename))
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            
            if let error = viewModel.loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text("Failed to load EPUB")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Close") {
                        dismiss()
                    }
                    .padding(.top)
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ReaderView(controller: viewModel.readerController)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            isControlsVisible.toggle()
                        }
                    }
                
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading EPUB...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding(32)
                    .background(Material.ultraThinMaterial)
                    .cornerRadius(16)
                }
                
                if isControlsVisible {
                    VStack {
                        HStack {
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                                    .shadow(radius: 4)
                            }
                            Spacer()
                        }
                        .padding()
                        Spacer()
                    }
                    .transition(.opacity)
                }
            }
        }
        .onAppear {
            viewModel.downloadAndPrepare()
        }
    }
}
