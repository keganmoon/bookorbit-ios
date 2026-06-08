import CarPlay
import UIKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    
    var interfaceController: CPInterfaceController?
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        print("🚗 CarPlay didConnect called successfully!")
        self.interfaceController = interfaceController
        
        // Load the initial screen
        refreshCarPlayUI()
    }
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        print("🚗 CarPlay didDisconnect called.")
        self.interfaceController = nil
    }
    
    /// Redraws the root template depending on the user's login status
    private func refreshCarPlayUI() {
        print("🚗 CarPlay refreshing UI...")
        guard let interfaceController = interfaceController else {
            print("🚗 CarPlay refresh skipped: interfaceController is nil")
            return
        }
        
        Task {
            let authenticated = await APIClient.shared.isAuthenticated
            print("🚗 CarPlay authentication check completed. Authenticated: \(authenticated)")
            
            await MainActor.run {
                if authenticated {
                    print("🚗 CarPlay: setting root to Root Menu Template")
                    let rootTemplate = makeRootMenuTemplate()
                    interfaceController.setRootTemplate(rootTemplate, animated: true, completion: nil)
                } else {
                    print("🚗 CarPlay: setting root to Onboarding Required Template")
                    let rootTemplate = makeOnboardingRequiredTemplate()
                    interfaceController.setRootTemplate(rootTemplate, animated: true, completion: nil)
                }
            }
        }
    }
    
    // MARK: - Onboarding Required Template
    
    private func makeOnboardingRequiredTemplate() -> CPListTemplate {
        let instructionItem = CPListItem(
            text: "Authentication Required",
            detailText: "Please log in to BookOrbit on your iPhone first."
        )
        instructionItem.setImage(UIImage(systemName: "lock.fill") ?? UIImage())
        
        instructionItem.handler = { [weak self] item, completion in
            // Try checking login status again
            self?.refreshCarPlayUI()
            completion()
        }
        
        let section = CPListSection(items: [instructionItem])
        return CPListTemplate(title: "BookOrbit", sections: [section])
    }
    
    // MARK: - Root Menu Template
    
    private func makeRootMenuTemplate() -> CPListTemplate {
        let continueListeningItem = CPListItem(
            text: "Continue Listening",
            detailText: "Resume your in-progress audiobooks"
        )
        continueListeningItem.setImage(UIImage(systemName: "play.circle.fill") ?? UIImage())
        continueListeningItem.handler = { [weak self] item, completion in
            self?.pushContinueListening(completion: completion)
        }
        
        let browseAudiobooksItem = CPListItem(
            text: "Browse Audiobooks",
            detailText: "Explore all books in your Audiobooks library"
        )
        browseAudiobooksItem.setImage(UIImage(systemName: "headphones") ?? UIImage())
        browseAudiobooksItem.handler = { [weak self] item, completion in
            self?.pushAudiobooksLibrary(completion: completion)
        }
        
        let section = CPListSection(items: [continueListeningItem, browseAudiobooksItem])
        return CPListTemplate(title: "BookOrbit", sections: [section])
    }
    
    // MARK: - Continue Listening
    
    private func pushContinueListening(completion: @escaping () -> Void) {
        Task {
            do {
                print("🚗 CarPlay: Fetching continue-listening shelf...")
                let inProgressBooks = try await APIClient.shared.getDashboardScroller(type: "continue-reading")
                let audiobooks = inProgressBooks.filter { $0.isAudiobook }
                
                let items = audiobooks.map { book in
                    let item = CPListItem(
                        text: book.title,
                        detailText: book.authors ?? "Unknown Author"
                    )
                    item.setImage(UIImage(systemName: "headphones") ?? UIImage())
                    
                    item.handler = { _, itemCompletion in
                        if let audioUrlString = book.audioUrl, let url = URL(string: audioUrlString) {
                            let bookId = Int(book.id) ?? 0
                            let fileId = book.files.first(where: { $0.isAudio })?.fileId ?? 0
                            print("🚗 CarPlay: Playing continue-listening audiobook: \(book.title)")
                            AudioPlayerManager.shared.playAudio(url: url, bookId: bookId, fileId: fileId, title: book.title, author: book.authors ?? "Unknown")
                        }
                        itemCompletion()
                    }
                    return item
                }
                
                let section = CPListSection(items: items.isEmpty ? [CPListItem(text: "No In-Progress Audiobooks", detailText: "Start listening on your iPhone first")] : items)
                let continueListeningTemplate = CPListTemplate(title: "Continue Listening", sections: [section])
                
                await MainActor.run {
                    self.interfaceController?.pushTemplate(continueListeningTemplate, animated: true, completion: nil)
                }
            } catch {
                print("🚗 CarPlay Error: Failed to fetch continue-listening: \(error)")
                await MainActor.run {
                    self.presentErrorAlert(message: "Failed to load in-progress audiobooks.")
                }
            }
            completion()
        }
    }
    
    // MARK: - Audiobooks Library Catalog
    
    private func pushAudiobooksLibrary(completion: @escaping () -> Void) {
        Task {
            do {
                print("🚗 CarPlay: Fetching libraries to find Audiobooks...")
                let libraries = try await APIClient.shared.getLibraries()
                let audiobooksLibraries = libraries.filter { $0.type == "audiobooks" }
                
                if audiobooksLibraries.isEmpty {
                    let section = CPListSection(items: [CPListItem(text: "No Audiobooks Library Found", detailText: "Setup an Audiobooks library on your server")])
                    let emptyTemplate = CPListTemplate(title: "Audiobooks", sections: [section])
                    await MainActor.run {
                        self.interfaceController?.pushTemplate(emptyTemplate, animated: true, completion: nil)
                    }
                } else if audiobooksLibraries.count == 1 {
                    let library = audiobooksLibraries[0]
                    self.pushLibraryBooks(library: library, completion: completion)
                    return
                } else {
                    let items = audiobooksLibraries.map { library in
                        let item = CPListItem(
                            text: library.name,
                            detailText: "Audiobook Catalog"
                        )
                        item.setImage(UIImage(systemName: "headphones") ?? UIImage())
                        item.handler = { [weak self] _, itemCompletion in
                            self?.pushLibraryBooks(library: library, completion: itemCompletion)
                        }
                        return item
                    }
                    let section = CPListSection(items: items)
                    let multiTemplate = CPListTemplate(title: "Libraries", sections: [section])
                    await MainActor.run {
                        self.interfaceController?.pushTemplate(multiTemplate, animated: true, completion: nil)
                    }
                }
            } catch {
                print("🚗 CarPlay Error: Failed to load libraries: \(error)")
                await MainActor.run {
                    self.presentErrorAlert(message: "Failed to load Audiobooks library.")
                }
            }
            completion()
        }
    }
    
    private func pushLibraryBooks(library: Library, completion: @escaping () -> Void) {
        Task {
            do {
                print("🚗 CarPlay: Fetching books for library: \(library.name)...")
                let books = try await APIClient.shared.getBooks(libraryId: library.id)
                let audiobooks = books.filter { $0.isAudiobook }
                
                let items = audiobooks.map { book in
                    let item = CPListItem(
                        text: book.title,
                        detailText: book.authors ?? "Unknown Author"
                    )
                    item.setImage(UIImage(systemName: "headphones") ?? UIImage())
                    
                    item.handler = { _, itemCompletion in
                        if let audioUrlString = book.audioUrl, let url = URL(string: audioUrlString) {
                            let bookId = Int(book.id) ?? 0
                            let fileId = book.files.first(where: { $0.isAudio })?.fileId ?? 0
                            print("🚗 CarPlay: Playing audiobook: \(book.title)")
                            AudioPlayerManager.shared.playAudio(url: url, bookId: bookId, fileId: fileId, title: book.title, author: book.authors ?? "Unknown")
                        }
                        itemCompletion()
                    }
                    return item
                }
                
                let section = CPListSection(items: items.isEmpty ? [CPListItem(text: "No Audiobooks Found", detailText: "Add audio files to this library")] : items)
                let catalogTemplate = CPListTemplate(title: library.name, sections: [section])
                
                await MainActor.run {
                    self.interfaceController?.pushTemplate(catalogTemplate, animated: true, completion: nil)
                }
            } catch {
                print("🚗 CarPlay Error: Failed to load books: \(error)")
                await MainActor.run {
                    self.presentErrorAlert(message: "Failed to load catalog.")
                }
            }
            completion()
        }
    }
    
    // MARK: - Helper Methods
    
    private func presentErrorAlert(message: String) {
        let okAction = CPAlertAction(title: "OK", style: .default, handler: { _ in })
        let errorAlert = CPAlertTemplate(titleVariants: [message], actions: [okAction])
        self.interfaceController?.presentTemplate(errorAlert, animated: true, completion: nil)
    }
}
