import Foundation
import Combine

public struct DashboardSection: Identifiable {
    public var id: String { "\(addonId)_\(dashboard.id)" }
    public let addonId: String
    public let addonEndpoint: String
    public let dashboard: DashboardItem
    public var items: [MediaItem]
    public var isLoading: Bool
}

@MainActor
public class DashboardViewModel: ObservableObject {
    @Published public var heroItem: MediaItem? = nil
    /// Featured titles for the rotating hero: wide artwork only, films and series only,
    /// a couple from each row so the carousel is not six titles from the same list.
    @Published public var heroItems: [MediaItem] = []
    static let maxHeroItems = 6
    @Published public var sections: [DashboardSection] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    private let client: MediaHubClient
    private let addonManager: AddonManager
    private let storage: StorageService
    
    public init(
        client: MediaHubClient,
        addonManager: AddonManager,
        storage: StorageService
    ) {
        self.client = client
        self.addonManager = addonManager
        self.storage = storage
    }
    
    public convenience init() {
        self.init(client: .shared, addonManager: .shared, storage: .shared)
    }
    
    public var continueWatching: [WatchHistoryItem] {
        storage.watchHistory
    }
    
    public var favorites: [FavoriteItem] {
        storage.favorites
    }
    
    public func loadDashboard() async {
        isLoading = true
        errorMessage = nil
        // Otherwise the hero keeps showing a title from an addon the user just removed.
        heroItem = nil
        heroItems = []

        let dashboards = await addonManager.fetchAllDashboards()
        
        var loadedSections: [DashboardSection] = []
        for (addon, dash) in dashboards {
            let initialItems: [MediaItem] = dash.initialData?.items ?? []
            let section = DashboardSection(
                addonId: addon.id,
                addonEndpoint: addon.endpoint,
                dashboard: dash,
                items: initialItems,
                isLoading: initialItems.isEmpty
            )
            loadedSections.append(section)
        }
        self.sections = loadedSections
        self.isLoading = false
        
        // Fetch items for sections that didn't have initialData in parallel
        await withTaskGroup(of: (String, [MediaItem]).self) { group in
            for section in loadedSections where section.items.isEmpty {
                let secId = section.id
                let endpoint = section.addonEndpoint
                let catId = section.dashboard.catalogId ?? section.dashboard.id
                // The dashboard's own id selects the sub-list inside the catalog
                // (e.g. "movie/trendingDay" vs "movie/popularity"). Dropping it makes
                // every dashboard of the same catalog render identical rows.
                let dashId = section.dashboard.customId

                group.addTask {
                    // Serve a recent response first so the row is populated immediately;
                    // a cold start otherwise shows empty shelves until the network answers.
                    if let cached = CatalogCache.shared.value(endpoint: endpoint, catalogId: catId, id: dashId) {
                        return (secId, cached.items)
                    }
                    do {
                        let response = try await self.client.fetchCatalog(
                            endpoint: endpoint,
                            catalogId: catId,
                            id: dashId
                        )
                        CatalogCache.shared.store(
                            items: response.items,
                            nextCursor: response.nextCursor,
                            endpoint: endpoint,
                            catalogId: catId,
                            id: dashId
                        )
                        return (secId, response.items)
                    } catch {
                        return (secId, [])
                    }
                }
            }
            
            for await (secId, items) in group {
                if let idx = self.sections.firstIndex(where: { $0.id == secId }) {
                    self.sections[idx].items = items
                    self.sections[idx].isLoading = false
                    
                    // Prefer a title that actually ships wide artwork. The old test used
                    // `backdropUrl`, which falls back to the poster and so matched
                    // everything — the hero was simply whichever row answered first.
                    let featured = items
                        .filter { $0.wideArtworkUrl != nil && !$0.isIPTV }
                        .filter { item in !self.heroItems.contains(where: { $0.id == item.id }) }
                        .prefix(2)
                    self.heroItems.append(contentsOf: featured.prefix(max(0, Self.maxHeroItems - self.heroItems.count)))

                    if !items.isEmpty, let candidate = items.first(where: { $0.wideArtworkUrl != nil }) {
                        if self.heroItem?.wideArtworkUrl == nil {
                            self.heroItem = candidate
                        }
                    } else if self.heroItem == nil {
                        self.heroItem = items.first
                    }
                }
            }
        }
    }
}
