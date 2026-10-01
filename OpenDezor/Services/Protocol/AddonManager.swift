import Foundation
import Combine

public struct ActiveAddon: Identifiable, Equatable {
    public var id: String { manifest.id }
    public let manifest: AddonManifest
    public let endpoint: String
    public var isEnabled: Bool
    
    public init(manifest: AddonManifest, endpoint: String, isEnabled: Bool = true) {
        self.manifest = manifest
        self.endpoint = endpoint
        self.isEnabled = isEnabled
    }
}

@MainActor
public class AddonManager: ObservableObject {
    public static let shared = AddonManager()
    
    private let client: MediaHubClient
    private let detector: AddonDetector
    private let storage: StorageService
    
    @Published public var activeAddons: [ActiveAddon] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    public init(
        client: MediaHubClient = .shared,
        detector: AddonDetector = .shared,
        storage: StorageService? = nil
    ) {
        self.client = client
        self.detector = detector
        self.storage = storage ?? StorageService.shared
        Task {
            await reloadAllAddons()
        }
    }
    
    public func reloadAllAddons() async {
        isLoading = true
        errorMessage = nil
        
        // Detection probes several URLs per addon, so doing this one after another made
        // cold start scale linearly with the number of installed addons. The saved order
        // is restored afterwards so the dashboard sections do not shuffle between starts.
        let saved = storage.savedAddons
        var byIndex: [Int: ActiveAddon] = [:]

        await withTaskGroup(of: (Int, ActiveAddon?).self) { group in
            for (index, entry) in saved.enumerated() {
                group.addTask {
                    do {
                        let (manifest, endpoint) = try await self.detector.detect(from: entry.url)
                        return (index, ActiveAddon(manifest: manifest, endpoint: endpoint, isEnabled: entry.isEnabled))
                    } catch {
                        print("Failed to load saved addon \(entry.name) (\(entry.url)): \(error)")
                        return (index, nil)
                    }
                }
            }
            for await (index, addon) in group {
                if let addon { byIndex[index] = addon }
            }
        }

        let loaded = saved.indices.compactMap { byIndex[$0] }
        self.activeAddons = loaded
        self.isLoading = false
    }
    
    public func addAddon(from urlString: String) async throws -> AddonManifest {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let (manifest, endpoint) = try await detector.detect(from: urlString)
            let saved = SavedAddon(
                id: manifest.id,
                url: urlString,
                name: manifest.displayName,
                isEnabled: true,
                iconUrl: manifest.icon,
                description: manifest.description?.value
            )
            storage.saveAddon(saved)
            
            if let idx = activeAddons.firstIndex(where: { $0.id == manifest.id }) {
                activeAddons[idx] = ActiveAddon(manifest: manifest, endpoint: endpoint, isEnabled: true)
            } else {
                activeAddons.append(ActiveAddon(manifest: manifest, endpoint: endpoint, isEnabled: true))
            }
            
            return manifest
        } catch {
            self.errorMessage = error.localizedDescription
            throw error
        }
    }
    
    public func removeAddon(id: String) {
        storage.removeAddon(id: id)
        activeAddons.removeAll(where: { $0.id == id })
    }
    
    public func toggleAddon(id: String) {
        storage.toggleAddon(id: id)
        if let idx = activeAddons.firstIndex(where: { $0.id == id }) {
            activeAddons[idx].isEnabled.toggle()
        }
    }
    
    // MARK: - Dashboards Aggregation
    public func fetchAllDashboards() async -> [(addon: ActiveAddon, dashboard: DashboardItem)] {
        activeAddons.filter(\.isEnabled).flatMap { addon -> [(addon: ActiveAddon, dashboard: DashboardItem)] in
            // `pages` is the modern shape; `catalogs` is the fallback for addons that
            // predate it, each catalog standing in as a one-row dashboard.
            if let pages = addon.manifest.pages {
                return pages.flatMap { $0.dashboards ?? [] }.map { (addon, $0) }
            }
            return (addon.manifest.catalogs ?? []).map { cat in
                (addon, DashboardItem(
                    customId: cat.id,
                    type: cat.kind ?? "directory",
                    catalogId: cat.id,
                    addonId: addon.id,
                    name: cat.name,
                    options: cat.options,
                    features: cat.features,
                    initialData: nil
                ))
            }
        }
    }
    
    // MARK: - Universal Search
    public func searchAll(query: String) async -> [MediaItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        
        var allItems: [MediaItem] = []
        
        await withTaskGroup(of: [MediaItem].self) { group in
            for addon in activeAddons where addon.isEnabled {
                if let catalogs = addon.manifest.catalogs {
                    for cat in catalogs where (cat.features?.search?.enabled ?? true) {
                        group.addTask {
                            do {
                                let response = try await self.client.fetchCatalog(
                                    endpoint: addon.endpoint,
                                    catalogId: cat.id,
                                    search: query
                                )
                                return response.items
                            } catch {
                                return []
                            }
                        }
                    }
                }
            }
            
            for await items in group {
                allItems.append(contentsOf: items)
            }
        }
        
        var seen = Set<String>()
        return allItems.filter { seen.insert($0.id).inserted }
    }
}
