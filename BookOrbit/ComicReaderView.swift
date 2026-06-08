import SwiftUI
import ZIPFoundation

struct ComicReaderView: View {
    let fileId: Int
    let filename: String
    
    @State private var images: [URL] = []
    @State private var currentIndex: Int = 0
    @State private var isLoading = true
    @State private var loadError: String? = nil
    @State private var isControlsVisible = true
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Extracting Comic...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            } else if let error = loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text("Failed to load comic")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Close") {
                        dismiss()
                    }
                    .padding(.top)
                    .buttonStyle(.borderedProminent)
                }
            } else if images.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("No images found in archive.")
                        .font(.headline)
                        .foregroundColor(.white)
                        
                    Button("Close") {
                        dismiss()
                    }
                    .padding(.top)
                    .buttonStyle(.borderedProminent)
                }
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(0..<images.count, id: \.self) { index in
                        if let image = UIImage(contentsOfFile: images[index].path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .tag(index)
                                .onTapGesture {
                                    withAnimation {
                                        isControlsVisible.toggle()
                                    }
                                }
                        } else {
                            Text("Failed to load image")
                                .foregroundColor(.red)
                                .tag(index)
                        }
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .ignoresSafeArea()
            }
            
            // Overlay Controls
            if isControlsVisible && !isLoading {
                VStack {
                    HStack {
                        Button(action: {
                            cleanupTempFiles()
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .shadow(radius: 4)
                        }
                        Spacer()
                        if !images.isEmpty {
                            Text("\(currentIndex + 1) / \(images.count)")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .onAppear(perform: extractAndLoad)
    }
    
    private func extractAndLoad() {
        Task {
            let fileManager = FileManager.default
            let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!.standardizedFileURL
            let previewDir = cacheDir.appendingPathComponent("Previews", isDirectory: true).standardizedFileURL
            let sourceURL = previewDir.appendingPathComponent(filename).standardizedFileURL
            
            let ext = sourceURL.pathExtension.lowercased()
            if ext == "cbr" {
                await MainActor.run {
                    self.loadError = "CBR (RAR format) is not natively supported yet. Please use CBZ (ZIP format) comics instead."
                    self.isLoading = false
                }
                return
            }
            
            do {
                if !fileManager.fileExists(atPath: previewDir.path) {
                    try fileManager.createDirectory(at: previewDir, withIntermediateDirectories: true, attributes: nil)
                }
                
                if await APIClient.shared.isMockMode {
                    let mockImages = try await generateMockComicImages(count: 5)
                    await MainActor.run {
                        self.images = mockImages
                        self.isLoading = false
                    }
                    return
                }
                
                if !fileManager.fileExists(atPath: sourceURL.path) {
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
                        throw NSError(domain: "ComicReader", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status code \(httpResponse.statusCode)"])
                    }
                    
                    if fileManager.fileExists(atPath: sourceURL.path) {
                        try fileManager.removeItem(at: sourceURL)
                    }
                    try fileManager.moveItem(at: tempURL.standardizedFileURL, to: sourceURL)
                }
                
                let extractDir = cacheDir.appendingPathComponent("ComicExtract_\(fileId)", isDirectory: true).standardizedFileURL
                if fileManager.fileExists(atPath: extractDir.path) {
                    try fileManager.removeItem(at: extractDir)
                }
                try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true, attributes: nil)
                
                try fileManager.unzipItem(at: sourceURL, to: extractDir)
                
                var imageFiles: [URL] = []
                let enumerator = fileManager.enumerator(at: extractDir, includingPropertiesForKeys: nil)
                while let fileURL = enumerator?.nextObject() as? URL {
                    let fileExt = fileURL.pathExtension.lowercased()
                    if ["jpg", "jpeg", "png", "webp", "gif"].contains(fileExt) {
                        imageFiles.append(fileURL)
                    }
                }
                
                imageFiles.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                
                await MainActor.run {
                    self.images = imageFiles
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    var errorMsg = error.localizedDescription
                    if let data = try? Data(contentsOf: sourceURL), data.count > 0 {
                        let hexSig = data.prefix(4).map { String(format: "%02X", $0) }.joined()
                        let prefix = String(data: data.prefix(150), encoding: .utf8) ?? "binary data"
                        errorMsg += "\nFile size: \(data.count) bytes\nHex signature: \(hexSig)\nFile preview: \(prefix)"
                    } else if let attrs = try? fileManager.attributesOfItem(atPath: sourceURL.path), let size = attrs[.size] as? UInt64 {
                        errorMsg += "\nFile size: \(size) bytes"
                    }
                    self.loadError = errorMsg
                    self.isLoading = false
                }
                
                // Delete the corrupted file so it gets re-downloaded next time
                try? fileManager.removeItem(at: sourceURL)
            }
        }
    }
    
    private func cleanupTempFiles() {
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let extractDir = cacheDir.appendingPathComponent("ComicExtract_\(fileId)", isDirectory: true)
        if fileManager.fileExists(atPath: extractDir.path) {
            try? fileManager.removeItem(at: extractDir)
        }
    }
    
    private func generateMockComicImages(count: Int) async throws -> [URL] {
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let extractDir = cacheDir.appendingPathComponent("ComicExtract_Mock", isDirectory: true)
        
        if !fileManager.fileExists(atPath: extractDir.path) {
            try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        var urls: [URL] = []
        for i in 1...count {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1200))
            let img = renderer.image { ctx in
                UIColor.darkGray.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 1200))
                
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 48),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraphStyle
                ]
                let str = NSAttributedString(string: "Mock Page \(i)\n\n\(filename)", attributes: attrs)
                str.draw(in: CGRect(x: 100, y: 500, width: 600, height: 200))
            }
            if let data = img.jpegData(compressionQuality: 0.8) {
                let url = extractDir.appendingPathComponent(String(format: "page_%03d.jpg", i))
                try data.write(to: url)
                urls.append(url)
            }
        }
        return urls
    }
}
