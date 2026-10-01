import Foundation
import Combine

@MainActor
public class CatalogViewModel: ObservableObject {
    public let addonEndpoint: String
    public let catalogId: String
    public let catalogName: String
    public let features: CatalogFeatures?
    
    @Published public var items: [MediaItem] = []
    @Published public var isLoading: Bool = false
    @Published public var isLoadingMore: Bool = false
    @Published public var hasMore: Bool = true
    @Published public var cursor: String? = nil
    @Published public var searchQuery: String = ""
    @Published public var selectedSort: String? = nil
    @Published public var selectedFilters: [String: String] = [:] // [filterId: value]
    @Published public var errorMessage: String? = nil
    
    private let client: MediaHubClient
    
    public init(
        addonEndpoint: String,
        catalogId: String,
        catalogName: String,
        features: CatalogFeatures? = nil,
        client: MediaHubClient = .shared
    ) {
        self.addonEndpoint = addonEndpoint
        self.catalogId = catalogId
        self.catalogName = catalogName
        self.features = features
        self.client = client
    }
    
    public func loadCatalog(reset: Bool = false) async {
        if reset {
            cursor = nil
            hasMore = true
            items = []
            isLoading = true
        } else {
            guard !isLoadingMore && hasMore else { return }
            isLoadingMore = true
        }
        
        errorMessage = nil
        
        do {
            let activeSearch = searchQuery.isEmpty ? nil : searchQuery
            // Filters and sorting change the result set, so only the unfiltered listing is
            // cached — otherwise a cached page could be shown for the wrong filter.
            let cacheable = selectedFilters.isEmpty && selectedSort == nil
            if cacheable, reset,
               let cached = CatalogCache.shared.value(
                   endpoint: addonEndpoint, catalogId: catalogId, cursor: cursor, search: activeSearch
               ) {
                self.items = cached.items
                self.cursor = cached.nextCursor?.stringValue
                self.hasMore = (cached.nextCursor != nil && cached.nextCursor != .null && !cached.items.isEmpty)
                self.isLoading = false
                self.isLoadingMore = false
                return
            }

            let response = try await client.fetchCatalog(
                endpoint: addonEndpoint,
                catalogId: catalogId,
                search: activeSearch,
                sort: selectedSort,
                filter: selectedFilters.isEmpty ? nil : selectedFilters,
                cursor: cursor
            )

            if cacheable {
                CatalogCache.shared.store(
                    items: response.items,
                    nextCursor: response.nextCursor,
                    endpoint: addonEndpoint,
                    catalogId: catalogId,
                    cursor: cursor,
                    search: activeSearch
                )
            }
            
            if reset {
                self.items = response.items
            } else {
                // Deduplicate items
                var currentSet = Set(self.items.map { $0.id })
                let newItems = response.items.filter { currentSet.insert($0.id).inserted }
                self.items.append(contentsOf: newItems)
            }
            
            self.cursor = response.nextCursor?.stringValue
            self.hasMore = (response.nextCursor != nil && response.nextCursor != .null && !response.items.isEmpty)
            self.isLoading = false
            self.isLoadingMore = false
        } catch {
            self.isLoading = false
            self.isLoadingMore = false
            self.errorMessage = error.localizedDescription
        }
    }
    
    public func loadMoreIfNeeded(currentItem: MediaItem) {
        guard let last = items.last, last.id == currentItem.id else { return }
        guard hasMore && !isLoading && !isLoadingMore else { return }
        
        Task {
            await loadCatalog(reset: false)
        }
    }
    
    public func applySort(_ sortId: String?) {
        self.selectedSort = sortId
        Task {
            await loadCatalog(reset: true)
        }
    }
    
    public func setFilter(id: String, value: String?) {
        if let val = value, !val.isEmpty {
            selectedFilters[id] = val
        } else {
            selectedFilters.removeValue(forKey: id)
        }
        Task {
            await loadCatalog(reset: true)
        }
    }
    
    public func resetFilters() {
        selectedSort = nil
        selectedFilters = [:]
        searchQuery = ""
        Task {
            await loadCatalog(reset: true)
        }
    }
}
