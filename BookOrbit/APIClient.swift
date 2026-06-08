import Foundation

enum APIError: Error {
    case invalidURL
    case badResponse
    case requestFailed(String)
    case unauthorized
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server URL is invalid."
        case .badResponse:
            return "The server returned an invalid or empty response."
        case .requestFailed(let message):
            return message
        case .unauthorized:
            return "Unauthorized. Please check your username and password."
        }
    }
}

actor APIClient {
    static let shared = APIClient()
    
    // In-memory properties
    private var activeURLString: String? {
        UserDefaults.standard.string(forKey: "server_url")
    }
    
    private var activeToken: String? {
        UserDefaults.standard.string(forKey: "auth_token")
    }
    
    // Check if the client is currently authenticated (or in mock mode)
    var isAuthenticated: Bool {
        if isMockMode { return true }
        return activeURLString != nil && activeToken != nil
    }
    
    // Check if the configured URL is mock
    var isMockMode: Bool {
        guard let url = activeURLString else { return false }
        return url == "mock" || url.contains("mock")
    }
    
    /// Retrieve stored server URL
    func getServerURL() -> String {
        return activeURLString ?? ""
    }
    
    /// Helper to safely build URLs via string interpolation and stripping trailing/leading slashes
    private func getEndpoint(path: String) throws -> URL {
        guard let urlString = activeURLString else {
            throw APIError.invalidURL
        }
        let cleanBase = urlString.hasSuffix("/") ? String(urlString.dropLast()) : urlString
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: "\(cleanBase)/\(cleanPath)") else {
            throw APIError.invalidURL
        }
        return url
    }
    
    /// Retrieve authentication headers for HTTP requests
    func getAuthHeaders() async -> [String: String] {
        await ensureValidToken()
        var headers: [String: String] = ["Content-Type": "application/json"]
        if let token = activeToken {
            headers["Authorization"] = "Bearer \(token)"
        }
        return headers
    }
    
    private func isTokenExpired(token: String) -> Bool {
        let parts = token.components(separatedBy: ".")
        guard parts.count > 1 else { return true }
        
        var payload = parts[1]
        let padding = payload.count % 4
        if padding > 0 {
            payload += String(repeating: "=", count: 4 - padding)
        }
        
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else {
            return true
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return true
        }
        
        guard let exp = json["exp"] as? Double else {
            return false
        }
        
        let expDate = Date(timeIntervalSince1970: exp)
        return expDate.timeIntervalSinceNow < 300 // Expiry check with 5 mins buffer
    }
    
    func ensureValidToken() async {
        guard !isMockMode, let url = activeURLString, let username = UserDefaults.standard.string(forKey: "username"), let token = activeToken else {
            return
        }
        
        if isTokenExpired(token: token) {
            print("[APIClient] Token is expired or expiring soon. Attempting silent re-login...")
            if let passwordData = KeychainHelper.shared.read(service: "test.BookOrbit.auth", account: username),
               let password = String(data: passwordData, encoding: .utf8) {
                do {
                    try await login(url: url, username: username, password: password)
                    print("[APIClient] Silent re-login succeeded. Token refreshed.")
                } catch {
                    print("[APIClient] Silent re-login failed: \(error)")
                }
            }
        }
    }
    
    /// Authenticate user against BookOrbit NestJS server
    func login(url: String, username: String, password: String) async throws {
        // Clean up URL input
        var cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanURL.isEmpty {
            throw APIError.invalidURL
        }
        
        // Handle mock mode trigger
        if cleanURL.lowercased() == "mock" || cleanURL.contains("mock") {
            UserDefaults.standard.set("mock", forKey: "server_url")
            UserDefaults.standard.set("mock_token", forKey: "auth_token")
            UserDefaults.standard.set(username, forKey: "username")
            return
        }
        
        // Ensure scheme exists
        if !cleanURL.lowercased().hasPrefix("http://") && !cleanURL.lowercased().hasPrefix("https://") {
            cleanURL = "http://" + cleanURL
        }
        
        let cleanBase = cleanURL.hasSuffix("/") ? String(cleanURL.dropLast()) : cleanURL
        guard let loginEndpoint = URL(string: "\(cleanBase)/api/v1/auth/login") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: loginEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = ["username": username, "password": password]
        request.httpBody = try? JSONEncoder().encode(body)
        
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.requestFailed(error.localizedDescription)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.badResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw APIError.requestFailed("Server returned error code \(httpResponse.statusCode)")
        }
        
        // Attempt to parse token or accessToken from NestJS server response
        let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
        guard let token = loginResponse.token ?? loginResponse.accessToken else {
            throw APIError.badResponse
        }
        
        // Persist session details
        UserDefaults.standard.set(cleanBase, forKey: "server_url")
        UserDefaults.standard.set(token, forKey: "auth_token")
        UserDefaults.standard.set(username, forKey: "username")
        
        // Save password securely in Keychain
        if let passwordData = password.data(using: .utf8) {
            KeychainHelper.shared.save(passwordData, service: "test.BookOrbit.auth", account: username)
        }
    }
    
    /// Discard token and URL to return to onboarding
    func logout() {
        if let username = UserDefaults.standard.string(forKey: "username") {
            KeychainHelper.shared.delete(service: "test.BookOrbit.auth", account: username)
        }
        UserDefaults.standard.removeObject(forKey: "server_url")
        UserDefaults.standard.removeObject(forKey: "auth_token")
        UserDefaults.standard.removeObject(forKey: "username")
    }
    
    /// Fetch all libraries from BookOrbit server
    func getLibraries() async throws -> [Library] {
        if isMockMode {
            return mockLibraries()
        }
        
        let endpoint = try getEndpoint(path: "/api/v1/libraries")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        for (key, value) in await getAuthHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
            // Save raw response to scratch directory for inspection
            let scratchPath = "/Users/kegan/.gemini/antigravity/scratch/raw_library_response.json"
            try? data.write(to: URL(fileURLWithPath: scratchPath))
        } catch {
            throw APIError.requestFailed(error.localizedDescription)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.badResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        
        if httpResponse.statusCode != 200 {
            let serverMsg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.requestFailed("HTTP \(httpResponse.statusCode): \(serverMsg)")
        }
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Raw Library JSON: \(jsonString)")
        }
        
        do {
            return try JSONDecoder().decode([Library].self, from: data)
        } catch let decodingError as DecodingError {
            let rawString = String(data: data, encoding: .utf8) ?? ""
            print("Failed to decode Library: \(decodingError). Raw data: \(rawString)")
            throw APIError.requestFailed("Decoding failed: \(decodingError.localizedDescription)")
        }
    }
    
    /// Fetch books/audiobooks within a library
    func getBooks(libraryId: Int) async throws -> [BookItem] {
        if isMockMode {
            return mockBooks(for: libraryId)
        }
        
        let urlString = activeURLString ?? ""
        let endpoint = try getEndpoint(path: "/api/v1/libraries/\(libraryId)/books")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        for (key, value) in await getAuthHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Prepare request body with default pagination to retrieve up to 200 books
        let queryBody: [String: Any] = [
            "pagination": [
                "page": 0,
                "size": 200
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: queryBody)
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
            // Save raw response to scratch directory for inspection
            let scratchPath = "/Users/kegan/.gemini/antigravity/scratch/raw_books_response.json"
            try? data.write(to: URL(fileURLWithPath: scratchPath))
        } catch {
            throw APIError.requestFailed(error.localizedDescription)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.badResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 201 {
            let serverMsg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.requestFailed("HTTP \(httpResponse.statusCode): \(serverMsg)")
        }
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Raw Books JSON: \(jsonString)")
        }
        
        do {
            let pageResponse = try JSONDecoder().decode(BooksPageResponse.self, from: data)
            return pageResponse.items.map { card in
                // Detect audiobooks based on formats
                let audioFormats = ["m4b", "mp3", "m4a", "opus", "ogg", "flac"]
                let hasAudio = card.files.contains { file in
                    guard let fmt = file.format?.lowercased() else { return false }
                    return audioFormats.contains(fmt)
                }
                
                // Construct audio stream URL for the first audio file found
                var audioUrl: String? = nil
                if hasAudio, let firstAudioFile = card.files.first(where: {
                    guard let fmt = $0.format?.lowercased() else { return false }
                    return audioFormats.contains(fmt)
                }) {
                    audioUrl = "\(urlString)/api/v1/books/files/\(firstAudioFile.id)/serve"
                }
                
                // Construct cover URL
                let coverUrl = card.hasCover ? "\(urlString)/api/v1/books/\(card.id)/cover" : nil
                
                // Convert card.files to BookFile
                let bookFiles = card.files.map { file in
                    BookFile(fileId: file.id, format: file.format, role: file.role, sizeBytes: file.sizeBytes, filename: nil, durationSeconds: nil)
                }
                
                return BookItem(
                    id: String(card.id),
                    title: card.title ?? "Untitled",
                    authors: card.authors.joined(separator: ", "),
                    summary: nil, // Summary will be loaded on details view
                    coverUrl: coverUrl,
                    audioUrl: audioUrl,
                    isAudiobook: hasAudio,
                    files: bookFiles
                )
            }
        } catch let decodingError as DecodingError {
            let rawString = String(data: data, encoding: .utf8) ?? ""
            print("Failed to decode BookItem: \(decodingError). Raw data: \(rawString)")
            throw APIError.requestFailed("Decoding failed: \(decodingError.localizedDescription)")
        }
    }
    
    /// Fetch detailed metadata and file entries for a specific book
    func getBookDetail(bookId: Int) async throws -> BookItem {
        if isMockMode {
            // Find in mockBooks
            let allMocks = [6, 5, 7].flatMap { mockBooks(for: $0) }
            if let found = allMocks.first(where: { $0.id == String(bookId) }) {
                return found
            }
            throw APIError.badResponse
        }
        
        let urlString = activeURLString ?? ""
        let endpoint = try getEndpoint(path: "/api/v1/books/\(bookId)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        for (key, value) in await getAuthHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.badResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        
        if httpResponse.statusCode != 200 {
            throw APIError.badResponse
        }
        
        let detail = try JSONDecoder().decode(ServerBookDetail.self, from: data)
        
        let audioFormats = ["m4b", "mp3", "m4a", "opus", "ogg", "flac"]
        let hasAudio = detail.files.contains { file in
            guard let fmt = file.format?.lowercased() else { return false }
            return audioFormats.contains(fmt)
        }
        
        var audioUrl: String? = nil
        if hasAudio, let firstAudioFile = detail.files.first(where: {
            guard let fmt = $0.format?.lowercased() else { return false }
            return audioFormats.contains(fmt)
        }) {
            audioUrl = "\(urlString)/api/v1/books/files/\(firstAudioFile.id)/serve"
        }
        
        let coverUrl = "\(urlString)/api/v1/books/\(detail.id)/cover"
        
        let bookFiles = detail.files.map { file in
            BookFile(
                fileId: file.id,
                format: file.format,
                role: file.role,
                sizeBytes: file.sizeBytes,
                filename: file.filename,
                durationSeconds: file.durationSeconds
            )
        }
        
        return BookItem(
            id: String(detail.id),
            title: detail.title ?? "Untitled",
            authors: detail.authors.map { $0.name }.joined(separator: ", "),
            summary: detail.description,
            coverUrl: coverUrl,
            audioUrl: audioUrl,
            isAudiobook: hasAudio,
            files: bookFiles
        )
    }
    
    /// Fetch dashboard book scroller (shelf) of a specific type
    func getDashboardScroller(type: String) async throws -> [BookItem] {
        if isMockMode {
            return mockScroller(for: type)
        }
        
        let urlString = activeURLString ?? ""
        let endpoint = try getEndpoint(path: "/api/v1/dashboard/scrollers/\(type)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        for (key, value) in await getAuthHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.badResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.badResponse
        }
        
        let cards = try JSONDecoder().decode([ServerBookCard].self, from: data)
        return cards.map { card in
            let audioFormats = ["m4b", "mp3", "m4a", "opus", "ogg", "flac"]
            let hasAudio = card.files.contains { file in
                guard let fmt = file.format?.lowercased() else { return false }
                return audioFormats.contains(fmt)
            }
            
            var audioUrl: String? = nil
            if hasAudio, let firstAudioFile = card.files.first(where: {
                guard let fmt = $0.format?.lowercased() else { return false }
                return audioFormats.contains(fmt)
            }) {
                audioUrl = "\(urlString)/api/v1/books/files/\(firstAudioFile.id)/serve"
            }
            
            let coverUrl = card.hasCover ? "\(urlString)/api/v1/books/\(card.id)/cover" : nil
            let bookFiles = card.files.map { file in
                BookFile(fileId: file.id, format: file.format, role: file.role, sizeBytes: file.sizeBytes, filename: nil, durationSeconds: nil)
            }
            
            return BookItem(
                id: String(card.id),
                title: card.title ?? "Untitled",
                authors: card.authors.joined(separator: ", "),
                summary: nil,
                coverUrl: coverUrl,
                audioUrl: audioUrl,
                isAudiobook: hasAudio,
                files: bookFiles
            )
        }
    }
    
    /// Fetch playback progress for an audiobook
    func getAudioProgress(bookId: Int) async -> ServerAudioProgress? {
        if isMockMode { return nil }
        
        do {
            let endpoint = try getEndpoint(path: "/api/v1/books/\(bookId)/audio-progress")
            var request = URLRequest(url: endpoint)
            request.httpMethod = "GET"
            for (key, value) in await getAuthHeaders() {
                request.setValue(value, forHTTPHeaderField: key)
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            return try JSONDecoder().decode(ServerAudioProgress.self, from: data)
        } catch {
            print("Error fetching audio progress: \(error)")
            return nil
        }
    }
    
    /// Save playback progress for an audiobook
    func saveAudioProgress(bookId: Int, fileId: Int, positionSeconds: Double, percentage: Double) async {
        if isMockMode { return }
        
        do {
            let endpoint = try getEndpoint(path: "/api/v1/books/\(bookId)/audio-progress")
            var request = URLRequest(url: endpoint)
            request.httpMethod = "PATCH"
            for (key, value) in await getAuthHeaders() {
                request.setValue(value, forHTTPHeaderField: key)
            }
            
            let body: [String: Any] = [
                "currentFileId": fileId,
                "positionSeconds": positionSeconds,
                "percentage": percentage
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            _ = try await URLSession.shared.data(for: request)
        } catch {
            print("Error saving audio progress: \(error)")
        }
    }
    
    // MARK: - Mock Data Generators
    
    private func mockLibraries() -> [Library] {
        return [
            Library(id: 6, name: "My Audiobooks", icon: "BookHeadphones"),
            Library(id: 5, name: "Sci-Fi Ebooks", icon: "LibraryBig"),
            Library(id: 7, name: "Graphic Novels", icon: "BookUser")
        ]
    }
    
    private func mockBooks(for libraryId: Int) -> [BookItem] {
        switch libraryId {
        case 6: // Audiobooks
            return [
                BookItem(id: "601",
                         title: "Project Hail Mary",
                         authors: "Andy Weir",
                         summary: "Ryland Grace is the sole survivor on a desperate, last-chance mission to save humanity from an extinction-level threat. The only problem is he doesn't know his name or what he is supposed to do.",
                         coverUrl: "https://covers.openlibrary.org/b/id/10543666-L.jpg",
                         audioUrl: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3",
                         isAudiobook: true,
                         files: [
                            BookFile(fileId: 6011, format: "mp3", role: "primary", sizeBytes: 42567900, filename: "Project Hail Mary Chapter 1.mp3", durationSeconds: 1200)
                         ]),
                BookItem(id: "602",
                         title: "Dune",
                         authors: "Frank Herbert",
                         summary: "Set on the desert planet Arrakis, Dune is the story of the boy Paul Atreides, heir to a noble family tasked with ruling an inhospitable world where the only thing of value is the spice 'melange'.",
                         coverUrl: "https://covers.openlibrary.org/b/id/10452331-L.jpg",
                         audioUrl: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3",
                         isAudiobook: true,
                         files: [
                            BookFile(fileId: 6021, format: "mp3", role: "primary", sizeBytes: 38240500, filename: "Dune Chapter 1.mp3", durationSeconds: 1150)
                         ]),
                BookItem(id: "603",
                         title: "The Hobbit",
                         authors: "J.R.R. Tolkien",
                         summary: "Bilbo Baggins is a hobbit who enjoys a comfortable, unambitious life, rarely traveling any farther than his pantry or cellar. But his contentment is disturbed when the wizard Gandalf and a company of dwarves arrive.",
                         coverUrl: "https://covers.openlibrary.org/b/id/10582967-L.jpg",
                         audioUrl: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3",
                         isAudiobook: true,
                         files: [
                            BookFile(fileId: 6031, format: "mp3", role: "primary", sizeBytes: 52199400, filename: "The Hobbit Chapter 1.mp3", durationSeconds: 1540)
                         ])
            ]
        case 5: // Ebooks
            return [
                BookItem(id: "501",
                         title: "Neuromancer",
                         authors: "William Gibson",
                         summary: "Case was the sharpest data-thief in the matrix—until he crossed the wrong people, who burned his nervous system with a wartime toxin. Now, a new employer offers him a cure in exchange for a final run.",
                         coverUrl: "https://covers.openlibrary.org/b/id/8301724-L.jpg",
                         audioUrl: nil,
                         isAudiobook: false,
                         files: [
                            BookFile(fileId: 5011, format: "epub", role: "primary", sizeBytes: 1045200, filename: "Neuromancer.epub", durationSeconds: nil)
                         ]),
                BookItem(id: "502",
                         title: "Foundation",
                         authors: "Isaac Asimov",
                         summary: "For twelve thousand years the Galactic Empire has ruled supreme. Now it is dying. Only Hari Seldon, creator of the revolutionary science of psychohistory, can foresee the future.",
                         coverUrl: "https://covers.openlibrary.org/b/id/8254425-L.jpg",
                         audioUrl: nil,
                         isAudiobook: false,
                         files: [
                            BookFile(fileId: 5021, format: "pdf", role: "primary", sizeBytes: 4567200, filename: "Foundation.pdf", durationSeconds: nil)
                         ])
            ]
        case 7: // Comics
            return [
                BookItem(id: "701",
                         title: "Watchmen",
                         authors: "Alan Moore & Dave Gibbons",
                         summary: "A world-altering conspiracy unfolds when a retired superhero is brutally murdered. His former colleagues must investigate, uncovering dark secrets that threaten humanity.",
                         coverUrl: "https://covers.openlibrary.org/b/id/8255956-L.jpg",
                         audioUrl: nil,
                         isAudiobook: false,
                         files: [
                            BookFile(fileId: 7011, format: "cbz", role: "primary", sizeBytes: 25421000, filename: "Watchmen Issue 1.cbz", durationSeconds: nil)
                         ])
            ]
        default:
            return []
        }
    }
    
    private func mockScroller(for type: String) -> [BookItem] {
        switch type {
        case "continue-reading":
            // In mock mode, return both an audiobook and an ebook to simulate the unified continue shelf
            return [mockBooks(for: 6)[0], mockBooks(for: 5)[0]]
        case "recently-added":
            return mockBooks(for: 6) + mockBooks(for: 5)
        default:
            return []
        }
    }
}

// Data Models
struct Library: Codable, Identifiable {
    let id: Int
    let name: String
    let icon: String?
    
    var type: String {
        guard let iconLower = icon?.lowercased() else { return "books" }
        if iconLower.contains("headphones") || name.lowercased().contains("audio") {
            return "audiobooks"
        } else if iconLower.contains("user") || name.lowercased().contains("comic") {
            return "comics"
        } else {
            return "books"
        }
    }
}

struct BookItem: Codable, Identifiable {
    let id: String
    let title: String
    let authors: String?
    let summary: String?
    let coverUrl: String?
    let audioUrl: String?
    let isAudiobook: Bool
    let files: [BookFile]
}

struct BookFile: Codable, Identifiable {
    var id: String { String(fileId) }
    let fileId: Int
    let format: String?
    let role: String
    let sizeBytes: Int?
    let filename: String?
    let durationSeconds: Double?
    
    var isAudio: Bool {
        guard let format = format?.lowercased() else { return false }
        return ["m4b", "mp3", "m4a", "opus", "ogg", "flac"].contains(format)
    }
}

struct LoginResponse: Codable {
    let token: String?
    let accessToken: String?
}

// NestJS Server API Response Structs (for internal parsing)
struct BooksPageResponse: Decodable {
    let items: [ServerBookCard]
    let total: Int
    let page: Int
    let size: Int
}

struct ServerBookCard: Decodable {
    let id: Int
    let title: String?
    let authors: [String]
    let files: [ServerBookFileRef]
    let hasCover: Bool
}

struct ServerBookFileRef: Decodable {
    let id: Int
    let format: String?
    let role: String
    let sizeBytes: Int?
}

struct ServerBookDetail: Decodable {
    let id: Int
    let title: String?
    let subtitle: String?
    let description: String?
    let authors: [ServerAuthorRef]
    let files: [ServerBookDetailFile]
}

struct ServerAuthorRef: Decodable {
    let id: Int
    let name: String
}

struct ServerBookDetailFile: Decodable {
    let id: Int
    let format: String?
    let role: String
    let sizeBytes: Int?
    let filename: String?
    let durationSeconds: Double?
}

struct ServerAudioProgress: Codable {
    let userId: Int
    let bookId: Int
    let percentage: Double
    let currentFileId: Int
    let positionSeconds: Double
}

class RedirectHandler: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var modifiedRequest = request
        // If redirecting to a different host (like S3), strip Authorization header
        if let originalHost = task.originalRequest?.url?.host, let newHost = request.url?.host, originalHost != newHost {
            modifiedRequest.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(modifiedRequest)
    }
}

// MARK: - Keychain Helper
class KeychainHelper {
    static let shared = KeychainHelper()
    
    @discardableResult
    func save(_ data: Data, service: String, account: String) -> OSStatus {
        let deleteQuery = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as [CFString : Any]
        
        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            print("[KeychainHelper] Warning: SecItemDelete failed with status \(deleteStatus)")
        }
        
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ] as [CFString : Any]
        
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus != errSecSuccess {
            print("[KeychainHelper] Error: SecItemAdd failed with status \(addStatus)")
        }
        return addStatus
    }
    
    func read(service: String, account: String) -> Data? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [CFString : Any]
        
        var dataTypeRef: AnyObject? = nil
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            return dataTypeRef as? Data
        } else if status != errSecItemNotFound {
            print("[KeychainHelper] Warning: SecItemCopyMatching failed with status \(status)")
        }
        return nil
    }
    
    @discardableResult
    func delete(service: String, account: String) -> OSStatus {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as [CFString : Any]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("[KeychainHelper] Warning: SecItemDelete failed with status \(status)")
        }
        return status
    }
}
