import XCTest
@testable import OpenDezor

/// Covers the playback chain that was previously wired up only halfway: resuming a
/// title, ordering sources by the preferred quality, and retrying only the kinds of
/// failure that are worth retrying.
final class PlaybackChainTests: XCTestCase {

    // MARK: - Resume Keys

    /// Reading and writing the history key has to agree, otherwise resuming a series
    /// silently never matches — which is exactly what happened before.
    @MainActor
    func testEpisodeKeyMatchesHistoryEntry() {
        let entry = WatchHistoryItem(
            mediaItemId: "tt123",
            title: "Reacher",
            posterUrl: nil,
            itemType: "series",
            season: 2,
            episode: 5,
            lastPositionSeconds: 120,
            durationSeconds: 2400,
            updatedAt: Date()
        )

        let episode = SeriesEpisodeItem(season: 2, episode: 5)
        XCTAssertEqual(AppState.episodeKey(for: episode), entry.episodeKey)
        XCTAssertEqual(entry.id, "tt123" + (AppState.episodeKey(for: episode) ?? ""))
    }

    /// The hero "play" button on a series has no episode. Sources are only returned per
    /// episode, so it continues the last one watched, or starts at the first.
    @MainActor
    func testSeriesPlayContinuesLastWatchedEpisode() {
        let series = MediaItem(
            customId: "tt123", type: "series",
            episodes: [
                SeriesEpisodeItem(season: 2, episode: 1),
                SeriesEpisodeItem(season: 1, episode: 1),
                SeriesEpisodeItem(season: 1, episode: 2)
            ]
        )
        XCTAssertEqual(AppState.episodeToContinue(in: series, history: [])?.season, 1)
        XCTAssertEqual(AppState.episodeToContinue(in: series, history: [])?.episode, 1)

        let watched = [
            WatchHistoryItem(mediaItemId: "tt123", title: "R", itemType: "series", season: 1, episode: 2,
                             updatedAt: Date(timeIntervalSince1970: 100)),
            WatchHistoryItem(mediaItemId: "tt123", title: "R", itemType: "series", season: 2, episode: 1,
                             updatedAt: Date(timeIntervalSince1970: 200))
        ]
        let next = AppState.episodeToContinue(in: series, history: watched)
        XCTAssertEqual(next?.season, 2)
        XCTAssertEqual(next?.episode, 1)
    }

    @MainActor
    func testEpisodeKeyIsNilForMovies() {
        XCTAssertNil(AppState.episodeKey(for: nil))
        XCTAssertNil(WatchHistoryItem.episodeKey(season: nil, episode: 3))
        XCTAssertNil(WatchHistoryItem.episodeKey(season: 1, episode: nil))
    }

    // MARK: - Resume Position

    @MainActor
    func testResumeReturnsSavedPositionAndRestartsWhenNearlyFinished() {
        let storage = StorageService(databaseManager: DatabaseManager(inMemory: true))

        storage.updateHistory(
            mediaItemId: "movie1", title: "Film", posterUrl: nil, itemType: "movie",
            position: 300, duration: 6000
        )
        XCTAssertEqual(storage.getResumeTimestamp(for: "movie1"), 300)

        // Past 95 % the title counts as watched and should start over.
        storage.updateHistory(
            mediaItemId: "movie2", title: "Film", posterUrl: nil, itemType: "movie",
            position: 5900, duration: 6000
        )
        XCTAssertEqual(storage.getResumeTimestamp(for: "movie2"), 0)
    }

    @MainActor
    func testResumeIsPerEpisode() {
        let storage = StorageService(databaseManager: DatabaseManager(inMemory: true))
        let e1 = SeriesEpisodeItem(season: 1, episode: 1)
        let e2 = SeriesEpisodeItem(season: 1, episode: 2)

        storage.updateHistory(
            mediaItemId: "show", title: "Serie", posterUrl: nil, itemType: "series",
            season: 1, episode: 1, position: 400, duration: 2400
        )

        XCTAssertEqual(storage.getResumeTimestamp(for: "show", episodeKey: AppState.episodeKey(for: e1)), 400)
        // A different episode of the same series must not inherit that position.
        XCTAssertEqual(storage.getResumeTimestamp(for: "show", episodeKey: AppState.episodeKey(for: e2)), 0)
    }

    // MARK: - Source Ordering

    @MainActor
    func testPreferredQualityIsOrderedFirst() {
        let sources = [
            MediaSource(url: "a", quality: "480p"),
            MediaSource(url: "b", quality: "1080p"),
            MediaSource(url: "c", quality: "4K"),
            MediaSource(url: "d", quality: "720p")
        ]

        let ordered = DetailViewModel.sortedByPreferredQuality(sources, preferred: "720p")
        XCTAssertEqual(ordered.first?.url, "d", "Die bevorzugte Qualität muss zuerst kommen")
        // Everything after it is ranked descending.
        XCTAssertEqual(ordered.dropFirst().map(\.quality), ["4K", "1080p", "480p"])
    }

    @MainActor
    func testSourcesWithoutQualityKeepAddonOrder() {
        let sources = [
            MediaSource(url: "first", name: .single("Server A")),
            MediaSource(url: "second", name: .single("Server B")),
            MediaSource(url: "third", name: .single("Server C"))
        ]
        let ordered = DetailViewModel.sortedByPreferredQuality(sources, preferred: "1080p")
        XCTAssertEqual(ordered.map(\.url), ["first", "second", "third"])
    }

    // MARK: - Retry

    /// 5xx and transport errors are worth another attempt; a 4xx or a decoding failure
    /// would only be re-sent verbatim, so those must fail immediately.
    func testRetriesServerErrorsButNotClientErrors() async throws {
        MockURLProtocol.reset()
        let client = MediaHubClient(session: MockSessionFactory.makeMockSession())
        client.retryBaseDelay = 0

        var attempts = 0
        MockURLProtocol.requestHandler = { request in
            attempts += 1
            let body = MockAddonData.sampleCatalogMoviesResponseJSON.data(using: .utf8)!
            // Fail twice with a server error, then succeed.
            let status = attempts < 3 ? 503 : 200
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, body)
        }

        let response = try await client.fetchCatalog(endpoint: "https://addon.test", catalogId: "c")
        XCTAssertEqual(attempts, 3, "Nach zwei 5xx muss der dritte Versuch greifen")
        XCTAssertFalse(response.items.isEmpty)

        // A 404 must not be retried.
        MockURLProtocol.reset()
        attempts = 0
        MockURLProtocol.requestHandler = { request in
            attempts += 1
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        do {
            _ = try await client.fetchCatalog(endpoint: "https://addon.test", catalogId: "c")
            XCTFail("404 hätte werfen müssen")
        } catch {
            XCTAssertEqual(attempts, 1, "Ein 404 darf nicht wiederholt werden")
        }
        MockURLProtocol.reset()
    }

    // MARK: - Image Proxy

    func testImageProxyRewritesHttpUrlsAndLeavesIconsAlone() {
        let poster = "https://image.tmdb.org/t/p/original/abc.jpg"
        let proxied = ImageProxy.url(for: poster, size: .small)
        XCTAssertTrue(proxied.hasPrefix(ImageProxy.endpoint))
        XCTAssertTrue(proxied.contains("size=small"))
        // The original URL survives as a query parameter.
        XCTAssertTrue(proxied.contains("image.tmdb.org"))

        // Favicons and non-http inputs stay untouched.
        XCTAssertEqual(ImageProxy.url(for: "https://x.test/favicon.ico", size: .small), "https://x.test/favicon.ico")
        XCTAssertEqual(ImageProxy.url(for: "", size: .small), "")
    }

    // MARK: - Catalog Cache

    func testCatalogCacheRoundTripsAndIgnoresEmptyResults() {
        let cache = CatalogCache()
        let items = [MediaItem(customId: "1", type: "movie", name: .single("A"))]

        cache.store(items: items, nextCursor: nil, endpoint: "https://a.test", catalogId: "cat")
        XCTAssertEqual(cache.value(endpoint: "https://a.test", catalogId: "cat")?.items.count, 1)

        // A different catalog must not hit the same entry.
        XCTAssertNil(cache.value(endpoint: "https://a.test", catalogId: "other"))

        // Empty responses are usually transient failures and must not be cached.
        cache.store(items: [], nextCursor: nil, endpoint: "https://b.test", catalogId: "cat")
        XCTAssertNil(cache.value(endpoint: "https://b.test", catalogId: "cat"))
    }
}
