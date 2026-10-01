import Foundation
import Combine

@MainActor
public class DetailViewModel: ObservableObject {
    @Published public var item: MediaItem
    @Published public var selectedSeason: Int = 1
    @Published public var availableSources: [MediaSource] = []
    @Published public var isLoadingSources: Bool = false
    @Published public var isLoadingDetail: Bool = false
    @Published public var isResolvingSource: Bool = false
    @Published public var selectedEpisode: SeriesEpisodeItem? = nil
    @Published public var errorMessage: String? = nil
    
    private let client: MediaHubClient
    private let storage: StorageService
    private let addonManager: AddonManager
    
    public init(
        item: MediaItem,
        client: MediaHubClient,
        storage: StorageService,
        addonManager: AddonManager
    ) {
        self.item = item
        self.client = client
        self.storage = storage
        self.addonManager = addonManager
        
        if let firstEp = item.episodes?.first {
            self.selectedSeason = firstEp.season
            self.selectedEpisode = firstEp
        }
    }
    
    public convenience init(item: MediaItem) {
        self.init(item: item, client: .shared, storage: .shared, addonManager: .shared)
    }
    
    /// The addon this item came from, falling back to the first enabled one.
    private var addon: ActiveAddon? {
        if let addonId = item.addonId,
           let match = addonManager.activeAddons.first(where: { $0.id == addonId }) {
            return match
        }
        return addonManager.activeAddons.first(where: { $0.isEnabled })
    }

    private var addonEndpoint: String? {
        addon?.endpoint
    }

    /// The manifest's `urlPatterns` declare which source URLs have to go through the
    /// addon's `resolve` action. Matching against them is the protocol's own rule —
    /// guessing from substrings like "gateway" misses IPTV links and every extractor host.
    private func needsResolving(_ source: MediaSource) -> Bool {
        if source.resolved == true { return false }
        if source.type == "externalUrl" || source.type == "resolver" { return true }

        // Addons also claim their own `{addonId}://` scheme by default.
        if let addonId = addon?.id, source.url.lowercased().hasPrefix("\(addonId.lowercased())://") {
            return true
        }

        guard let patterns = addon?.manifest.urlPatterns else { return false }
        let url = source.url
        let range = NSRange(url.startIndex..., in: url)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            if regex.firstMatch(in: url, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    /// Catalog entries carry only enough for a poster tile — no episodes, cast or synopsis.
    /// The `item` action returns the full record, and for a series it is the only way to
    /// get the episode list that the source lookup needs.
    public func loadDetail() async {
        guard let endpoint = addonEndpoint else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }

        do {
            let detailed = try await client.fetchItemDetail(
                endpoint: endpoint,
                itemType: item.type ?? "movie",
                ids: item.ids ?? ["id": item.id],
                name: item.displayName
            )
            self.item = detailed.filled(from: item)

            if let firstEp = detailed.episodes?.first {
                self.selectedSeason = firstEp.season
                if self.selectedEpisode == nil {
                    self.selectedEpisode = firstEp
                }
            }
        } catch {
            // The catalog entry stays usable, so a failed detail fetch is not fatal.
            print("Detail-Abruf fehlgeschlagen: \(error)")
        }
    }

    public var isFavorite: Bool {
        storage.isFavorite(mediaItemId: item.id)
    }
    
    public func toggleFavorite() {
        storage.toggleFavorite(mediaItem: item)
        objectWillChange.send()
    }
    
    public var episodesForSelectedSeason: [SeriesEpisodeItem] {
        guard let eps = item.episodes else { return [] }
        return eps.filter { $0.season == selectedSeason }.sorted { $0.episode < $1.episode }
    }
    
    public var availableSeasons: [Int] {
        guard let eps = item.episodes else { return [1] }
        let seasons = Set(eps.map { $0.season })
        return Array(seasons).sorted()
    }
    
    // MARK: - Fetch Streaming Sources
    public func fetchSources(for episode: SeriesEpisodeItem? = nil) async {
        isLoadingSources = true
        errorMessage = nil
        availableSources = []
        
        let ep = episode ?? self.selectedEpisode

        // IPTV entries carry their stream URL on the item itself and the addon has no
        // `source` for them — asking it returns nothing ("No sources found"). Wrap the URL
        // so it still goes through needsResolving/StreamResolver.
        if let direct = item.url, !direct.isEmpty {
            self.availableSources = [MediaSource(url: direct, name: .single(item.displayName))] + (item.sources ?? [])
            self.isLoadingSources = false
            return
        }

        guard let endpoint = addonEndpoint else {
            // Check if item already has direct sources embedded
            if let embedded = item.sources, !embedded.isEmpty {
                self.availableSources = embedded
                self.isLoadingSources = false
                return
            }
            self.isLoadingSources = false
            self.errorMessage = L("Kein aktives Addon zum Laden von Quellen gefunden.")
            return
        }
        
        do {
            let sources = try await client.fetchSources(endpoint: endpoint, item: item, episode: ep)
            self.availableSources = Self.sortedByPreferredQuality(
                sources,
                preferred: storage.settings.defaultQuality
            )
            self.isLoadingSources = false
        } catch {
            // Fallback to item embedded sources if present
            if let embedded = item.sources, !embedded.isEmpty {
                self.availableSources = embedded
            } else {
                self.errorMessage = error.localizedDescription
            }
            self.isLoadingSources = false
        }
    }
    
    /// Orders sources so the user's preferred quality comes first, then descending by
    /// resolution. Addons return them in arbitrary order, and the first entry is what
    /// playback starts with.
    static func sortedByPreferredQuality(_ sources: [MediaSource], preferred: String) -> [MediaSource] {
        /// Vertical resolution parsed out of labels like "1080p", "FullHD", "4K".
        func rank(_ quality: String?) -> Int {
            guard let q = quality?.lowercased(), !q.isEmpty else { return 0 }
            if q.contains("2160") || q.contains("4k") || q.contains("uhd") { return 2160 }
            if q.contains("1440") { return 1440 }
            if q.contains("1080") || q.contains("fullhd") || q.contains("fhd") { return 1080 }
            if q.contains("720") || q.contains("hd") { return 720 }
            if q.contains("480") || q.contains("sd") { return 480 }
            if q.contains("360") { return 360 }
            if let digits = q.split(whereSeparator: { !$0.isNumber }).first, let n = Int(digits) { return n }
            return 0
        }

        let target = rank(preferred)
        return sources.enumerated().sorted { lhs, rhs in
            let l = rank(lhs.element.quality), r = rank(rhs.element.quality)
            // Exact matches for the preferred quality win outright.
            if (l == target) != (r == target) { return l == target }
            if l != r { return l > r }
            // Stable: keep the addon's own order for equally ranked sources.
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Subtitles offered by the addon for this item. Separate from the ones embedded in a
    /// MediaSource — most addons only expose them through the `subtitle` action.
    /// Never throws: missing subtitles must not stop playback.
    public func fetchSubtitles(for episode: SeriesEpisodeItem? = nil) async -> [Subtitle] {
        guard let endpoint = addonEndpoint else { return [] }
        do {
            return try await client.fetchSubtitles(
                endpoint: endpoint,
                item: item,
                episode: episode ?? selectedEpisode
            )
        } catch {
            print("Untertitel-Abruf fehlgeschlagen: \(error)")
            return []
        }
    }

    // MARK: - Resolve & Prepare Stream for Playback
    public func resolveAndGetStreamUrl(source: MediaSource) async throws -> (url: URL, headers: [String: String]?) {
        isResolvingSource = true
        defer { isResolvingSource = false }
        
        var effectiveHeaders = source.headers ?? [:]
        
        if needsResolving(source), let targetEndpoint = addonEndpoint {
            // StreamResolver walks multi-hop chains (resolveAgain) and merges headers
            // along the way, which a single resolveSource call would stop short of.
            // A failure propagates on purpose: a URL that needs resolving is a hoster page,
            // not a stream. Handing it to the player left it black at 00:00; throwing lets
            // AppState move on to the next source instead.
            let stream = try await StreamResolver.shared.resolve(
                source: source,
                addonEndpoint: targetEndpoint,
                addonManifest: addon?.manifest
            )
            for (k, v) in stream.headers {
                effectiveHeaders[k] = v
            }
            return (stream.url, effectiveHeaders.isEmpty ? nil : effectiveHeaders)
        }
        
        guard let directUrl = URL(string: source.url) else {
            throw MediaHubError.invalidUrl(source.url)
        }
        return (directUrl, effectiveHeaders.isEmpty ? nil : effectiveHeaders)
    }
}
