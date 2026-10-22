import Foundation
import AVFoundation
import Combine
#if canImport(AVKit)
import AVKit
#endif

// MARK: - Audio & Subtitle Track Models
public struct AudioTrackOption: Identifiable, Equatable {
    public let id: String
    public let displayName: String
    public let languageCode: String?
    public let group: AVMediaSelectionGroup?
    public let option: AVMediaSelectionOption?
    
    public init(id: String, displayName: String, languageCode: String?, group: AVMediaSelectionGroup? = nil, option: AVMediaSelectionOption? = nil) {
        self.id = id
        self.displayName = displayName
        self.languageCode = languageCode
        self.group = group
        self.option = option
    }
}

public struct SubtitleOption: Identifiable, Equatable {
    public let id: String
    public let displayName: String
    public let languageCode: String?
    public let isExternal: Bool
    public let externalUrl: URL?
    public let group: AVMediaSelectionGroup?
    public let option: AVMediaSelectionOption?
    
    public init(id: String, displayName: String, languageCode: String?, isExternal: Bool = false, externalUrl: URL? = nil, group: AVMediaSelectionGroup? = nil, option: AVMediaSelectionOption? = nil) {
        self.id = id
        self.displayName = displayName
        self.languageCode = languageCode
        self.isExternal = isExternal
        self.externalUrl = externalUrl
        self.group = group
        self.option = option
    }
}

// MARK: - Player Service
@MainActor
public class PlayerService: NSObject, ObservableObject {
    public static let shared = PlayerService()
    
    // Core AVPlayer
    public var player: AVPlayer?
    public var playerLayer: AVPlayerLayer?
    #if os(iOS)
    public var pipController: AVPictureInPictureController?
    #endif
    
    // Playback State
    @Published public var isPlaying: Bool = false
    @Published public var isBuffering: Bool = false
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 0
    /// Live streams (IPTV) report an indefinite duration. The UI hides the scrubber and
    /// seek buttons for them — a 0-length scrubber sat pinned at the end and read as
    /// "permanently fast-forwarded".
    @Published public var isLive: Bool = false
    @Published public var bufferedTime: TimeInterval = 0
    @Published public var playbackRate: Float = 1.0
    @Published public var isPictureInPictureActive: Bool = false
    @Published public var isPictureInPicturePossible: Bool = false
    @Published public var videoGravity: AVLayerVideoGravity = .resizeAspect
    
    // Metadata & Item info
    @Published public var currentItemTitle: String = ""
    @Published public var currentItemSubtitle: String = ""
    @Published public var currentItemMediaId: String = ""
    @Published public var currentItemSeason: Int? = nil
    @Published public var currentItemEpisode: Int? = nil
    @Published public var currentPosterUrl: String? = nil
    /// Saved with the history row so "Weiterschauen" can look the title up again.
    public private(set) var currentMediaItem: MediaItem?
    @Published public var errorMessage: String? = nil
    
    // Tracks & Subtitles
    @Published public var availableAudioTracks: [AudioTrackOption] = []
    @Published public var selectedAudioTrack: AudioTrackOption? = nil
    @Published public var availableSubtitles: [SubtitleOption] = []
    @Published public var selectedSubtitle: SubtitleOption? = nil
    @Published public var currentSubtitleCueText: String? = nil
    @Published public var subtitleOffset: TimeInterval = 0.0
    @Published public var sleepTimerMinutesRemaining: Int? = nil
    
    public private(set) var currentStreamUrl: URL?
    /// The stream plays through the VPN's loopback proxy. Handing that URL to an external
    /// player would either fail or bypass the tunnel, so the menu is hidden.
    @Published public private(set) var isRoutedThroughVPN: Bool = false
    public private(set) var currentCustomHeaders: [String: String]?
    private var sleepTimerTask: Task<Void, Never>?
    
    /// Called when the current item fails. AppState uses this to fall through to the
    /// next source instead of leaving the user on an error screen.
    public var onPlaybackFailed: ((Error?) -> Void)?
    /// Called when the item plays to its end — used for auto-play of the next episode.
    public var onPlaybackEnded: (() -> Void)?

    private var loadedExternalCues: [SubtitleCue] = []
    private var timeObserverToken: Any?
    private var itemStatusObserver: NSKeyValueObservation?
    private var itemBufferEmptyObserver: NSKeyValueObservation?
    private var itemLikelyToKeepUpObserver: NSKeyValueObservation?
    private var itemLoadedTimeRangesObserver: NSKeyValueObservation?
    private var resourceLoader: CustomResourceLoader?
    private var lastHistorySaveTime: TimeInterval = 0
    
    override public init() {
        super.init()
        // Audio session is initialized lazily when playback starts to avoid launch hangs
    }
    
    // MARK: - Audio Session Setup
    public func setupAudioSession() {
        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothHFP])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up AVAudioSession: \(error)")
        }
        #endif
    }
    
    // MARK: - Playback Invocation
    public func play(
        url: URL,
        title: String,
        subtitle: String? = nil,
        mediaItemId: String = "",
        posterUrl: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        customHeaders: [String: String]? = nil,
        subtitles: [Subtitle]? = nil,
        startPosition: TimeInterval? = nil,
        mediaItem: MediaItem? = nil,
        routedThroughVPN: Bool = false
    ) {
        stopAndCleanup()
        self.currentMediaItem = mediaItem
        setupAudioSession()
        
        self.currentItemTitle = title
        self.currentItemSubtitle = subtitle ?? ""
        self.currentItemMediaId = mediaItemId
        self.currentPosterUrl = posterUrl
        self.currentItemSeason = season
        self.currentItemEpisode = episode
        self.isBuffering = true
        self.isLive = false
        self.errorMessage = nil
        
        // Prepare Subtitles List
        var subs: [SubtitleOption] = [
            SubtitleOption(id: "off", displayName: L("Aus"), languageCode: nil)
        ]
        
        if let externalSubs = subtitles {
            for sub in externalSubs {
                if let subUrl = URL(string: sub.url) {
                    subs.append(
                        SubtitleOption(
                            id: sub.id,
                            displayName: sub.displayLanguage,
                            languageCode: sub.language,
                            isExternal: true,
                            externalUrl: subUrl
                        )
                    )
                }
            }
        }
        self.availableSubtitles = subs
        self.selectedSubtitle = subs.first // Default off
        self.subtitleOffset = 0.0
        
        // Setup Asset with Custom HTTP Headers
        var asset: AVURLAsset
        var effectiveHeaders = customHeaders ?? [:]
        if effectiveHeaders["User-Agent"] == nil {
            effectiveHeaders["User-Agent"] = MediaHubClient.defaultUserAgent
        }
        
        self.currentStreamUrl = url
        self.isRoutedThroughVPN = routedThroughVPN
        self.currentCustomHeaders = effectiveHeaders
        
        let assetOptions: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey": effectiveHeaders
        ]
        
        // Use custom resource loader for mhub streams or as header injector
        if let scheme = url.scheme, scheme.hasPrefix("mhub") {
            let customUrl = CustomResourceLoader.makeCustomURL(from: url)
            self.resourceLoader = CustomResourceLoader(headers: effectiveHeaders)
            asset = AVURLAsset(url: customUrl, options: assetOptions)
            asset.resourceLoader.setDelegate(self.resourceLoader, queue: DispatchQueue.global(qos: .userInitiated))
        } else {
            asset = AVURLAsset(url: url, options: assetOptions)
        }
        
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        player.allowsExternalPlayback = true
        #if os(iOS)
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        #endif
        
        self.player = player
        observePlayerItem(playerItem: playerItem, startPosition: startPosition)
        setupTimeObserver()
        
        player.play()
        self.isPlaying = true
        self.playbackRate = 1.0
        startStallWatchdog(for: playerItem)
    }

    // MARK: - Stall watchdog
    private var stallWatchdog: Task<Void, Never>?

    /// A dead stream often never reports `.failed` — the item just sits there with no
    /// picture at 00:00. Without this the user stares at a black screen and the next
    /// source is never tried.
    private func startStallWatchdog(for item: AVPlayerItem) {
        stallWatchdog?.cancel()
        stallWatchdog = Task { @MainActor [weak self, weak item] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled, let self, let item,
                  self.player?.currentItem === item, self.isPlaying else { return }
            let hasPicture = item.status == .readyToPlay && (self.player?.currentTime().seconds ?? 0) > 0.1
            guard !hasPicture else { return }
            self.isBuffering = false
            if let handler = self.onPlaybackFailed {
                handler(nil)
            } else {
                self.errorMessage = L("Der Stream startet nicht. Bitte wähle eine andere Quelle.")
            }
        }
    }
    
    // MARK: - Observe Item Status & Buffering
    private func observePlayerItem(playerItem: AVPlayerItem, startPosition: TimeInterval?) {
        itemStatusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            Task { @MainActor in
                if item.status == .readyToPlay {
                    self.isBuffering = false
                    self.duration = item.duration.isNumeric ? item.duration.seconds : 0
                    self.isLive = item.duration.isIndefinite
                    self.extractTracks(from: item)
                    
                    if let start = startPosition, start > 0, item.duration.seconds > start {
                        self.seek(to: start)
                    }
                } else if item.status == .failed {
                    self.isBuffering = false
                    // Hand the failure to whoever is coordinating playback first; only if
                    // nobody handles it does the error surface in the player UI.
                    if let handler = self.onPlaybackFailed {
                        handler(item.error)
                    } else {
                        self.errorMessage = item.error?.localizedDescription ?? L("Fehler beim Abspielen des Streams")
                    }
                }
            }
        }
        
        itemBufferEmptyObserver = playerItem.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.isBuffering = item.isPlaybackBufferEmpty
            }
        }
        
        itemLikelyToKeepUpObserver = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            Task { @MainActor in
                if item.isPlaybackLikelyToKeepUp {
                    self.isBuffering = false
                }
            }
        }
        
        itemLoadedTimeRangesObserver = playerItem.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            if let timeRange = item.loadedTimeRanges.first?.timeRangeValue {
                let buffered = timeRange.start.seconds + timeRange.duration.seconds
                Task { @MainActor in
                    self.bufferedTime = buffered
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
    }
    
    @objc private func playerItemDidReachEnd() {
        Task { @MainActor in
            self.isPlaying = false
            self.saveHistory()
            self.onPlaybackEnded?()
        }
    }
    
    // MARK: - Periodic Time Observer
    private func setupTimeObserver() {
        guard let player = player else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.handlePeriodicTime(time)
            }
        }
    }
    
    private func handlePeriodicTime(_ time: CMTime) {
        let seconds = time.seconds
        guard seconds.isFinite else { return }
        
        self.currentTime = seconds
        
        // Sync external subtitle cues with offset
        if let sub = self.selectedSubtitle, sub.isExternal {
            let adjustedTime = seconds + self.subtitleOffset
            if let cue = SubtitleParser.shared.activeCue(in: self.loadedExternalCues, at: adjustedTime) {
                self.currentSubtitleCueText = cue.text
            } else {
                self.currentSubtitleCueText = nil
            }
        } else {
            self.currentSubtitleCueText = nil
        }
        
        // Periodic Watch History Save every 5 seconds
        if abs(seconds - self.lastHistorySaveTime) > 5.0 {
            self.saveHistory()
            self.lastHistorySaveTime = seconds
        }
    }
    
    // MARK: - Sleep Timer
    public func setSleepTimer(minutes: Int?) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        guard let minutes, minutes > 0 else {
            sleepTimerMinutesRemaining = nil
            return
        }
        sleepTimerMinutesRemaining = minutes
        sleepTimerTask = Task { [weak self] in
            var remaining = minutes
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                if Task.isCancelled { return }
                remaining -= 1
                await MainActor.run {
                    self?.sleepTimerMinutesRemaining = remaining
                    if remaining == 0 {
                        self?.pause()
                        self?.sleepTimerMinutesRemaining = nil
                    }
                }
            }
        }
    }
    
    // MARK: - Extract Media Tracks (Audio & Subtitles from HLS Manifest)
    /// Loose language match: streams label tracks as "de", "de-DE", "deu" or "ger", so a
    /// plain equality check against the preferred code almost never fires.
    private static func matches(languageCode: String?, preferred: String) -> Bool {
        guard let languageCode, !preferred.isEmpty else { return false }
        let track = languageCode.lowercased()
        let want = preferred.lowercased()
        if track == want || track.hasPrefix(want + "-") || track.hasPrefix(want + "_") { return true }
        // Three-letter ISO 639-2 variants for the two languages the app ships with.
        let aliases: [String: Set<String>] = [
            "de": ["deu", "ger", "de"],
            "en": ["eng", "en"]
        ]
        return aliases[want]?.contains(String(track.prefix(3))) ?? false
    }

    private func extractTracks(from item: AVPlayerItem) {
        guard let asset = item.asset as? AVURLAsset else { return }
        
        Task {
            // 1. Audio Tracks
            var audioTracks: [AudioTrackOption] = []
            if let audioGroup = try? await asset.loadMediaSelectionGroup(for: .audible) {
                for option in audioGroup.options {
                    // AVFoundation hands out "Unknown" for untitled tracks; number them instead.
                    let rawName = option.displayName
                    let name = (rawName.isEmpty || rawName.lowercased() == "unknown")
                        ? "\(L("Tonspur")) \(audioTracks.count + 1)" : rawName
                    let lang = option.extendedLanguageTag ?? option.locale?.identifier
                    let track = AudioTrackOption(
                        id: option.displayName + (lang ?? ""),
                        displayName: name,
                        languageCode: lang,
                        group: audioGroup,
                        option: option
                    )
                    audioTracks.append(track)
                }
                
                let currentAudio = item.currentMediaSelection.selectedMediaOption(in: audioGroup)
                let preferred = await MainActor.run { StorageService.shared.settings.preferredAudioLanguage }
                // Honour the preferred audio language when the stream offers it; otherwise
                // keep whatever the stream selected itself.
                let preferredTrack = audioTracks.first { Self.matches(languageCode: $0.languageCode, preferred: preferred) }
                let selected = preferredTrack
                    ?? audioTracks.first(where: { $0.option == currentAudio })
                    ?? audioTracks.first

                await MainActor.run {
                    self.availableAudioTracks = audioTracks
                    self.selectedAudioTrack = selected
                    if let preferredTrack, preferredTrack.option != currentAudio {
                        self.selectAudioTrack(preferredTrack)
                    }
                }
            }
            
            // 2. Embedded In-Manifest Subtitles
            if let subtitleGroup = try? await asset.loadMediaSelectionGroup(for: .legible) {
                var embeddedSubs: [SubtitleOption] = []
                for option in subtitleGroup.options {
                    let name = option.displayName
                    let lang = option.extendedLanguageTag ?? option.locale?.identifier
                    let sub = SubtitleOption(
                        id: option.displayName + (lang ?? ""),
                        displayName: name,
                        languageCode: lang,
                        isExternal: false,
                        group: subtitleGroup,
                        option: option
                    )
                    embeddedSubs.append(sub)
                }
                
                await MainActor.run {
                    // Combine with any external subtitles
                    var allSubs = self.availableSubtitles
                    for sub in embeddedSubs where !allSubs.contains(where: { $0.id == sub.id }) {
                        allSubs.append(sub)
                    }
                    self.availableSubtitles = allSubs

                    // Auto-enable subtitles in the preferred language, but only if the user
                    // has not already picked one for this playback.
                    let preferred = StorageService.shared.settings.preferredSubtitleLanguage
                    if self.selectedSubtitle == nil || self.selectedSubtitle?.id == "off",
                       let match = allSubs.first(where: {
                           $0.id != "off" && Self.matches(languageCode: $0.languageCode, preferred: preferred)
                       }) {
                        self.selectSubtitle(match)
                    }
                }
            }
        }
    }
    
    // MARK: - Playback Controls
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }
    
    public func pause() {
        player?.pause()
        self.isPlaying = false
        saveHistory()
    }
    
    public func resume() {
        player?.rate = playbackRate
        player?.play()
        self.isPlaying = true
    }
    
    public func seek(to seconds: TimeInterval) {
        guard !isLive else { return }
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        let targetTime = CMTime(seconds: clamped, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            if finished {
                Task { @MainActor in
                    self?.currentTime = clamped
                }
            }
        }
    }
    
    public func skipForward(seconds: Double = 10) {
        seek(to: currentTime + seconds)
    }
    
    public func skipBackward(seconds: Double = 10) {
        seek(to: currentTime - seconds)
    }
    
    public func setPlaybackRate(_ rate: Float) {
        self.playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
    }
    
    public func toggleVideoGravity() {
        if videoGravity == .resizeAspect {
            videoGravity = .resizeAspectFill
        } else {
            videoGravity = .resizeAspect
        }
    }
    
    // MARK: - Track Switching
    public func selectAudioTrack(_ track: AudioTrackOption) {
        guard let group = track.group, let option = track.option, let item = player?.currentItem else { return }
        item.select(option, in: group)
        self.selectedAudioTrack = track
    }
    
    public func selectSubtitle(_ subtitle: SubtitleOption?) {
        guard let subtitle = subtitle else {
            // Turn off
            self.selectedSubtitle = availableSubtitles.first(where: { $0.id == "off" })
            self.currentSubtitleCueText = nil
            self.loadedExternalCues = []
            return
        }
        
        self.selectedSubtitle = subtitle
        
        if subtitle.id == "off" {
            self.currentSubtitleCueText = nil
            self.loadedExternalCues = []
            if let group = subtitle.group, let item = player?.currentItem {
                item.select(nil, in: group)
            }
        } else if subtitle.isExternal, let extUrl = subtitle.externalUrl {
            // Load external VTT/SRT file
            Task {
                do {
                    let cues = try await SubtitleParser.shared.load(from: extUrl)
                    await MainActor.run {
                        self.loadedExternalCues = cues
                    }
                } catch {
                    print("Failed to load external subtitles: \(error)")
                }
            }
        } else if let group = subtitle.group, let option = subtitle.option, let item = player?.currentItem {
            // In-manifest subtitle
            item.select(option, in: group)
            self.loadedExternalCues = []
        }
    }
    
    // MARK: - Picture-in-Picture
    public func setupPictureInPicture(with layer: AVPlayerLayer) {
        self.playerLayer = layer
        #if os(iOS)
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let pip = AVPictureInPictureController(playerLayer: layer)
            pip?.delegate = self
            self.pipController = pip
            self.isPictureInPicturePossible = true
        }
        #endif
    }
    
    public func togglePictureInPicture() {
        #if os(iOS)
        guard let pip = pipController else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
        #endif
    }
    
    // MARK: - Persistence & Watch History
    private func saveHistory() {
        // A live position is not somewhere to resume, so it stays out of "Weiterschauen".
        // Live channels are recognised by type as well: a live stream is not always
        // reported with an indefinite duration, and then kept landing in the row.
        guard !isLive, currentMediaItem?.isIPTV != true,
              !currentItemMediaId.isEmpty && currentTime > 5 else { return }
        StorageService.shared.updateHistory(
            mediaItemId: currentItemMediaId,
            title: currentItemTitle,
            posterUrl: currentPosterUrl,
            itemType: currentItemSeason != nil ? "series" : "movie",
            season: currentItemSeason,
            episode: currentItemEpisode,
            position: currentTime,
            duration: duration,
            mediaItem: currentMediaItem
        )
    }
    
    // MARK: - Stop & Cleanup
    public func stopAndCleanup() {
        stallWatchdog?.cancel()
        onPlaybackFailed = nil
        onPlaybackEnded = nil
        saveHistory()
        
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        itemBufferEmptyObserver?.invalidate()
        itemBufferEmptyObserver = nil
        itemLikelyToKeepUpObserver?.invalidate()
        itemLikelyToKeepUpObserver = nil
        itemLoadedTimeRangesObserver?.invalidate()
        itemLoadedTimeRangesObserver = nil
        
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        
        player?.pause()
        player = nil
        
        self.isPlaying = false
        self.isBuffering = false
        self.currentTime = 0
        self.duration = 0
        self.isLive = false
        self.bufferedTime = 0
        self.currentSubtitleCueText = nil
        self.loadedExternalCues = []
        self.resourceLoader = nil
    }
}

// MARK: - AVPictureInPictureControllerDelegate
#if os(iOS)
extension PlayerService: @preconcurrency AVPictureInPictureControllerDelegate {
    @MainActor
    public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        self.isPictureInPictureActive = true
    }
    
    @MainActor
    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        self.isPictureInPictureActive = false
    }
    
    @MainActor
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        self.isPictureInPictureActive = false
        print("PiP failed: \(error)")
    }
}
#endif
