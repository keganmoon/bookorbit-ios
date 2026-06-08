import AVFoundation
import MediaPlayer
import Combine
import UIKit

class AudioPlayerManager: NSObject, ObservableObject {
    static let shared = AudioPlayerManager()
    
    private var player: AVPlayer?
    @Published var isPlaying = false
    @Published var currentTitle: String?
    @Published var currentAuthor: String?
    
    // Progress tracking properties
    @Published var currentBookId: Int?
    @Published var currentFileId: Int?
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    private var timeObserverToken: Any?
    
    private var playbackSetupTask: Task<Void, Never>?
    
    override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommandCenter()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("Failed to configure background AVAudioSession: \(error)")
        }
    }
    
    func playAudio(url: URL, bookId: Int, fileId: Int, title: String, author: String) {
        // Cancel any pending playback setup tasks first
        playbackSetupTask?.cancel()
        
        // Stop existing playback and save progress
        stopPlaybackAndSave()
        
        self.currentBookId = bookId
        self.currentFileId = fileId
        self.currentTime = 0.0
        self.duration = 0.0
        
        playbackSetupTask = Task {
            // Fetch starting progress from server
            let progress = await APIClient.shared.getAudioProgress(bookId: bookId)
            
            // Check if task was cancelled while we were fetching progress
            if Task.isCancelled { return }
            
            let startPosition = (progress?.currentFileId == fileId) ? (progress?.positionSeconds ?? 0.0) : 0.0
            
            // Retrieve authorization headers from APIClient
            let headers = await APIClient.shared.getAuthHeaders()
            if Task.isCancelled { return }
            
            // Construct asset with authentication headers for streaming from self-hosted BookOrbit server
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let playerItem = AVPlayerItem(asset: asset)
            
            await MainActor.run {
                if Task.isCancelled { return }
                
                let avPlayer = AVPlayer(playerItem: playerItem)
                self.player = avPlayer
                
                // Seek to starting position if greater than 0
                if startPosition > 0 {
                    let time = CMTime(seconds: startPosition, preferredTimescale: 1000)
                    avPlayer.seek(to: time)
                }
                
                avPlayer.play()
                
                self.isPlaying = true
                self.currentTitle = title
                self.currentAuthor = author
                self.currentTime = startPosition
                
                self.updateNowPlayingState()
                
                if let bId = self.currentBookId {
                    self.fetchAndSetArtwork(for: bId)
                }
                
                // Add periodic time observer to save progress every 5 seconds
                self.setupTimeObserver(for: avPlayer, fileId: fileId, bookId: bookId)
            }
        }
    }
    
    func togglePlayback() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            self.isPlaying = false
            saveCurrentProgress()
        } else {
            player.play()
            self.isPlaying = true
        }
        self.updateNowPlayingState()
    }
    
    func stopPlaybackAndSave() {
        playbackSetupTask?.cancel()
        playbackSetupTask = nil
        
        guard let avPlayer = player, let currentItem = avPlayer.currentItem else {
            self.isPlaying = false
            self.currentBookId = nil
            self.currentFileId = nil
            self.currentTime = 0.0
            self.duration = 0.0
            return
        }
        
        avPlayer.pause()
        let currentTime = avPlayer.currentTime().seconds
        let duration = currentItem.duration.seconds
        
        if let bookId = currentBookId, let fileId = currentFileId, duration > 0, !currentTime.isNaN, !duration.isNaN {
            let percentage = max(0.0, min(100.0, (currentTime / duration) * 100.0))
            let bId = bookId
            let fId = fileId
            
            Task {
                await APIClient.shared.saveAudioProgress(
                    bookId: bId,
                    fileId: fId,
                    positionSeconds: currentTime,
                    percentage: percentage
                )
            }
        }
        
        removeTimeObserver()
        player = nil
        self.currentBookId = nil
        self.currentFileId = nil
        self.isPlaying = false
        self.currentTime = 0.0
        self.duration = 0.0
        
        // Reset Now Playing Info Center
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
    }
    
    func seek(to seconds: Double) {
        guard let player = player else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 1000)
        player.seek(to: time) { [weak self] finished in
            if finished {
                DispatchQueue.main.async {
                    self?.currentTime = seconds
                    self?.updateNowPlayingState()
                }
            }
        }
    }
    
    func skipBackward(seconds: Double = 15.0) {
        guard let player = player else { return }
        let currentTime = player.currentTime().seconds
        seek(to: max(0.0, currentTime - seconds))
    }
    
    func skipForward(seconds: Double = 15.0) {
        guard let player = player, let currentItem = player.currentItem else { return }
        let currentTime = player.currentTime().seconds
        let duration = currentItem.duration.seconds
        guard !duration.isNaN else { return }
        seek(to: min(duration, currentTime + seconds))
    }
    
    private func saveCurrentProgress() {
        guard let player = player, let bookId = currentBookId, let fileId = currentFileId, let currentItem = player.currentItem else { return }
        let currentTime = player.currentTime().seconds
        let duration = currentItem.duration.seconds
        if duration > 0, !currentTime.isNaN, !duration.isNaN {
            let percentage = max(0.0, min(100.0, (currentTime / duration) * 100.0))
            let bId = bookId
            let fId = fileId
            Task {
                await APIClient.shared.saveAudioProgress(bookId: bId, fileId: fId, positionSeconds: currentTime, percentage: percentage)
            }
        }
    }
    
    private func setupTimeObserver(for avPlayer: AVPlayer, fileId: Int, bookId: Int) {
        removeTimeObserver()
        
        var lastSaveTime: Double = 0.0
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, let currentItem = avPlayer.currentItem else { return }
            
            let currentTime = time.seconds
            let duration = currentItem.duration.seconds
            
            guard !currentTime.isNaN, !duration.isNaN, duration > 0 else { return }
            
            let oldDuration = self.duration
            self.currentTime = currentTime
            self.duration = duration
            
            // If duration was resolved (changed from 0 to actual value), update Now Playing Info
            if oldDuration == 0.0 && duration > 0 {
                self.updateNowPlayingState()
            }
            
            // Sync to server every 5 seconds
            if abs(currentTime - lastSaveTime) >= 5.0 {
                lastSaveTime = currentTime
                let percentage = max(0.0, min(100.0, (currentTime / duration) * 100.0))
                Task {
                    await APIClient.shared.saveAudioProgress(
                        bookId: bookId,
                        fileId: fileId,
                        positionSeconds: currentTime,
                        percentage: percentage
                    )
                }
            }
        }
    }
    
    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Disable next/prev track to prioritize skip forward/backward buttons on CarPlay/Lock screen
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        
        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            self.player?.play()
            DispatchQueue.main.async {
                self.isPlaying = true
                self.updateNowPlayingState()
            }
            return .success
        }
        
        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            self.player?.pause()
            DispatchQueue.main.async {
                self.isPlaying = false
                self.updateNowPlayingState()
            }
            self.saveCurrentProgress()
            return .success
        }
        
        // Skip backward command (15 seconds)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            self.skipBackward(seconds: 15.0)
            return .success
        }
        
        // Skip forward command (15 seconds)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            self.skipForward(seconds: 15.0)
            return .success
        }
        
        // Change playback position (scrubbing)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: positionEvent.positionTime)
            return .success
        }
    }
    
    private func updateNowPlayingState() {
        guard let player = player, let currentItem = player.currentItem else { return }
        let title = currentTitle ?? "Streaming Audiobook"
        let author = currentAuthor ?? "Unknown Author"
        let elapsed = player.currentTime().seconds
        let duration = currentItem.duration.seconds
        let rate = player.rate
        
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyArtist] = author
        
        if !elapsed.isNaN {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }
        if !duration.isNaN && duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        
        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = rate > 0 ? .playing : .paused
        }
    }
    
    private func fetchAndSetArtwork(for bookId: Int) {
        Task {
            do {
                let serverURL = await APIClient.shared.getServerURL()
                guard !serverURL.isEmpty else { return }
                
                let coverUrlString: String
                if serverURL == "mock" {
                    return // No cover art fetched in mock mode
                } else {
                    coverUrlString = "\(serverURL)/api/v1/books/\(bookId)/cover"
                }
                
                guard let url = URL(string: coverUrlString) else { return }
                
                // Fetch the image data using authorization headers
                let headers = await APIClient.shared.getAuthHeaders()
                var request = URLRequest(url: url)
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
                
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    return
                }
                
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
                            return image
                        }
                        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
                        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                        print("🎨 CarPlay: Cover art updated successfully for bookId: \(bookId)")
                    }
                }
            } catch {
                print("🎨 CarPlay Error: Failed to fetch cover art: \(error)")
            }
        }
    }
}
