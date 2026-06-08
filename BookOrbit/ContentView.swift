import SwiftUI
import PDFKit
import WebKit
 

struct ContentView: View {
    @StateObject private var audioPlayer = AudioPlayerManager.shared
    @AppStorage("app_theme") private var appTheme = 0
    @AppStorage("show_all_libraries") private var showAllLibraries = false
    @State private var isLoggedIn = false
    @State private var isShowingSettings = false
    @State private var isConnecting = false
    
    // Onboarding Form States
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var authError: String?
    
    // Dashboard States
    @State private var libraries: [Library] = []
    @State private var selectedLibrary: Library?
    @State private var books: [BookItem] = []
    @State private var selectedBook: BookItem?
    
    @State private var isLoadingLibraries = false
    @State private var isLoadingBooks = false
    @State private var libraryError: String?
    
    // Document Reading States
    @State private var downloadError: String? = nil
    @State private var activeWebReaderFile: DocumentFileInfo? = nil
    @State private var libraryWebReaderFile: DocumentFileInfo? = nil
    @State private var activelyDownloadingFileId: Int? = nil
    @State private var isLoadingDetail = false
    @State private var detailError: String? = nil
    @State private var selectedBookProgress: ServerAudioProgress? = nil
    
    // Search States
    @State private var searchText = ""
    @State private var librarySearchText = ""
    
    // Shelves States
    @State private var continueListening: [BookItem] = []
    @State private var continueReading: [BookItem] = []
    @State private var recentlyAdded: [BookItem] = []
    @State private var isLoadingShelves = false
    
    private var displayedLibraries: [Library] {
        if showAllLibraries {
            return libraries
        } else {
            return libraries.filter { library in
                let nameLower = library.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if nameLower == "my audiobooks" || nameLower.contains("mock") {
                    return true
                }
                return nameLower == "audiobooks" || nameLower == "audiobook"
            }
        }
    }
    
    private var filteredContinueListening: [BookItem] {
        if searchText.isEmpty { return continueListening }
        return continueListening.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.authors?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    private var filteredContinueReading: [BookItem] {
        if searchText.isEmpty { return continueReading }
        return continueReading.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.authors?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    private var filteredRecentlyAdded: [BookItem] {
        let base = showAllLibraries ? recentlyAdded : recentlyAdded.filter { $0.isAudiobook }
        if searchText.isEmpty { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.authors?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    private var filteredLibraryBooks: [BookItem] {
        if librarySearchText.isEmpty { return books }
        return books.filter {
            $0.title.localizedCaseInsensitiveContains(librarySearchText) ||
            ($0.authors?.localizedCaseInsensitiveContains(librarySearchText) ?? false)
        }
    }
    
    var body: some View {
        ZStack {
            if !isLoggedIn {
                onboardingView
            } else {
                dashboardView
            }
            
            if let book = selectedBook {
                // Dimmed background that is tappable to dismiss
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            selectedBook = nil
                        }
                    }
                    .transition(.opacity)
                
                // Bottom slide-up drawer
                VStack {
                    Spacer()
                    VStack(spacing: 0) {
                        // Close button header
                        HStack {
                            Spacer()
                            Button(action: {
                                withAnimation {
                                    selectedBook = nil
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, 16)
                                    .padding(.top, 12)
                            }
                        }
                        
                        bookDetailsView(book: book)
                    }
                    .frame(height: UIScreen.main.bounds.height * 0.8)
                    .background(Color(uiColor: .systemBackground))
                    .cornerRadius(20)
                    .shadow(radius: 12)
                    .transition(.move(edge: .bottom))
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .onAppear(perform: checkLoginStatus)
        .preferredColorScheme(preferredColorScheme)
        .sheet(item: $activeWebReaderFile) { fileInfo in
            WebReaderSheetView(bookId: fileInfo.bookId, fileId: fileInfo.fileId, filename: fileInfo.filename, format: fileInfo.format)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(
                showAllLibraries: $showAllLibraries,
                appTheme: $appTheme,
                serverURL: serverURL,
                username: username,
                onLogout: handleLogout
            )
        }
        .alert(isPresented: Binding(
            get: { downloadError != nil },
            set: { if !$0 { downloadError = nil } }
        )) {
            Alert(
                title: Text("Download Error"),
                message: Text(downloadError ?? "An error occurred while loading the e-book."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private var preferredColorScheme: ColorScheme? {
        switch appTheme {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
    
    // MARK: - Onboarding/Login View
    
    private var onboardingView: some View {
        ZStack {
            // Elegant background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    Spacer().frame(height: 40)
                    
                    // Logo & Header
                    VStack(spacing: 12) {
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 72))
                            .foregroundColor(.accentColor)
                            .shadow(color: .accentColor.opacity(0.3), radius: 15, x: 0, y: 5)
                        
                        Text("BookOrbit")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text("Your Self-Hosted Digital Library")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                    
                    // Login Card
                    VStack(spacing: 20) {
                        Text("Connect to Server")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Server URL")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            
                            TextField("e.g. http://192.168.1.100:5000 (or 'mock')", text: $serverURL)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .keyboardType(.URL)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            
                            TextField("Enter username", text: $username)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            
                            SecureField("Enter password", text: $password)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        if let error = authError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                        
                        Button(action: handleConnect) {
                            HStack {
                                Spacer()
                                if isConnecting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Connect")
                                        .fontWeight(.bold)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .disabled(isConnecting)
                        
                        Text("Use 'mock' as Server URL to explore locally.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(24)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.06), radius: 15, x: 0, y: 5)
                    .padding(.horizontal)
                    
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Dashboard View
    
    private var dashboardView: some View {
        NavigationView {
            ZStack {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if isLoadingLibraries {
                        Spacer()
                        ProgressView("Syncing libraries...")
                        Spacer()
                    } else if let error = libraryError {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.red)
                            Text("Failed to sync libraries")
                                .font(.headline)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            Button("Retry") {
                                syncLibraries()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                // Libraries section
                                Text("Libraries")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)
                                    .padding(.top)
                                
                                if displayedLibraries.isEmpty {
                                    VStack(spacing: 12) {
                                        Image(systemName: "folder.badge.minus")
                                            .font(.system(size: 48))
                                            .foregroundColor(.secondary)
                                        Text(libraries.isEmpty ? "No libraries found on your server." : "No audiobook libraries displayed.")
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                        if !libraries.isEmpty {
                                            Button("Show All Libraries") {
                                                showAllLibraries = true
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                    .padding(.top, 40)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                } else {
                                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                        ForEach(displayedLibraries) { library in
                                            Button(action: {
                                                selectedLibrary = library
                                                loadBooks(for: library)
                                            }) {
                                                libraryCard(library: library)
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                
                                // Horizontally scrolling dashboard shelves
                                if isLoadingShelves {
                                    HStack {
                                        Spacer()
                                        ProgressView("Loading shelves...")
                                            .font(.caption)
                                        Spacer()
                                    }
                                    .padding(.vertical)
                                } else {
                                    if !filteredContinueListening.isEmpty {
                                        dashboardShelf(title: "Continue Listening", books: filteredContinueListening)
                                    }
                                    
                                    if showAllLibraries && !filteredContinueReading.isEmpty {
                                        dashboardShelf(title: "Continue Reading", books: filteredContinueReading)
                                    }
                                    
                                    if !filteredRecentlyAdded.isEmpty {
                                        dashboardShelf(title: "Recently Added", books: filteredRecentlyAdded)
                                    }
                                    
                                    if !searchText.isEmpty && filteredContinueListening.isEmpty && filteredContinueReading.isEmpty && filteredRecentlyAdded.isEmpty {
                                        VStack(spacing: 12) {
                                            Image(systemName: "magnifyingglass")
                                                .font(.system(size: 48))
                                                .foregroundColor(.secondary)
                                            Text("No matches found for \"\(searchText)\"")
                                                .font(.headline)
                                                .foregroundColor(.secondary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 40)
                                    }
                                }
                                
                                // Instructions info card
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "info.circle.fill")
                                            .foregroundColor(.accentColor)
                                        Text("CarPlay Enabled")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                    }
                                    
                                    Text("Connect your phone to your car's CarPlay display to navigate libraries and stream audiobooks on the road.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .cornerRadius(12)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            }
                            .padding(.bottom, 90) // Safe padding for player bar
                        }
                    }
                }
                
                // Bottom Audio Player Bar
                if audioPlayer.isPlaying || audioPlayer.currentTitle != nil {
                    VStack {
                        Spacer()
                        bottomPlayerBar
                    }
                }
            }
            .navigationBarTitle("BookOrbit", displayMode: .large)
            .navigationBarItems(
                trailing: HStack(spacing: 16) {
                    Button(action: syncLibraries) {
                        Image(systemName: "arrow.clockwise")
                    }
                    
                    Button(action: { isShowingSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            )
            // Push library browser
            .sheet(item: $selectedLibrary) { library in
                libraryBrowserView(library: library)
            }
            .searchable(text: $searchText, prompt: showAllLibraries ? "Search audiobooks & ebooks..." : "Search audiobooks...")
        }
    }
    
    // MARK: - Library Card Builder
    
    private func libraryCard(library: Library) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: iconForLibraryType(library.type))
                .font(.system(size: 32))
                .foregroundColor(.accentColor)
                .padding(12)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(library.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if library.type.lowercased() == "books" || library.type.lowercased() == "comics" {
                        Text("WIP")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(4)
                    }
                }
                
                Text(library.type.capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
    
    private func iconForLibraryType(_ type: String) -> String {
        switch type.lowercased() {
        case "audiobooks":
            return "headphones"
        case "books":
            return "book.fill"
        case "comics":
            return "sparkles"
        default:
            return "folder.fill"
        }
    }
    
    // MARK: - Library Browser View
    
    private func libraryBrowserView(library: Library) -> some View {
        NavigationView {
            ZStack {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if library.type.lowercased() == "books" || library.type.lowercased() == "comics" {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("This section is under active development. Document reading may fail or be unstable.")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                    }
                    
                    if isLoadingBooks {
                        Spacer()
                        ProgressView("Loading catalog...")
                        Spacer()
                    } else if filteredLibraryBooks.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "folder.badge.minus")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text(librarySearchText.isEmpty ? "This library is empty." : "No matches found for \"\(librarySearchText)\"")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                                ForEach(filteredLibraryBooks) { book in
                                    Button(action: { loadBookDetail(book: book) }) {
                                        bookGridItem(book: book)
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
                
                if let book = selectedBook {
                    // Dimmed background that is tappable to dismiss
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                selectedBook = nil
                            }
                        }
                        .transition(.opacity)
                    
                    // Bottom slide-up drawer
                    VStack {
                        Spacer()
                        VStack(spacing: 0) {
                            // Close button header
                            HStack {
                                Spacer()
                                Button(action: {
                                    withAnimation {
                                        selectedBook = nil
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                        .padding(.trailing, 16)
                                        .padding(.top, 12)
                                }
                            }
                            
                            bookDetailsView(book: book)
                        }
                        .frame(height: UIScreen.main.bounds.height * 0.8)
                        .background(Color(uiColor: .systemBackground))
                        .cornerRadius(20)
                        .shadow(radius: 12)
                        .transition(.move(edge: .bottom))
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationBarTitle(library.name, displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                selectedLibrary = nil
                librarySearchText = "" // clear search when closing
            })
            .searchable(text: $librarySearchText, prompt: "Search in \(library.name)...")
            .sheet(item: $libraryWebReaderFile) { fileInfo in
                WebReaderSheetView(bookId: fileInfo.bookId, fileId: fileInfo.fileId, filename: fileInfo.filename, format: fileInfo.format)
            }
        }
    }
    
    private func bookGridItem(book: BookItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cover Image
            if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(uiColor: .secondarySystemBackground)
                        .overlay(Image(systemName: book.isAudiobook ? "headphones" : "book").foregroundColor(.secondary))
                }
                .frame(height: 180)
                .cornerRadius(12)
                .clipped()
            } else {
                Color(uiColor: .secondarySystemBackground)
                    .frame(height: 180)
                    .cornerRadius(12)
                    .overlay(Image(systemName: book.isAudiobook ? "headphones" : "book").foregroundColor(.secondary))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let author = book.authors {
                    Text(author)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack {
                    Image(systemName: book.isAudiobook ? "headphones" : "doc.text")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                    
                    Text(book.isAudiobook ? "Audiobook" : "E-Book")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Book Details & Playback Sheet
    
    private func bookDetailsView(book: BookItem) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Cover
                if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxHeight: 280)
                    .cornerRadius(16)
                    .shadow(radius: 10)
                    .padding(.top, 32)
                }
                
                // Metadata
                VStack(spacing: 8) {
                    Text(book.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    if let author = book.authors {
                        Text(author)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    
                    if book.isAudiobook, let duration = book.files.first(where: { $0.isAudio })?.durationSeconds, duration > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                            Text("Total Length: \(formatDuration(duration))")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                
                // Playback Control Dashboard (Audiobook specific)
                if book.isAudiobook {
                    VStack(spacing: 16) {
                        Text("AUDIOBOOK PLAYER")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        let isCurrentBookActive = audioPlayer.currentBookId == Int(book.id)
                        
                        if isCurrentBookActive {
                            // Active playback progress slider
                            VStack(spacing: 8) {
                                Slider(value: Binding(
                                    get: { audioPlayer.currentTime },
                                    set: { newValue in
                                        audioPlayer.seek(to: newValue)
                                    }
                                ), in: 0...max(1.0, audioPlayer.duration))
                                .accentColor(.accentColor)
                                
                                HStack {
                                    Text(formatTimeInterval(audioPlayer.currentTime))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatTimeInterval(audioPlayer.duration))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal)
                        } else if let progress = selectedBookProgress {
                            // Static progress from server
                            VStack(spacing: 8) {
                                ProgressView(value: min(100.0, max(0.0, progress.percentage)), total: 100.0)
                                    .tint(.accentColor)
                                
                                let totalDuration = book.files.first(where: { $0.isAudio })?.durationSeconds ?? 0.0
                                HStack {
                                    Group {
                                        if totalDuration > 0 {
                                            Text("Last played: \(formatTimeInterval(progress.positionSeconds)) / \(formatTimeInterval(totalDuration))")
                                        } else {
                                            Text("Last played: \(formatTimeInterval(progress.positionSeconds))")
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int(progress.percentage))%")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        HStack(spacing: 32) {
                            Button(action: {
                                if isCurrentBookActive {
                                    audioPlayer.skipBackward()
                                }
                            }) {
                                Image(systemName: "gobackward.15")
                                    .font(.title)
                                    .foregroundColor(isCurrentBookActive ? .primary : .secondary)
                            }
                            .disabled(!isCurrentBookActive)
                            
                            Button(action: {
                                if isCurrentBookActive {
                                    audioPlayer.togglePlayback()
                                } else {
                                    if let audioUrlString = book.audioUrl, let url = URL(string: audioUrlString) {
                                        let bookId = Int(book.id) ?? 0
                                        let fileId = book.files.first(where: { $0.isAudio })?.fileId ?? 0
                                        audioPlayer.playAudio(url: url, bookId: bookId, fileId: fileId, title: book.title, author: book.authors ?? "Unknown")
                                    }
                                }
                            }) {
                                Image(systemName: audioPlayer.isPlaying && isCurrentBookActive ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 64))
                                    .foregroundColor(.accentColor)
                            }
                            
                            Button(action: {
                                if isCurrentBookActive {
                                    audioPlayer.skipForward()
                                }
                            }) {
                                Image(systemName: "goforward.15")
                                    .font(.title)
                                    .foregroundColor(isCurrentBookActive ? .primary : .secondary)
                            }
                            .disabled(!isCurrentBookActive)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }
                
                // E-Book Reader Dashboard (for books with readable files but no audiobook)
                if !book.isAudiobook, let readableFile = book.files.first(where: { isReadableFormat($0.format) }) {
                    VStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Text("E-BOOK READER")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            Text("WIP")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .cornerRadius(4)
                        }
                        
                        Button(action: {
                            let format = readableFile.format?.lowercased() ?? "epub"
                            var filename = readableFile.filename ?? "document"
                            if !filename.lowercased().hasSuffix(".\(format)") {
                                filename = "\(filename).\(format)"
                            }
                            let bookIdInt = Int(book.id) ?? 0
                            handleReadableFile(bookId: bookIdInt, fileId: readableFile.fileId, filename: filename, format: format)
                        }) {
                            HStack(spacing: 12) {
                                if activelyDownloadingFileId == readableFile.fileId {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("Preparing...")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                } else {
                                    Image(systemName: "book.fill")
                                        .font(.title2)
                                    Text("Read Now")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 48)
                            .background(activelyDownloadingFileId == readableFile.fileId ? Color.gray : Color.accentColor)
                            .cornerRadius(28)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .disabled(activelyDownloadingFileId != nil)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }
                
                // Summary Description
                VStack(alignment: .leading, spacing: 12) {
                    Text("Synopsis")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(book.summary ?? "No synopsis available.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // Files List Section
                if !book.files.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Files in this Book")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.bottom, 4)
                        
                        ForEach(book.files) { file in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.filename ?? "File: \(file.role)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    HStack(spacing: 8) {
                                        Text(file.format?.uppercased() ?? "UNKNOWN")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.1))
                                            .foregroundColor(.accentColor)
                                            .cornerRadius(4)
                                        
                                        if isReadableFormat(file.format) {
                                            Text("WIP")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.15))
                                                .foregroundColor(.orange)
                                                .cornerRadius(4)
                                        }
                                        
                                        if let size = file.sizeBytes {
                                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        if let duration = file.durationSeconds, duration > 0 {
                                            Text(formatDuration(duration))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                if file.isAudio {
                                    Button(action: {
                                        if audioPlayer.currentFileId == file.fileId {
                                            audioPlayer.togglePlayback()
                                        } else {
                                            Task {
                                                let serverURL = await APIClient.shared.getServerURL()
                                                let audioUrlString = "\(serverURL)/api/v1/books/files/\(file.fileId)/serve"
                                                if let url = URL(string: audioUrlString) {
                                                    await MainActor.run {
                                                        let bookId = Int(book.id) ?? 0
                                                        audioPlayer.playAudio(url: url, bookId: bookId, fileId: file.fileId, title: file.filename ?? book.title, author: book.authors ?? "Unknown")
                                                    }
                                                }
                                            }
                                        }
                                    }) {
                                        Image(systemName: audioPlayer.isPlaying && audioPlayer.currentFileId == file.fileId ? "pause.circle.fill" : "play.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.accentColor)
                                    }
                                } else if isReadableFormat(file.format) {
                                    Button(action: {
                                        let format = file.format?.lowercased() ?? "epub"
                                        var filename = file.filename ?? "document"
                                        if !filename.lowercased().hasSuffix(".\(format)") {
                                            filename = "\(filename).\(format)"
                                        }
                                        let bookIdInt = Int(book.id) ?? 0
                                        handleReadableFile(bookId: bookIdInt, fileId: file.fileId, filename: filename, format: format)
                                    }) {
                                        if activelyDownloadingFileId == file.fileId {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                                                .frame(width: 24, height: 24)
                                        } else {
                                            Image(systemName: "book.circle.fill")
                                                .font(.title2)
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .disabled(activelyDownloadingFileId != nil)
                                }
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }
                
                // Loading Detail indicator
                if isLoadingDetail {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Updating book files...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                
                Spacer()
            }
        }
    }
    
    // MARK: - Now Playing Bottom Bar Builder
    
    private var bottomPlayerBar: some View {
        HStack(spacing: 16) {
            // Tappable metadata area to reopen player
            HStack(spacing: 16) {
                Image(systemName: "headphones")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
                    .padding(12)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(audioPlayer.currentTitle ?? "Streaming Audiobook")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(audioPlayer.currentAuthor ?? "Unknown Author")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                reopenCurrentBookPlayer()
            }
            
            Spacer()
            
            Button(action: { audioPlayer.togglePlayback() }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: -4)
        .padding()
        .transition(.move(edge: .bottom))
    }
    
    private func reopenCurrentBookPlayer() {
        guard let bookId = audioPlayer.currentBookId else { return }
        // Create a basic representation of the book item to open the drawer
        // and fetch detailed metadata in the background.
        let book = BookItem(
            id: String(bookId),
            title: audioPlayer.currentTitle ?? "Streaming Audiobook",
            authors: audioPlayer.currentAuthor ?? "Unknown Author",
            summary: nil,
            coverUrl: nil,
            audioUrl: nil,
            isAudiobook: true,
            files: []
        )
        loadBookDetail(book: book)
    }
    
    // MARK: - Action Helpers
    
    private func checkLoginStatus() {
        if let savedURL = UserDefaults.standard.string(forKey: "server_url"), savedURL != "mock" {
            self.serverURL = savedURL
        }
        if let savedUser = UserDefaults.standard.string(forKey: "username") {
            self.username = savedUser
        }
        
        Task {
            let auth = await APIClient.shared.isAuthenticated
            await MainActor.run {
                self.isLoggedIn = auth
                if auth {
                    syncLibraries()
                }
            }
        }
    }
    
    private func handleConnect() {
        isConnecting = true
        authError = nil
        
        Task {
            do {
                try await APIClient.shared.login(url: serverURL, username: username, password: password)
                await MainActor.run {
                    isConnecting = false
                    isLoggedIn = true
                    syncLibraries()
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    authError = "Connection failed. Please check Server URL and credentials."
                }
            }
        }
    }
    
    private func handleLogout() {
        Task {
            await APIClient.shared.logout()
            await MainActor.run {
                self.isLoggedIn = false
                self.libraries = []
                self.selectedLibrary = nil
                self.books = []
            }
        }
    }
    
    private func syncLibraries() {
        isLoadingLibraries = true
        libraryError = nil
        Task {
            do {
                let fetchedLibraries = try await APIClient.shared.getLibraries()
                await MainActor.run {
                    self.libraries = fetchedLibraries
                    self.isLoadingLibraries = false
                }
                
                // Fetch shelves asynchronously
                loadDashboardShelves()
            } catch {
                await MainActor.run {
                    if let apiError = error as? APIError, case .unauthorized = apiError {
                        self.handleLogout()
                    } else {
                        self.libraryError = error.localizedDescription
                    }
                    self.isLoadingLibraries = false
                }
            }
        }
    }
    
    private func loadDashboardShelves() {
        self.isLoadingShelves = true
        Task {
            // Fetch continue-reading
            var inProgressBooks: [BookItem] = []
            do {
                inProgressBooks = try await APIClient.shared.getDashboardScroller(type: "continue-reading")
            } catch {
                print("Error loading continue-reading shelf: \(error)")
            }
            
            // Fetch recently-added
            var addedBooks: [BookItem] = []
            do {
                addedBooks = try await APIClient.shared.getDashboardScroller(type: "recently-added")
            } catch {
                print("Error loading recently-added shelf: \(error)")
            }
            
            await MainActor.run {
                // Filter inProgressBooks on client-side
                self.continueListening = inProgressBooks.filter { $0.isAudiobook }
                self.continueReading = inProgressBooks.filter { !$0.isAudiobook }
                self.recentlyAdded = addedBooks
                self.isLoadingShelves = false
            }
        }
    }
    
    private func loadBooks(for library: Library) {
        isLoadingBooks = true
        books = []
        Task {
            do {
                let fetchedBooks = try await APIClient.shared.getBooks(libraryId: library.id)
                await MainActor.run {
                    self.books = fetchedBooks
                    self.isLoadingBooks = false
                }
            } catch {
                await MainActor.run {
                    if let apiError = error as? APIError, case .unauthorized = apiError {
                        self.handleLogout()
                    }
                    self.isLoadingBooks = false
                }
            }
        }
    }
    
    private func loadBookDetail(book: BookItem) {
        self.isLoadingDetail = true
        self.detailError = nil
        self.selectedBookProgress = nil
        self.selectedBook = book // Presents details sheet immediately
        
        Task {
            do {
                if let bookId = Int(book.id) {
                    let detail = try await APIClient.shared.getBookDetail(bookId: bookId)
                    let progress = await APIClient.shared.getAudioProgress(bookId: bookId)
                    await MainActor.run {
                        self.selectedBook = detail
                        self.selectedBookProgress = progress
                        self.isLoadingDetail = false
                    }
                } else {
                    // Mock mode (mock ids are "601", etc. which are numeric now)
                    await MainActor.run {
                        self.isLoadingDetail = false
                    }
                }
            } catch {
                await MainActor.run {
                    if let apiError = error as? APIError, case .unauthorized = apiError {
                        self.selectedBook = nil
                        self.handleLogout()
                    } else {
                        self.detailError = error.localizedDescription
                    }
                    self.isLoadingDetail = false
                }
            }
        }
    }
    
    private func getDestinationURL(filename: String) -> URL {
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let previewDir = cacheDir.appendingPathComponent("Previews", isDirectory: true)
        if !fileManager.fileExists(atPath: previewDir.path) {
            try? fileManager.createDirectory(at: previewDir, withIntermediateDirectories: true)
        }
        return previewDir.appendingPathComponent(filename)
    }
    
    private func handleReadableFile(bookId: Int, fileId: Int, filename: String, format: String) {
        let fmt = format.lowercased()
        let fileInfo = DocumentFileInfo(bookId: bookId, fileId: fileId, filename: filename, format: fmt)
        if isReadableFormat(fmt) {
            if selectedLibrary != nil {
                self.libraryWebReaderFile = fileInfo
            } else {
                self.activeWebReaderFile = fileInfo
            }
        } else {
            self.downloadError = "Format \(fmt) is not natively supported yet."
        }
    }
    
    private func cleanupPreviews() {
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let previewDir = cacheDir.appendingPathComponent("Previews", isDirectory: true)
        if fileManager.fileExists(atPath: previewDir.path) {
            try? fileManager.removeItem(at: previewDir)
        }
    }
    
    private func isReadableFormat(_ format: String?) -> Bool {
        guard let format = format?.lowercased() else { return false }
        return ["pdf", "epub", "txt", "cbz", "cbr", "mobi", "azw", "azw3", "fb2"].contains(format)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? ""
    }
    
    private func formatTimeInterval(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hrs = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }
    
    private func dashboardShelf(title: String, books: [BookItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(books) { book in
                        Button(action: { loadBookDetail(book: book) }) {
                            VStack(alignment: .leading, spacing: 8) {
                                // Cover Image
                                if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Color(uiColor: .secondarySystemBackground)
                                            .overlay(Image(systemName: book.isAudiobook ? "headphones" : "book").foregroundColor(.secondary))
                                    }
                                    .frame(width: 110, height: 160)
                                    .cornerRadius(8)
                                    .clipped()
                                } else {
                                    Color(uiColor: .secondarySystemBackground)
                                        .frame(width: 110, height: 160)
                                        .cornerRadius(8)
                                        .overlay(Image(systemName: book.isAudiobook ? "headphones" : "book").foregroundColor(.secondary))
                                }
                                
                                Text(book.title)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .frame(width: 110, alignment: .leading)
                                
                                if let author = book.authors {
                                    Text(author)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 110, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - File Info Structure

struct DocumentFileInfo: Identifiable {
    let id = UUID()
    let bookId: Int
    let fileId: Int
    let filename: String
    let format: String
}

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var showAllLibraries: Bool
    @Binding var appTheme: Int
    let serverURL: String
    let username: String
    let onLogout: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Library Filters")) {
                    Toggle(isOn: $showAllLibraries) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Show All Libraries")
                                .font(.body)
                            Text("If disabled, only libraries named 'audiobooks' will be visible, optimizing the app for audiobook listening.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("App Theme")) {
                    Picker("Theme", selection: $appTheme) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Connected Server")) {
                    HStack {
                        Text("URL")
                        Spacer()
                        Text(serverURL.isEmpty ? "Not connected" : serverURL)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    HStack {
                        Text("Username")
                        Spacer()
                        Text(username.isEmpty ? "Not logged in" : username)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                        onLogout()
                    }) {
                        HStack {
                            Spacer()
                            Text("Log Out")
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }
            .navigationBarTitle("Settings", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

