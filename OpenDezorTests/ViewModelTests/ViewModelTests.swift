import XCTest
@testable import OpenDezor

final class ViewModelTests: XCTestCase {
    
    // MARK: - Omnibox URL Detection Tests
    @MainActor
    func testOmniboxUrlDetection() {
        let vm = OmniboxViewModel()
        
        XCTAssertTrue(vm.isInputUrl("https://mediahubmx.com"))
        XCTAssertTrue(vm.isInputUrl("http://example.com/stream.m3u8"))
        XCTAssertTrue(vm.isInputUrl("mhub://addon.bundle.json"))
        XCTAssertTrue(vm.isInputUrl("mediaurl://feed.json"))
        XCTAssertTrue(vm.isInputUrl("my-addon.dezor.net/mediahubmx.json"))
        XCTAssertTrue(vm.isInputUrl("example.org/feed.json"))
        
        XCTAssertFalse(vm.isInputUrl("Inception"))
        XCTAssertFalse(vm.isInputUrl("Breaking Bad Season 1"))
        XCTAssertFalse(vm.isInputUrl(""))
    }
    
    // MARK: - DetailViewModel Season and Episode Tests
    @MainActor
    func testDetailViewModelEpisodesFiltering() {
        let ep1 = SeriesEpisodeItem(
            ids: ["id": "ep1"],
            name: .single("Pilot"),
            originalName: nil,
            description: .single("Erste Episode"),
            releaseDate: "2024-01-01",
            poster: nil,
            season: 1,
            episode: 1,
            sources: nil
        )
        let ep2 = SeriesEpisodeItem(
            ids: ["id": "ep2"],
            name: .single("Episode 2"),
            originalName: nil,
            description: nil,
            releaseDate: "2024-01-08",
            poster: nil,
            season: 1,
            episode: 2,
            sources: nil
        )
        let ep3 = SeriesEpisodeItem(
            ids: ["id": "ep3"],
            name: .single("Season 2 Premiere"),
            originalName: nil,
            description: nil,
            releaseDate: "2025-01-01",
            poster: nil,
            season: 2,
            episode: 1,
            sources: nil
        )
        
        let seriesItem = MediaItem(
            customId: "series_1",
            type: "series",
            ids: ["id": "series_1"],
            name: .single("Test Serie"),
            originalName: nil,
            description: nil,
            releaseDate: "2024",
            year: 2024,
            runtime: 45,
            images: nil,
            genres: ["Drama"],
            cast: nil,
            director: nil,
            sources: nil,
            episodes: [ep1, ep2, ep3],
            url: nil,
            logo: nil,
            category: nil,
            group: nil,
            country: nil,
            catalogId: nil,
            addonId: nil
        )
        
        let detailVM = DetailViewModel(item: seriesItem)
        XCTAssertEqual(detailVM.availableSeasons, [1, 2])
        XCTAssertEqual(detailVM.selectedSeason, 1)
        
        let s1Episodes = detailVM.episodesForSelectedSeason
        XCTAssertEqual(s1Episodes.count, 2)
        XCTAssertEqual(s1Episodes[0].id, "ep1")
        XCTAssertEqual(s1Episodes[1].id, "ep2")
        
        detailVM.selectedSeason = 2
        let s2Episodes = detailVM.episodesForSelectedSeason
        XCTAssertEqual(s2Episodes.count, 1)
        XCTAssertEqual(s2Episodes[0].id, "ep3")
    }
    
    // MARK: - CatalogViewModel Filter State Tests
    @MainActor
    func testCatalogViewModelFilterState() {
        let vm = CatalogViewModel(
            addonEndpoint: "https://example.com",
            catalogId: "movies",
            catalogName: "Filme"
        )
        
        XCTAssertNil(vm.selectedSort)
        XCTAssertTrue(vm.selectedFilters.isEmpty)
        
        vm.applySort("popularity")
        XCTAssertEqual(vm.selectedSort, "popularity")
        
        vm.setFilter(id: "genre", value: "action")
        XCTAssertEqual(vm.selectedFilters["genre"], "action")
        
        vm.resetFilters()
        XCTAssertNil(vm.selectedSort)
        XCTAssertTrue(vm.selectedFilters.isEmpty)
    }

    /// A hand-off from another screen (the omnibox, or tapping a cast member) arrives
    /// before the browser tab has ever been shown, so `load` runs while the web view is
    /// still nil. That request used to be dropped: the address bar showed the URL and the
    /// tab stayed blank.
    @MainActor
    func testLoadBeforeAttachIsNotLost() {
        let vm = BrowserViewModel()

        vm.load("Danny Lau")

        // The address is reflected immediately so the bar is correct either way...
        XCTAssertTrue(vm.displayedAddress.contains("duckduckgo.com"))
        XCTAssertTrue(vm.displayedAddress.contains("Danny"))
        // ...and the request itself is queued rather than discarded.
        XCTAssertTrue(vm.hasPendingLoad, "load() before attach() must be replayed on attach")
    }

    /// Search terms with reserved characters must survive as one query.
    @MainActor
    func testSearchEncodesReservedCharacters() {
        let url = BrowserViewModel.searchURL(for: "swift & rust")
        XCTAssertNotNil(url)
        // A bare "&" would split the query into a second, bogus parameter.
        XCTAssertFalse(url!.absoluteString.contains("q=swift & rust"))
        XCTAssertTrue(url!.absoluteString.contains("%26"))
    }

}
