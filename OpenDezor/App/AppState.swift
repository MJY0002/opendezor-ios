import SwiftUI
import Combine

public enum AppTab: String, CaseIterable, Identifiable {
    case dashboard = "Entdecken"
    case browser = "Browser"
    case liveTV = "Live TV"
    case library = "Bibliothek"
    case settings = "Einstellungen"
    
    public var id: String { rawValue }

    /// The raw value doubles as this tab's identity, so it stays German; the label the
    /// user sees goes through the translation table.
    public var title: String { L(rawValue) }

    public var iconName: String {
        switch self {
        case .dashboard: return "sparkles"
        case .browser: return "globe"
        case .liveTV: return "antenna.radiowaves.left.and.right"
        case .library: return "bookmark.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

public struct ActivePlaybackTarget: Identifiable, Equatable {
    public let id = UUID()
    public let item: MediaItem
    public let episode: SeriesEpisodeItem?
    public let source: MediaSource?
    public let directUrl: URL?
    public let headers: [String: String]?
    
    public init(item: MediaItem, episode: SeriesEpisodeItem? = nil, source: MediaSource? = nil, directUrl: URL? = nil, headers: [String: String]? = nil) {
        self.item = item
        self.episode = episode
        self.source = source
        self.directUrl = directUrl
        self.headers = headers
    }
    
    public static func == (lhs: ActivePlaybackTarget, rhs: ActivePlaybackTarget) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
public class AppState: ObservableObject {
    public static let shared = AppState()
    
    private let onboardingKey = "opendezor_has_completed_onboarding"
    
    @Published public var selectedTab: AppTab = .dashboard
    @Published public var activePlayback: ActivePlaybackTarget? = nil
    @Published public var isPlayerPresented: Bool = false
    @Published public var selectedMediaDetail: MediaItem? = nil
    @Published public var activeToast: ToastNotification? = nil
    /// True while sources are looked up and resolved, before the player opens.
    @Published public private(set) var isPreparingPlayback: Bool = false
    /// Shows the VPN screen: on launch, and when a film is started without a tunnel.
    @Published public var isVPNGatePresented: Bool = false
    /// Onboarding page index. Lives here rather than in the view because changing the
    /// language or palette rebuilds the view tree, which would otherwise reset it to 0.
    @Published public var onboardingStep: Int = 0
    /// Address handed over from the omnibox when it turned out not to be an addon.
    /// The browser tab picks it up and clears it.
    @Published public var pendingBrowserUrl: String? = nil

    /// True until the launch animation has played. Shown on every cold start, whether or
    /// not onboarding is done.
    @Published public var isLaunching: Bool = true
    @Published public var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey)
        }
    }
    
    public init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
    }
    
    public func completeOnboarding() {
        withAnimation(.easeInOut(duration: 0.35)) {
            self.hasCompletedOnboarding = true
        }
    }
    
    public func resetOnboarding() {
        withAnimation(.easeInOut(duration: 0.35)) {
            self.hasCompletedOnboarding = false
        }
    }
    
    /// Closes the detail sheet, then runs `action` once its dismissal has finished.
    ///
    /// SwiftUI allows one presentation at a time, so anything that presents the player
    /// cover — or switches tabs — while the sheet is still on screen (or still animating
    /// away) is silently dropped. Both callers needed the identical dance, so it lives
    /// here once; 0.45 s covers the dismissal.
    private func afterSheetDismissal(_ action: @escaping @MainActor () -> Void) {
        let sheetWasOpen = selectedMediaDetail != nil
        selectedMediaDetail = nil

        guard sheetWasOpen else {
            action()
            return
        }
        // A `@MainActor` closure is Sendable, so it can cross into the Task and still
        // touch this actor's state once it lands.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            action()
        }
    }

    public func startPlayback(item: MediaItem, episode: SeriesEpisodeItem? = nil, source: MediaSource? = nil, directUrl: URL? = nil, headers: [String: String]? = nil) {
        self.activePlayback = ActivePlaybackTarget(item: item, episode: episode, source: source, directUrl: directUrl, headers: headers)
        afterSheetDismissal { [weak self] in
            self?.isPlayerPresented = true
        }
    }

    /// Looks something up in the browser tab — used for cast members, where the app holds
    /// only a name and everything worth reading about the person is on the web.
    public func openInBrowser(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        afterSheetDismissal { [weak self] in
            // BrowserViewModel treats anything that is not a host as a search term.
            self?.pendingBrowserUrl = trimmed
            self?.selectedTab = .browser
        }
    }

    /// Everything needed to keep a playback session going: which sources are still
    /// untried, the subtitles fetched for this title, and the episode list for auto-play.
    /// Held here rather than in a view so it survives the detail sheet being dismissed.
    private struct PlaybackSession {
        let item: MediaItem
        var episode: SeriesEpisodeItem?
        var remainingSources: [MediaSource]
        var subtitles: [Subtitle]
        var attempts: Int = 0
    }

    private var session: PlaybackSession?
    /// Stop retrying after this many dead sources so a fully broken addon cannot loop.
    private static let maxSourceAttempts = 5

    /// Starts playback for an item that carries no resolved stream yet — the hero button
    /// and any other "play straight away" entry point. Reuses DetailViewModel's source
    /// lookup and resolver instead of duplicating that chain.
    public func startPlaybackResolvingSource(item: MediaItem, episode: SeriesEpisodeItem? = nil) async {
        isPreparingPlayback = true
        defer { isPreparingPlayback = false }
        // The source lookup already tells the addon what is about to be watched.
        guard await requireVPN(resume: { [weak self] in
            await self?.startPlaybackResolvingSource(item: item, episode: episode)
        }) else { return }
        let detail = DetailViewModel(item: item)
        var episode = episode
        // A series tile carries no episodes, and asking the addon for sources without one
        // returns nothing. Load the episode list and continue where the user left off.
        if episode == nil, item.isSeries || item.type == "series" {
            await detail.loadDetail()
            episode = Self.episodeToContinue(in: detail.item, history: StorageService.shared.watchHistory)
        }
        // Also covers IPTV entries, whose stream URL sits on the item itself.
        await detail.fetchSources(for: episode)

        DebugLog.log(detail.availableSources.isEmpty ? .error : .info, "Quellen", "\(detail.availableSources.count) Quellen gefunden\(detail.errorMessage.map { ", Fehler: \($0)" } ?? "")")
        guard !detail.availableSources.isEmpty else {
            showToast(
                message: detail.errorMessage ?? L("Keine Videoquellen für diesen Titel gefunden."),
                isError: true
            )
            return
        }

        // Subtitles are a nice-to-have: never let a failed lookup stop playback.
        let subtitles = await detail.fetchSubtitles(for: episode)

        await beginPlayback(
            item: item,
            episode: episode,
            sources: detail.availableSources,
            subtitles: subtitles
        )
    }

    /// The most recently watched episode of this series that exists in its episode list,
    /// otherwise the first one.
    static func episodeToContinue(in item: MediaItem, history: [WatchHistoryItem]) -> SeriesEpisodeItem? {
        let episodes = (item.episodes ?? []).sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
        let lastWatched = history
            .filter { $0.mediaItemId == item.id && $0.season != nil }
            .max { $0.updatedAt < $1.updatedAt }
        if let lastWatched,
           let match = episodes.first(where: { $0.season == lastWatched.season && $0.episode == lastWatched.episode }) {
            return match
        }
        return episodes.first
    }

    /// Single entry point for starting a title. Resolves the first usable source, resumes
    /// where the user left off, and remembers the rest of the list so a dead stream can
    /// fall through to the next one.
    public func beginPlayback(
        item: MediaItem,
        episode: SeriesEpisodeItem? = nil,
        sources: [MediaSource],
        subtitles: [Subtitle] = []
    ) async {
        session = PlaybackSession(
            item: item,
            episode: episode,
            remainingSources: sources,
            subtitles: subtitles
        )
        isPreparingPlayback = true
        defer { isPreparingPlayback = false }
        await playNextAvailableSource()
    }

    /// Connects the VPN if needed, or explains why nothing plays and offers the VPN
    /// screen. Every playback entry point calls this before talking to the addon.
    public func requireVPN(resume: (@MainActor () async -> Void)? = nil) async -> Bool {
        if await VPNManager.shared.ensureConnected() { return true }
        showToast(message: L("Wiedergabe läuft nur über das VPN. Bitte verbinde das VPN."), isError: true)
        pendingAfterVPN = resume
        isVPNGatePresented = true
        return false
    }

    /// What the user was starting when the VPN gate interrupted them; run once the
    /// tunnel is up, so connecting does not drop them back at the channel list.
    private var pendingAfterVPN: (@MainActor () async -> Void)?

    public func resumePendingPlaybackAfterVPN() {
        guard let pending = pendingAfterVPN else { return }
        pendingAfterVPN = nil
        Task { @MainActor in await pending() }
    }

    public func discardPendingPlaybackAfterVPN() { pendingAfterVPN = nil }

    /// Takes the next untried source and starts it. Called again by the player's failure
    /// callback, so a broken server advances instead of dead-ending.
    ///
    /// Everything plays through the VPN — films, series and Live TV. The tunnel is up
    /// before resolving, too: the hoster ties its stream link to the address that fetched
    /// the page, and the stream is then played from the VPN's address.
    private func playNextAvailableSource() async {
        guard var current = session else { return }

        guard await requireVPN(resume: { [weak self] in await self?.playNextAvailableSource() }) else {
            return
        }

        while !current.remainingSources.isEmpty {
            if current.attempts >= Self.maxSourceAttempts { break }
            let source = current.remainingSources.removeFirst()
            current.attempts += 1
            DebugLog.log(.info, "Wiedergabe", "Quelle \(current.attempts) von \(current.attempts + current.remainingSources.count): \(URL(string: source.url)?.host ?? "?") \(source.quality ?? "")")
            session = current

            let detail = DetailViewModel(item: current.item)
            do {
                let (resolvedUrl, resolvedHeaders) = try await detail.resolveAndGetStreamUrl(source: source)
                // The player plays a loopback URL; StreamProxyServer fetches every
                // playlist, segment and byte range through the tunnel.
                var streamHeaders = resolvedHeaders ?? [:]
                if streamHeaders["User-Agent"] == nil {
                    streamHeaders["User-Agent"] = MediaHubClient.defaultUserAgent
                }
                var upstream = resolvedUrl
                if let scheme = upstream.scheme, scheme.hasPrefix("mhub"),
                   let restored = CustomResourceLoader.restoreOriginalURL(from: upstream) {
                    upstream = restored
                }
                let url = try await StreamProxyServer.shared.proxiedURL(for: upstream, headers: streamHeaders)
                let headers: [String: String]? = nil

                // Continue where this title (and, for a series, this episode) was left off.
                let resumeAt = StorageService.shared.getResumeTimestamp(
                    for: current.item.id,
                    episodeKey: Self.episodeKey(for: current.episode)
                )

                let allSubtitles = current.subtitles + (source.subtitles ?? [])

                PlayerService.shared.play(
                    url: url,
                    title: current.item.displayName,
                    subtitle: current.episode?.displayName,
                    mediaItemId: current.item.id,
                    posterUrl: current.item.posterUrl,
                    season: current.episode?.season,
                    episode: current.episode?.episode,
                    customHeaders: headers,
                    subtitles: allSubtitles.isEmpty ? nil : allSubtitles,
                    startPosition: resumeAt > 0 ? resumeAt : nil,
                    mediaItem: current.item,
                    routedThroughVPN: true
                )
                installPlayerCallbacks()
                DebugLog.log(.info, "Wiedergabe", "Stream bereit, Start bei \(Int(resumeAt)) s")
                startPlayback(
                    item: current.item,
                    episode: current.episode,
                    source: source,
                    directUrl: url,
                    headers: headers
                )
                return
            } catch {
                // Resolving failed — try the next source rather than reporting straight away.
                print("Quelle fehlgeschlagen (\(source.url)): \(error)"); DebugLog.log(.warning, "Wiedergabe", "Quelle fehlgeschlagen (\(source.url)): \(error)")
                current = session ?? current
                continue
            }
        }

        session = nil
        // Every source failed: leave the black player instead of stranding the user in it.
        if isPlayerPresented { dismissPlayer() }
        showToast(
            message: "\(L("Stream konnte nicht geladen werden")): \(L("Keine Videoquellen für diesen Titel gefunden."))",
            isError: true
        )
    }

    /// The history key for an episode has to match how the history entry was written,
    /// otherwise resuming silently never matches for series — so both go through
    /// WatchHistoryItem's shared implementation.
    public static func episodeKey(for episode: SeriesEpisodeItem?) -> String? {
        guard let episode else { return nil }
        return WatchHistoryItem.episodeKey(season: episode.season, episode: episode.episode)
    }

    /// Auto-play of the next episode, honouring the setting. Only applies to series, and
    /// only while the next episode actually exists in the loaded episode list.
    public func playNextEpisodeIfEnabled() async {
        guard StorageService.shared.settings.autoPlayNextEpisode,
              let current = session,
              let episode = current.episode else { return }

        let detail = DetailViewModel(item: current.item)
        await detail.loadDetail()

        let episodes = (detail.item.episodes ?? [])
            .filter { $0.season == episode.season }
            .sorted { $0.episode < $1.episode }

        guard let next = episodes.first(where: { $0.episode > episode.episode }) else { return }

        await detail.fetchSources(for: next)
        guard !detail.availableSources.isEmpty else { return }
        let subtitles = await detail.fetchSubtitles(for: next)

        await beginPlayback(
            item: current.item,
            episode: next,
            sources: detail.availableSources,
            subtitles: subtitles
        )
    }

    private func installPlayerCallbacks() {
        PlayerService.shared.onPlaybackFailed = { [weak self] _ in
            Task { @MainActor in await self?.playNextAvailableSource() }
        }
        PlayerService.shared.onPlaybackEnded = { [weak self] in
            Task { @MainActor in await self?.playNextEpisodeIfEnabled() }
        }
    }

    public func dismissPlayer() {
        self.isPlayerPresented = false
        self.activePlayback = nil
        PlayerService.shared.stopAndCleanup()
    }
    
    public func showToast(message: String, icon: String? = nil, isError: Bool = false) {
        let toast = ToastNotification(message: message, icon: icon, isError: isError)
        withAnimation(AppMotion.standard) {
            self.activeToast = toast
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.activeToast?.id == toast.id {
                withAnimation(.easeOut(duration: 0.25)) {
                    self.activeToast = nil
                }
            }
        }
    }
    
    public func openURL(_ url: URL) {
        let urlString = url.absoluteString
        if url.scheme == "mhub" || url.scheme == "mediaurl" || urlString.contains(".json") {
            Task {
                do {
                    let manifest = try await AddonManager.shared.addAddon(from: urlString)
                    showToast(message: "\(L("Addon")) '\(manifest.name.value)' \(L("erfolgreich installiert!"))", icon: "checkmark.seal.fill")
                } catch {
                    showToast(message: "\(L("Fehler beim Installieren des Addons")): \(error.localizedDescription)", isError: true)
                }
            }
        }
    }
}
