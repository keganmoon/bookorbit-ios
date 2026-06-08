<div align="center">

# BookOrbit iOS & CarPlay Client

An elegant, native iOS application and Apple CarPlay integration for **BookOrbit**—the self-hosted digital library for ebooks, audiobooks, and comics.

[![Platform](https://img.shields.io/badge/Platform-iOS_15.0+-000000?style=flat-square&logo=apple&logoColor=white&color=black)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.5+-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg?style=flat-square&color=B461B3)](LICENSE)
[![BookOrbit](https://img.shields.io/badge/Server-BookOrbit-blue?style=flat-square&color=4169E1)](https://github.com/bookorbit/bookorbit)

</div>

---

## What is BookOrbit iOS?

**BookOrbit iOS** is the companion mobile and in-car client for your self-hosted **[BookOrbit](https://bookorbit.app)** server. It provides a premium, unified experience for browsing, reading, and listening to your self-hosted digital collection on your iPhone, iPad, and CarPlay dashboard.

With library-specific settings toggles, you can customize your dashboard layout—streamlining the application as a dedicated audiobook player or enabling ebook and comic libraries on the fly.

---

## Key Features

### 🎧 Audiobook Player & CarPlay Integration
*   **CarPlay Dashboard:** Browse your audio libraries, shelves, and control playback directly from your car head unit using Apple's CarPlay template framework.
*   **Background Playback:** Smooth audio session management (`AVPlayer` + `MPRemoteCommandCenter`) with lock-screen widget control, skip back/forward, and scrub bars.
*   **Progress Syncing:** Real-time playhead progress, completion percentages, and reading session stats automatically synced with your server.

### 📖 Dynamic Document Readers
*   **E-Book Reader (EPUB):** High-performance web-based reader featuring customizable typography, line height, text alignment, light/dark themes, bookmarks, and highlight annotations.
*   **Comic Viewer (CBZ/CBR):** Full support for digital comics, rendering swipeable, high-resolution comic pages.
*   **PDF Viewer:** Standardized `PDFView` navigation offering smooth zoom and page transition behaviors.

### 🔑 Secure Login & Silent Renewal
*   **Keychain Protection:** Sensitive server URLs, usernames, and JWT tokens are securely stored using Apple's Keychain services under the `kSecAttrAccessibleAfterFirstUnlock` policy.
*   **Automatic Token Refresh:** Proactively intercepts request authentication and performs silent background logins if JWT tokens are near expiration.
*   **Offline Resiliency:** App retains authenticated sessions when offline, automatically reconnecting when a network connection is re-established.

### ⚙️ Customizable Settings
*   **Per-Library Toggles:** Settings sheet automatically detects all server-side libraries (Audiobooks, eBooks, Comics) and provides granular toggles to enable or disable them.
*   **Context-Aware Prompts:** Search bars and dashboard scroller shelves automatically adapt (e.g. dynamic search prompts like `"Search audiobooks, ebooks & comics..."` or `"Search audiobooks..."`) depending on which libraries you have active.

---

## Architecture Overview

*   **`ContentView.swift`**: Principal SwiftUI app layout, displaying dashboard shelves (Continue Listening, Continue Reading, Recently Added) and native settings sheets.
*   **`WebReaderView.swift`**: Houses `WebReaderSheetView` (asynchronously inserts JWT cookies to WebKit store to eliminate login prompt race conditions) and `WebReaderView` (WKWebView wrapper for e-book and comic routing).
*   **`AudioPlayerManager.swift`**: Core audio manager handling local/remote playback states, CarPlay integration, lock-screen interactions, and playhead progress.
*   **`APIClient.swift`**: Networking coordinator wrapping async/await fetch queries and secure Keychain storage logic.
*   **`CarPlaySceneDelegate.swift`**: CarPlay template delegate configuring lists and controlling audiobook playback templates.

---

## Xcode Setup & Requirements

### 1. Prerequisites
Open the workspace (`BookOrbit.xcodeproj`) in Xcode. Ensure the following Swift Package Manager (SPM) packages are fetched:
*   **ZIPFoundation:** `https://github.com/weichsel/ZIPFoundation` (minimum version `0.9.0`)
*   **EpubReaderLight (epub-reader-light):** `https://github.com/pichukov/epub-reader-light`

### 2. Capabilities Configuration
1. Open the project settings in Xcode under target **BookOrbit > Signing & Capabilities**.
2. Click **+ Capability** and add **Background Modes**.
3. Check the **Audio, AirPlay, and Picture in Picture** option.
4. (Optional) Add **Keychain Sharing** if sharing credentials with other app groups, although standard sandbox Keychain functions are enabled by default.

### 3. CarPlay Scene Configuration (`Info.plist`)
Under **Application Scene Manifest** in your `Info.plist` target settings:
1. Ensure **Enable Multiple Windows** is set to `YES`.
2. Under **Scene Configuration**, add **External Session Application Scene Session Role**.
3. Declare `CarPlay` pointing to the delegate class: `$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate`.

---

## Getting Started

1. Clone this repository to your local mac:
   ```bash
   git clone git@github.com:keganmoon/bookorbit-ios.git
   cd bookorbit-ios
   ```
2. Open `BookOrbit.xcodeproj` in Xcode.
3. Configure your code signing team under **Signing & Capabilities**.
4. Run (`Cmd + R`) on an iOS Simulator or physical iPhone.
5. Enter your server URL and login credentials to connect.
   *   *Note:* You can type `"mock"` in the server URL field to load the offline demo dashboard with sample data immediately.
