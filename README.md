# BookOrbit iOS Application & CarPlay Integration

Nativ iOS implementation for **BookOrbit**! SwiftUI client designed for streaming audiobooks and reading digital publications from your self-hosted BookOrbit server. 

By default, the app is tailored to operate as a dedicated **Audiobook Player**, but it can be configured in settings to expose E-Book and Comic libraries as well.

---

## Key Features

### 🎧 Audiobook-First Mode
- **Clean Focus:** Out of the box, the app limits the UI to shelves (`Continue Listening`, `Recently Added` audiobooks) and libraries named `"audiobooks"` (case-insensitive).
- **Settings Toggle:** A dedicated settings panel allows users to toggle "Show All Libraries" to reveal E-books (EPUB, PDF) and Comics (CBZ, ZIP) with visual **WIP** development tags.

### 🔑 Secure Login & Silent Session Renewal
- **Keychain Integration:** Passwords and credentials are securely stored using Apple's Keychain services under the `kSecAttrAccessibleAfterFirstUnlock` accessibility policy.
- **JWT Expired Tracking:** Proactively checks token expiration times (`exp` claim) before requests are made. If expiring, it performs a silent, background re-login using the stored credentials.
- **Offline Resiliency:** A failure to reach the server due to network issues does not delete user login states, ensuring seamless usage when resuming connection.

### 🚗 CarPlay Ready
- **Background Playback:** Audio sessions are fully configured with background audio capabilities (`AVPlayer` + `MPRemoteCommandCenter`).
- **In-Car UI:** Full integration with the Apple CarPlay template framework (`CPTemplateApplicationSceneDelegate`), allowing users to browse audiobook libraries, shelves, and control playback directly from their car head units.

### 📖 Native Document Viewers
- **EPUB Reader:** A native, lightweight e-book viewer presenting structured chapters with custom theme configurations (Dark/Light).
- **Comic Reader (CBZ/ZIP):** Fast archive extraction using `ZIPFoundation` to extract and display swipeable comic pages natively (`TabView` page style).
- **PDF Reader:** Fully integrated `PDFView` utilizing resolved standardized paths to avoid sandbox symbol link issues on physical iOS devices.

---

## Project Structure

- **`BookOrbitApp.swift`**: SwiftUI app main entry point.
- **`ContentView.swift`**: Principal dashboard interface, drawer components for book details, and the custom iOS Settings sheet.
- **`APIClient.swift`**: Network actor executing async/await queries, mapping response records, and wrapping the Keychain credentials assistant.
- **`AudioPlayerManager.swift`**: Central background audio player managing remote control actions and playing state.
- **`CarPlaySceneDelegate.swift`**: UIKit CarPlay delegate formatting layouts and controlling templates.
- **`ComicReaderView.swift` / `EPUBReaderView.swift`**: Viewers managing local caches, extracting archives, and presenting book pages.

---

## Xcode Setup & Integration

### 1. Requirements & Dependencies
Open the Xcode workspace (`BookOrbit.xcodeproj`) and ensure the following Swift Package Manager dependencies are linked:
- **ZIPFoundation:** `https://github.com/weichsel/ZIPFoundation` (minimum version `0.9.0`)
- **EpubReaderLight (epub-reader-light):** `https://github.com/pichukov/epub-reader-light`

### 2. Capabilities Configuration
1. Open the project settings in Xcode under target **BookOrbit > Signing & Capabilities**.
2. Click **+ Capability** and add **Background Modes**.
3. Select **Audio, AirPlay, and Picture in Picture**.
4. To enable keychain access groups, you can add the Keychain Sharing capability, though standard sandboxed keychain storage works by default.

### 3. Application Scene Manifest (`Info.plist`)
Under the `Info.plist` configuration, check the **Application Scene Manifest**:
1. Ensure **Enable Multiple Windows** is set to `YES`.
2. Under **Scene Configuration**, add **External Session Application Scene Session Role**.
3. Include an entry named `CarPlay` pointing to the delegate class: `$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate`.

---

## Testing & Verification

### Running locally
Select the `BookOrbit` scheme, target an iOS Simulator or connected physical iOS device, and click **Run** (or `Cmd + R`). Use the server URL `"mock"` to browse predefined, offline libraries and test the interface immediately without configuring a live server.
