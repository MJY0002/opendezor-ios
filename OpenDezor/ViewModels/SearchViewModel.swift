import Foundation

/// What the search page is narrowed to. Chosen before or after a search; the results of
/// one search are fetched once and filtered locally, so switching is instant.
public enum SearchScope: String, CaseIterable, Identifiable {
    case all, movies, series, live, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return L("Alle")
        case .movies: return L("Filme")
        case .series: return L("Serien")
        case .live: return L("Live TV")
        case .other: return L("Sonstiges")
        }
    }

    public var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .movies: return "film"
        case .series: return "tv"
        case .live: return "antenna.radiowaves.left.and.right"
        case .other: return "ellipsis.circle"
        }
    }

    /// The one concrete scope an item belongs to (never `.all`).
    public static func classify(_ item: MediaItem) -> SearchScope {
        if item.isSeries { return .series }
        switch item.type?.lowercased() {
        case "movie": return .movies
        case "iptv", "channel": return .live
        default: return .other
        }
    }
}

@MainActor
public final class SearchViewModel: ObservableObject {
    @Published public var query: String = ""
    @Published public var scope: SearchScope = .all
    @Published public private(set) var results: [MediaItem] = []
    @Published public private(set) var isSearching = false
    /// The query the current `results` belong to; nil until a search ran.
    @Published public private(set) var searchedQuery: String? = nil

    private let addonManager: AddonManager
    private let storage: StorageService

    public init(addonManager: AddonManager, storage: StorageService) {
        self.addonManager = addonManager
        self.storage = storage
    }

    public convenience init() {
        self.init(addonManager: .shared, storage: .shared)
    }

    public var recentSearches: [String] { storage.searchHistory }

    public var visibleResults: [MediaItem] {
        scope == .all ? results : results.filter { SearchScope.classify($0) == scope }
    }

    public func count(for scope: SearchScope) -> Int {
        scope == .all ? results.count : results.filter { SearchScope.classify($0) == scope }.count
    }

    /// `remember` records the query in the history; only an explicit submit does, so the
    /// half-typed prefixes of search-as-you-type do not pile up there.
    public func search(remember: Bool = false) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            searchedQuery = nil
            isSearching = false
            return
        }
        if remember { storage.addSearchQuery(trimmed) }
        guard trimmed != searchedQuery else { return }
        isSearching = true
        let found = await addonManager.searchAll(query: trimmed)
        // A newer keystroke cancelled this search; leave the newer one to publish.
        guard !Task.isCancelled else { return }
        results = found
        searchedQuery = trimmed
        isSearching = false
    }

    /// Debounced search-as-you-type; `.task(id: query)` cancels it on the next keystroke.
    public func searchAfterPause() async {
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard !Task.isCancelled else { return }
        await search()
    }
}
