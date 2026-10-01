import XCTest
@testable import OpenDezor

@MainActor
final class StorageServiceTests: XCTestCase {
    
    private var db: DatabaseManager!
    private var storage: StorageService!
    
    override func setUp() async throws {
        try await super.setUp()
        db = DatabaseManager(inMemory: true)
        storage = StorageService(databaseManager: db)
    }
    
    override func tearDown() async throws {
        storage = nil
        db = nil
        try await super.tearDown()
    }
    
    // MARK: - Addon Storage Tests
    func testSaveAndToggleAddon() {
        let addon = SavedAddon(
            id: "hub.test",
            url: "https://hub.test/mediahubmx.json",
            name: "Test MediaHub",
            isEnabled: true
        )
        
        storage.saveAddon(addon)
        XCTAssertEqual(storage.savedAddons.count, 1)
        XCTAssertEqual(storage.getAddon(id: "hub.test")?.name, "Test MediaHub")
        XCTAssertTrue(storage.savedAddons[0].isEnabled)
        
        // Toggle addon
        storage.toggleAddon(id: "hub.test")
        XCTAssertFalse(storage.getAddon(id: "hub.test")?.isEnabled ?? true)
        
        // Remove addon
        storage.removeAddon(id: "hub.test")
        XCTAssertEqual(storage.savedAddons.count, 0)
        XCTAssertNil(storage.getAddon(id: "hub.test"))
    }
    
    func testSaveAddonFromManifest() {
        let manifest = AddonManifest(
            id: "demo-addon.example",
            name: "Demo",
            version: "1.0.0",
            icon: "https://demo-addon.example/icon.png",
            description: "Live TV and Movies"
        )
        
        storage.saveAddon(manifest: manifest, endpoint: "https://demo-addon.example/api")
        XCTAssertEqual(storage.savedAddons.count, 1)
        let saved = storage.getAddon(id: "demo-addon.example")
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.url, "https://demo-addon.example/api")
        XCTAssertEqual(saved?.name, "Demo")
    }
    
    /// History and favourites used to rebuild items as `ids: ["id": mediaItemId]`, which
    /// addons reject — resuming or playing a favourite found no sources.
    func testHistoryAndFavoritesKeepTheAddonIdsThroughTheDatabase() {
        let movie = MediaItem(
            type: "series",
            ids: ["tmdb": "1413", "tmdb_id": "1413"],
            name: .single("American Horror Story"),
            images: ItemImages(poster: "https://img/p.jpg", backdrop: "https://img/b.jpg")
        )
        let channel = MediaItem(type: "iptv", ids: ["id": "abc"], name: .single("SKY"),
                                url: "https://other-addon.example/demo-iptv/play/abc")

        storage.updateHistory(mediaItemId: movie.id, title: movie.displayName, posterUrl: nil,
                              itemType: "series", season: 1, episode: 2, position: 60, duration: 3000,
                              mediaItem: movie)
        // A periodic save without the item must not erase it.
        storage.updateHistory(mediaItemId: movie.id, title: movie.displayName, posterUrl: nil,
                              itemType: "series", season: 1, episode: 2, position: 90, duration: 3000)
        storage.toggleFavorite(mediaItem: channel)

        let reloaded = StorageService(databaseManager: db)
        let history = reloaded.watchHistory.first?.asMediaItem
        XCTAssertEqual(history?.ids?["tmdb"], "1413")
        XCTAssertEqual(history?.id, movie.id)
        XCTAssertEqual(history?.images?.backdrop, "https://img/b.jpg")

        let favorite = reloaded.favorites.first?.asMediaItem
        XCTAssertEqual(favorite?.url, "https://other-addon.example/demo-iptv/play/abc")
        XCTAssertEqual(favorite?.id, channel.id)
    }

    // MARK: - Watch History Tests
    func testWatchHistoryProgressAndResume() {
        // 1. Movie watched 50%
        storage.updateHistory(
            mediaItemId: "movie_1",
            title: "Inception",
            posterUrl: "https://img.com/p.jpg",
            itemType: "movie",
            position: 3600,
            duration: 7200
        )
        
        XCTAssertEqual(storage.watchHistory.count, 1)
        XCTAssertEqual(storage.getProgress(for: "movie_1"), 0.5)
        XCTAssertEqual(storage.getResumeTimestamp(for: "movie_1"), 3600)
        
        // 2. Series episode watched 96% (should reset resume timestamp to 0 for restart)
        storage.updateHistory(
            mediaItemId: "series_1",
            title: "Breaking Bad",
            posterUrl: "https://img.com/bb.jpg",
            itemType: "series",
            season: 1,
            episode: 1,
            position: 2880,
            duration: 3000
        )
        
        XCTAssertEqual(storage.watchHistory.count, 2)
        XCTAssertEqual(storage.getResumeTimestamp(for: "series_1", episodeKey: "_s1e1"), 0)
        
        // Clear history
        storage.clearHistory()
        XCTAssertEqual(storage.watchHistory.count, 0)
    }
    
    // MARK: - Favorites Tests
    func testToggleFavorite() {
        let movie = MediaItem(
            customId: "fav_movie",
            type: "movie",
            name: "Interstellar",
            images: ItemImages(poster: "https://img.com/interstellar.jpg")
        )
        
        XCTAssertFalse(storage.isFavorite(mediaItemId: movie.id))
        
        // Add to favorites
        storage.toggleFavorite(mediaItem: movie)
        XCTAssertTrue(storage.isFavorite(mediaItemId: movie.id))
        XCTAssertEqual(storage.favorites.count, 1)
        XCTAssertEqual(storage.favorites[0].title, "Interstellar")
        
        // Remove from favorites via toggle
        storage.toggleFavorite(mediaItem: movie)
        XCTAssertFalse(storage.isFavorite(mediaItemId: movie.id))
        XCTAssertEqual(storage.favorites.count, 0)
    }
    
    // MARK: - Search History Tests
    func testSearchHistoryDeduplicationAndLimit() {
        storage.addSearchQuery("Marvel")
        storage.addSearchQuery("Batman")
        storage.addSearchQuery("marvel") // Case-insensitive duplicate should move to front
        
        XCTAssertEqual(storage.searchHistory.count, 2)
        XCTAssertEqual(storage.searchHistory[0], "marvel")
        XCTAssertEqual(storage.searchHistory[1], "Batman")
        
        storage.clearSearchHistory()
        XCTAssertEqual(storage.searchHistory.count, 0)
    }
    
    // MARK: - App Settings Tests
    func testAppSettingsPersistence() {
        var settings = AppSettings()
        settings.defaultQuality = "4K"
        settings.autoPlayNextEpisode = false
        settings.preferredAudioLanguage = "en"
        
        storage.updateSettings(settings)
        XCTAssertEqual(storage.settings.defaultQuality, "4K")
        XCTAssertFalse(storage.settings.autoPlayNextEpisode)
        XCTAssertEqual(storage.settings.preferredAudioLanguage, "en")
        
        // Reset settings
        storage.resetSettings()
        XCTAssertEqual(storage.settings.defaultQuality, "1080p")
        XCTAssertTrue(storage.settings.autoPlayNextEpisode)
    }
}
