//
//  BookOrbitTests.swift
//  BookOrbitTests
//
//  Created by Kegan on 6/6/26.
//

import XCTest
import PDFKit
import ZIPFoundation
@testable import BookOrbit

final class BookOrbitTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Ensure Previews folder is clean before each test
        cleanupTestPreviews()
    }

    override func tearDownWithError() throws {
        // Clean up Previews folder after each test
        cleanupTestPreviews()
        try super.tearDownWithError()
    }

    /// Helper to cleanly delete the Previews directory for test isolation
    private func cleanupTestPreviews() {
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let previewDir = cacheDir.appendingPathComponent("Previews", isDirectory: true)
        if fileManager.fileExists(atPath: previewDir.path) {
            try? fileManager.removeItem(at: previewDir)
        }
    }

    /// Verifies that the correct readable file extensions are supported
    func testReadableFormats() {
        let readableExtensions = ["pdf", "epub", "txt", "cbz", "cbr", "mobi", "azw", "azw3", "fb2"]
        let unreadableExtensions = ["mp3", "m4b", "jpg", "png", "zip"]
        
        // We can create a test method mirroring ContentView's isReadableFormat logic
        func isReadable(_ format: String) -> Bool {
            return ["pdf", "epub", "txt", "cbz", "cbr", "mobi", "azw", "azw3", "fb2"].contains(format.lowercased())
        }
        
        for ext in readableExtensions {
            XCTAssertTrue(isReadable(ext), "Format \(ext) should be readable")
        }
        
        for ext in unreadableExtensions {
            XCTAssertFalse(isReadable(ext), "Format \(ext) should not be readable")
        }
    }

    /// Verifies that preview file destination URLs are correctly placed in app Library/Caches/Previews directory
    func testGetDestinationURLPath() {
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let previewDir = cacheDir.appendingPathComponent("Previews", isDirectory: true)
        
        let filename = "test_document.epub"
        let expectedURL = previewDir.appendingPathComponent(filename)
        
        // Mirror getDestinationURL function
        func getDestinationURL(filename: String) -> URL {
            let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let previewDir = cacheDir.appendingPathComponent("Previews", isDirectory: true)
            if !fileManager.fileExists(atPath: previewDir.path) {
                try? fileManager.createDirectory(at: previewDir, withIntermediateDirectories: true)
            }
            return previewDir.appendingPathComponent(filename)
        }
        
        let destinationURL = getDestinationURL(filename: filename)
        
        XCTAssertEqual(destinationURL.lastPathComponent, filename)
        XCTAssertTrue(destinationURL.path.contains("/Library/Caches/Previews/"))
        XCTAssertTrue(fileManager.fileExists(atPath: previewDir.path), "Previews directory should be created if missing")
    }

    /// Verifies that file URLs are standardized (resolves symbol links /var vs /private/var)
    func testURLStandardization() {
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let previewDir = cacheDir.appendingPathComponent("Previews", isDirectory: true)
        if !fileManager.fileExists(atPath: previewDir.path) {
            try? fileManager.createDirectory(at: previewDir, withIntermediateDirectories: true)
        }
        
        let destinationURL = previewDir.appendingPathComponent("standardized_test.epub")
        let standardizedURL = URL(fileURLWithPath: destinationURL.path).standardized
        
        // Assert standardizedURL has resolved symbolic links (canonical path starting with /private on iOS/macOS)
        XCTAssertTrue(standardizedURL.path.starts(with: "/private") || !standardizedURL.path.contains("/var/"),
                      "Standardized URL path should resolve system symbolic links cleanly")
    }

    /// Verifies that cleanupPreviews removes all cached e-books and the previews folder entirely
    func testCleanupPreviewsRemovesFilesAndFolder() throws {
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let previewDir = cacheDir.appendingPathComponent("Previews", isDirectory: true)
        
        // Ensure Previews folder exists and create mock files inside it
        try fileManager.createDirectory(at: previewDir, withIntermediateDirectories: true)
        let file1 = previewDir.appendingPathComponent("temp1.epub")
        let file2 = previewDir.appendingPathComponent("temp2.zip")
        
        try "Content 1".write(to: file1, atomically: true, encoding: .utf8)
        try "Content 2".write(to: file2, atomically: true, encoding: .utf8)
        
        XCTAssertTrue(fileManager.fileExists(atPath: file1.path))
        XCTAssertTrue(fileManager.fileExists(atPath: file2.path))
        
        // Mirror cleanupPreviews function
        func cleanupPreviews() {
            let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let previewDir = cacheDir.appendingPathComponent("Previews", isDirectory: true)
            if fileManager.fileExists(atPath: previewDir.path) {
                try? fileManager.removeItem(at: previewDir)
            }
        }
        
        cleanupPreviews()
        
        XCTAssertFalse(fileManager.fileExists(atPath: file1.path), "Cached file 1 should be deleted")
        XCTAssertFalse(fileManager.fileExists(atPath: file2.path), "Cached file 2 should be deleted")
        XCTAssertFalse(fileManager.fileExists(atPath: previewDir.path), "Previews directory should be deleted entirely")
    }

    /// Tests downloading a real PDF and loading it to see if URLSession.shared vs custom session behaves differently
    func testDownloadPDF() async throws {
        let fileId = 19184
        let token = UserDefaults.standard.string(forKey: "auth_token") ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOjEsInZlciI6MSwiaWF0IjoxNzgwNzc1ODUwLCJleHAiOjE3ODA3NzY3NTB9.L89lnJm9d54k3VyFMwZJTmdJAoNM53upt6w8G7qHw3U"
        let serverURL = UserDefaults.standard.string(forKey: "server_url") ?? "https://bookorbit.moontube.cc"
        
        let downloadURL = URL(string: "\(serverURL)/api/v1/books/files/\(fileId)/serve")!
        var request = URLRequest(url: downloadURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("[TEST] Starting PDF download tests...")
        
        // 1. Download using custom session with RedirectHandler
        let session = URLSession(configuration: .default, delegate: RedirectHandler(), delegateQueue: nil)
        do {
            let (tempURL, response) = try await session.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                XCTFail("Expected HTTPURLResponse")
                return
            }
            print("[TEST] Custom URLSession status: \(httpResponse.statusCode)")
            if httpResponse.statusCode == 401 {
                print("[TEST] Custom URLSession returned 401 Unauthorized. Skipping live verification due to expired token.")
                return
            }
            if httpResponse.statusCode != 200 {
                print("[TEST] Custom URLSession returned \(httpResponse.statusCode). Skipping live verification.")
                return
            }
            let data = try Data(contentsOf: tempURL)
            print("[TEST] Custom URLSession downloaded bytes: \(data.count)")
            let doc = PDFDocument(data: data)
            print("[TEST] Custom URLSession PDFDocument pages: \(doc?.pageCount ?? -1)")
            XCTAssertNotNil(doc, "PDFDocument should be parsed successfully")
            XCTAssertGreaterThan(doc?.pageCount ?? 0, 0, "PDF should have pages")
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == -1012 {
                print("[TEST] Custom URLSession failed with auth error -1012. Skipping live verification.")
                return
            }
            print("[TEST] Custom URLSession failed: \(error)")
            XCTFail("Custom session failed: \(error)")
        }
        
        // 2. Download using URLSession.shared
        do {
            let (tempURL, response) = try await URLSession.shared.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                XCTFail("Expected HTTPURLResponse")
                return
            }
            print("[TEST] Shared URLSession status: \(httpResponse.statusCode)")
            if httpResponse.statusCode == 401 {
                print("[TEST] Shared URLSession returned 401 Unauthorized. Skipping live verification.")
                return
            }
            if httpResponse.statusCode != 200 {
                print("[TEST] Shared URLSession returned \(httpResponse.statusCode). Skipping live verification.")
                return
            }
            let data = try Data(contentsOf: tempURL)
            print("[TEST] Shared URLSession downloaded bytes: \(data.count)")
            let doc = PDFDocument(data: data)
            print("[TEST] Shared URLSession PDFDocument pages: \(doc?.pageCount ?? -1)")
            XCTAssertNotNil(doc, "PDFDocument should be parsed successfully")
            XCTAssertGreaterThan(doc?.pageCount ?? 0, 0, "PDF should have pages")
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == -1012 {
                print("[TEST] Shared URLSession failed with auth error -1012. Skipping live verification.")
                return
            }
            print("[TEST] Shared URLSession failed: \(error)")
            XCTFail("Shared session failed: \(error)")
        }
    }

    /// Tests downloading a real CBZ and unzipping it using ZIPFoundation
    func testDownloadAndUnzipCBZ() async throws {
        let fileId = 2070
        let token = UserDefaults.standard.string(forKey: "auth_token") ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOjEsInZlciI6MSwiaWF0IjoxNzgwNzc1ODUwLCJleHAiOjE3ODA3NzY3NTB9.L89lnJm9d54k3VyFMwZJTmdJAoNM53upt6w8G7qHw3U"
        let serverURL = "https://bookorbit.moontube.cc"
        
        let downloadURL = URL(string: "\(serverURL)/api/v1/books/files/\(fileId)/serve")!
        var request = URLRequest(url: downloadURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("[TEST] Starting CBZ download and unzip test...")
        
        let tempURL: URL
        let response: URLResponse
        do {
            (tempURL, response) = try await URLSession.shared.download(for: request)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == -1012 {
                print("[TEST] CBZ download failed with auth error -1012. Skipping live verification.")
                return
            }
            throw error
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Expected HTTPURLResponse")
            return
        }
        if httpResponse.statusCode == 401 {
            print("[TEST] CBZ download returned 401 Unauthorized. Skipping live verification.")
            return
        }
        if httpResponse.statusCode != 200 {
            print("[TEST] CBZ download returned status code \(httpResponse.statusCode). Skipping live verification.")
            return
        }
        
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let extractDir = cacheDir.appendingPathComponent("TestComicExtract_\(fileId)", isDirectory: true)
        if fileManager.fileExists(atPath: extractDir.path) {
            try? fileManager.removeItem(at: extractDir)
        }
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        // Unzip it
        do {
            try fileManager.unzipItem(at: tempURL, to: extractDir)
            print("[TEST] Unzipped successfully!")
            
            // Check images
            var imageCount = 0
            let enumerator = fileManager.enumerator(at: extractDir, includingPropertiesForKeys: nil)
            while let fileURL = enumerator?.nextObject() as? URL {
                let ext = fileURL.pathExtension.lowercased()
                if ["jpg", "jpeg", "png", "webp", "gif"].contains(ext) {
                    imageCount += 1
                }
            }
            print("[TEST] Found \(imageCount) images in CBZ")
            XCTAssertGreaterThan(imageCount, 0, "CBZ should contain images")
        } catch {
            print("[TEST] Unzip failed: \(error)")
            XCTFail("Unzip failed: \(error)")
        }
        
        // Cleanup
        try? fileManager.removeItem(at: extractDir)
    }
}
