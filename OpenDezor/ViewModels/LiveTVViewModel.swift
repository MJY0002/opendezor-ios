import Foundation
import Combine

@MainActor
public class LiveTVViewModel: ObservableObject {
    @Published public var channels: [MediaItem] = []
    @Published public var categories: [String] = ["Alle"]
    @Published public var selectedCategory: String = "Alle"
    @Published public var searchQuery: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    private let client: MediaHubClient
    private let addonManager: AddonManager
    
    public init(
        client: MediaHubClient,
        addonManager: AddonManager
    ) {
        self.client = client
        self.addonManager = addonManager
    }
    
    public convenience init() {
        self.init(client: .shared, addonManager: .shared)
    }
    
    public var filteredChannels: [MediaItem] {
        var list = channels
        
        if selectedCategory != "Alle" {
            list = list.filter {
                $0.category?.caseInsensitiveCompare(selectedCategory) == .orderedSame ||
                $0.group?.caseInsensitiveCompare(selectedCategory) == .orderedSame
            }
        }
        
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let query = searchQuery.lowercased()
            list = list.filter {
                $0.displayName.lowercased().contains(query) ||
                ($0.category?.lowercased().contains(query) ?? false) ||
                ($0.group?.lowercased().contains(query) ?? false)
            }
        }
        
        return list
    }
    
    public func loadChannels() async {
        isLoading = true
        errorMessage = nil
        
        var allChannels: [MediaItem] = []
        var cats: Set<String> = ["Alle"]
        
        // 1. Addon channels
        for addon in addonManager.activeAddons where addon.isEnabled {
            if let catalogs = addon.manifest.catalogs {
                let iptvCatalogs = catalogs.filter { $0.kind == "iptv" || $0.id.lowercased().contains("iptv") || $0.id.lowercased().contains("channel") || $0.id.lowercased().contains("tv") }
                
                for cat in iptvCatalogs {
                    do {
                        let response = try await client.fetchCatalog(endpoint: addon.endpoint, catalogId: cat.id)
                        for item in response.items {
                            allChannels.append(item)
                            if let c = item.category, !c.isEmpty { cats.insert(c) }
                            if let g = item.group, !g.isEmpty { cats.insert(g) }
                        }
                    } catch {
                        print("Failed to load IPTV catalog \(cat.id): \(error)")
                    }
                }
            }
        }
        
        // 2. Custom M3U IPTV channels
        let customChannels = StorageService.shared.customIPTVChannels
        for item in customChannels {
            allChannels.append(item)
            if let c = item.category, !c.isEmpty { cats.insert(c) }
            if let g = item.group, !g.isEmpty { cats.insert(g) }
        }
        
        self.channels = allChannels
        var sortedCats = Array(cats.subtracting(["Alle"])).sorted()
        sortedCats.insert("Alle", at: 0)
        self.categories = sortedCats
        self.isLoading = false
    }
    
    // MARK: - M3U Import & Management
    public func importM3U(from input: String) async throws -> Int {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        
        var importedItems: [MediaItem] = []
        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" {
            importedItems = try await M3UParser.fetchAndParse(from: url)
        } else {
            importedItems = M3UParser.parse(content: trimmed)
        }
        
        guard !importedItems.isEmpty else { return 0 }
        
        StorageService.shared.saveCustomIPTVChannels(importedItems)
        await loadChannels()
        return importedItems.count
    }
    
    public func deleteCustomChannel(id: String) {
        StorageService.shared.removeCustomIPTVChannel(id: id)
        channels.removeAll(where: { $0.id == id })
    }
    
    public func clearAllCustomChannels() {
        StorageService.shared.clearCustomIPTVChannels()
        channels.removeAll(where: { $0.id.hasPrefix("m3u_") })
    }
    
}
