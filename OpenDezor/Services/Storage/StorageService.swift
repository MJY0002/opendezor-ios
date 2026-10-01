import Foundation
import Combine
import SwiftUI

@MainActor
public class StorageService: ObservableObject {
    public static let shared = StorageService()
    
    private let db: DatabaseManager
    private let settingsKey = "opendezor_settings"
    
    @Published public var savedAddons: [SavedAddon] = []
    @Published public var watchHistory: [WatchHistoryItem] = []
    @Published public var favorites: [FavoriteItem] = []
    @Published public var searchHistory: [String] = []
    @Published public var customIPTVChannels: [MediaItem] = []
    @Published public var settings: AppSettings = AppSettings()
    
    public init(databaseManager: DatabaseManager = .shared) {
        self.db = databaseManager
        loadAll()
    }
    
    public func loadAll() {
        self.savedAddons = db.getAllAddons()
        self.watchHistory = db.getWatchHistory()
        self.favorites = db.getAllFavorites()
        self.searchHistory = db.getSearchHistory()
        self.customIPTVChannels = db.getAllCustomIPTV()
        loadSettings()
    }
    
    // MARK: - Addons Management
    public func saveAddon(_ addon: SavedAddon) {
        db.saveAddon(addon)
        if let idx = savedAddons.firstIndex(where: { $0.id == addon.id }) {
            savedAddons[idx] = addon
        } else {
            savedAddons.insert(addon, at: 0)
        }
    }
    
    public func saveAddon(manifest: AddonManifest, endpoint: String) {
        let saved = SavedAddon(
            id: manifest.id,
            url: endpoint,
            name: manifest.displayName,
            isEnabled: true,
            iconUrl: manifest.icon,
            description: manifest.description?.value
        )
        saveAddon(saved)
    }
    
    public func removeAddon(id: String) {
        db.deleteAddon(id: id)
        savedAddons.removeAll(where: { $0.id == id })
    }
    
    public func toggleAddon(id: String) {
        if let idx = savedAddons.firstIndex(where: { $0.id == id }) {
            var updated = savedAddons[idx]
            updated.isEnabled.toggle()
            db.saveAddon(updated)
            savedAddons[idx] = updated
        }
    }
    
    public func getAddon(id: String) -> SavedAddon? {
        savedAddons.first(where: { $0.id == id })
    }
    
    // MARK: - Watch History Management
    public func updateHistory(
        mediaItemId: String,
        title: String,
        posterUrl: String?,
        itemType: String,
        season: Int? = nil,
        episode: Int? = nil,
        position: Double,
        duration: Double,
        mediaItem: MediaItem? = nil
    ) {
        let historyId = mediaItemId + (WatchHistoryItem.episodeKey(season: season, episode: episode) ?? "")
        let item = WatchHistoryItem(
            mediaItemId: mediaItemId,
            title: title,
            posterUrl: posterUrl,
            itemType: itemType,
            season: season,
            episode: episode,
            lastPositionSeconds: position,
            durationSeconds: duration,
            updatedAt: Date(),
            // Periodic saves may not carry the item; keep the one the row already has.
            item: mediaItem ?? watchHistory.first(where: { $0.id == historyId })?.item
        )
        
        db.saveHistoryItem(item)
        
        if let idx = watchHistory.firstIndex(where: { $0.id == item.id }) {
            watchHistory[idx] = item
        } else {
            watchHistory.insert(item, at: 0)
        }
        
        if watchHistory.count > 100 {
            watchHistory = Array(watchHistory.prefix(100))
        }
    }
    
    public func getResumeTimestamp(for mediaItemId: String, episodeKey: String? = nil) -> Double {
        let targetId = mediaItemId + (episodeKey ?? "")
        guard let item = watchHistory.first(where: { $0.id == targetId }) else {
            return 0
        }
        // If almost finished (> 95%), restart from beginning
        if item.isCompleted || (item.durationSeconds > 0 && (item.lastPositionSeconds / item.durationSeconds) >= 0.95) {
            return 0
        }
        return item.lastPositionSeconds
    }
    
    public func getProgress(for mediaItemId: String, episodeKey: String? = nil) -> Double {
        let targetId = mediaItemId + (episodeKey ?? "")
        return watchHistory.first(where: { $0.id == targetId })?.progressRatio ?? 0
    }
    
    public func clearHistory() {
        db.clearAllHistory()
        watchHistory.removeAll()
    }
    
    // MARK: - Favorites Management
    public func isFavorite(mediaItemId: String) -> Bool {
        favorites.contains(where: { $0.mediaItemId == mediaItemId })
    }
    
    public func toggleFavorite(mediaItem: MediaItem) {
        if isFavorite(mediaItemId: mediaItem.id) {
            removeFavorite(mediaItemId: mediaItem.id)
        } else {
            let fav = FavoriteItem(
                mediaItemId: mediaItem.id,
                title: mediaItem.displayName,
                posterUrl: mediaItem.posterUrl,
                itemType: mediaItem.type ?? "movie",
                addedAt: Date(),
                item: mediaItem
            )
            db.saveFavorite(fav)
            favorites.insert(fav, at: 0)
        }
    }
    
    public func removeFavorite(mediaItemId: String) {
        db.deleteFavorite(mediaItemId: mediaItemId)
        favorites.removeAll(where: { $0.mediaItemId == mediaItemId })
    }
    
    // MARK: - Search History Management
    public func addSearchQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        db.addSearchQuery(trimmed)
        searchHistory.removeAll(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        searchHistory.insert(trimmed, at: 0)
        if searchHistory.count > settings.searchHistoryLimit {
            searchHistory = Array(searchHistory.prefix(settings.searchHistoryLimit))
        }
    }
    
    public func clearSearchHistory() {
        db.clearSearchHistory()
        searchHistory.removeAll()
    }
    
    // MARK: - Custom IPTV Channels Management
    public func saveCustomIPTVChannels(_ items: [MediaItem]) {
        db.saveCustomIPTV(items)
        for item in items {
            if let idx = customIPTVChannels.firstIndex(where: { $0.id == item.id }) {
                customIPTVChannels[idx] = item
            } else {
                customIPTVChannels.append(item)
            }
        }
    }
    
    public func removeCustomIPTVChannel(id: String) {
        db.deleteCustomIPTV(id: id)
        customIPTVChannels.removeAll(where: { $0.id == id })
    }
    
    public func clearCustomIPTVChannels() {
        db.clearAllCustomIPTV()
        customIPTVChannels.removeAll()
    }
    
    // MARK: - Settings Management
    public func updateSettings(_ newSettings: AppSettings) {
        self.settings = newSettings
        if let data = try? JSONEncoder().encode(newSettings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
        applyPreferences(newSettings)
    }

    /// Pushes appearance and language out to the controllers and the protocol client, so
    /// a settings change takes effect everywhere without the caller having to know who
    /// needs telling.
    public func applyPreferences(_ settings: AppSettings) {
        ThemeController.shared.apply(settings)
        LocalizationController.shared.apply(settings.language)
        ImageCache.applyLimit(megabytes: settings.maxCacheSizeMB)
        MediaHubClient.shared.userLanguage = settings.language.protocolCode
        MediaHubClient.shared.userRegion = settings.language.regionCode
    }
    
    /// Mutate-and-save, animated. Settings screens change one field at a time and all of
    /// them have to go through `updateSettings` so theme, language and the protocol client
    /// stay in sync — so the whole dance lives here rather than in each view.
    public func update(_ mutate: (inout AppSettings) -> Void) {
        var next = settings
        mutate(&next)
        withAnimation(.easeInOut(duration: 0.25)) {
            updateSettings(next)
        }
    }

    public func resetSettings() {
        updateSettings(AppSettings())
    }
    
    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = saved
        } else {
            self.settings = AppSettings()
        }
        applyPreferences(self.settings)
    }
}
