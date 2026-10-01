import XCTest
@testable import OpenDezor

final class ModelParsingTests: XCTestCase {
    
    // MARK: - TranslatedText Tests
    func testTranslatedTextSingleString() throws {
        let json = "\"Single Title\"".data(using: .utf8)!
        let text = try JSONDecoder().decode(TranslatedText.self, from: json)
        XCTAssertEqual(text.value, "Single Title")
        XCTAssertEqual(text.description, "Single Title")
    }
    
    func testTranslatedTextLocalizedDictionary() throws {
        let json = "{\"en\": \"English Title\", \"de\": \"Deutscher Titel\"}".data(using: .utf8)!
        let text = try JSONDecoder().decode(TranslatedText.self, from: json)
        // Check that either German or English is returned depending on current locale
        XCTAssertTrue(text.value == "Deutscher Titel" || text.value == "English Title")
    }
    
    func testTranslatedTextStringLiteral() {
        let text: TranslatedText = "Literal Title"
        XCTAssertEqual(text.value, "Literal Title")
    }
    
    // MARK: - AnyCodableValue Tests
    func testAnyCodableValueTypes() throws {
        let strJson = "\"hello\"".data(using: .utf8)!
        let strVal = try JSONDecoder().decode(AnyCodableValue.self, from: strJson)
        XCTAssertEqual(strVal.stringValue, "hello")
        
        let intJson = "42".data(using: .utf8)!
        let intVal = try JSONDecoder().decode(AnyCodableValue.self, from: intJson)
        XCTAssertEqual(intVal.stringValue, "42")
        
        let dblJson = "3.14".data(using: .utf8)!
        let dblVal = try JSONDecoder().decode(AnyCodableValue.self, from: dblJson)
        XCTAssertEqual(dblVal.stringValue, "3.14")
        
        let boolJson = "true".data(using: .utf8)!
        let boolVal = try JSONDecoder().decode(AnyCodableValue.self, from: boolJson)
        XCTAssertEqual(boolVal.stringValue, "true")
        
        let nullJson = "null".data(using: .utf8)!
        let nullVal = try JSONDecoder().decode(AnyCodableValue.self, from: nullJson)
        XCTAssertNil(nullVal.stringValue)
    }
    
    // MARK: - FilterValue Tests
    func testFilterValueVariants() throws {
        let strJson = "\"Action\"".data(using: .utf8)!
        let strFilter = try JSONDecoder().decode(FilterValue.self, from: strJson)
        XCTAssertEqual(strFilter.displayTitle, "Action")
        XCTAssertEqual(strFilter.keyString, "Action")
        
        let objJson = "{\"key\": \"scifi\", \"value\": \"Science Fiction\"}".data(using: .utf8)!
        let objFilter = try JSONDecoder().decode(FilterValue.self, from: objJson)
        XCTAssertEqual(objFilter.displayTitle, "Science Fiction")
        XCTAssertEqual(objFilter.keyString, "scifi")
    }
    
    // MARK: - AddonManifest Parsing Tests
    func testAddonManifestFullParsing() throws {
        let data = MockAddonData.sampleManifestJSON.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: data)
        
        XCTAssertEqual(manifest.id, "demo-addon.example")
        XCTAssertEqual(manifest.version, "1.4.2")
        XCTAssertEqual(manifest.author, "Dezor Team")
        XCTAssertEqual(manifest.adult, false)
        XCTAssertEqual(manifest.endpoints, ["https://demo-addon.example/api"])
        XCTAssertEqual(manifest.actions, ["catalog", "item", "source", "subtitle", "resolve"])
        
        // Catalogs
        guard let catalogs = manifest.catalogs else {
            XCTFail("Missing catalogs in manifest")
            return
        }
        XCTAssertEqual(catalogs.count, 3)
        let movieCat = catalogs[0]
        XCTAssertEqual(movieCat.id, "movies_popular")
        XCTAssertEqual(movieCat.kind, "vod")
        XCTAssertEqual(movieCat.options?.shape, "portrait")
        XCTAssertEqual(movieCat.features?.search?.enabled, true)
        XCTAssertEqual(movieCat.features?.sort?.count, 2)
        XCTAssertEqual(movieCat.features?.filter?.count, 1)
        XCTAssertEqual(movieCat.features?.filter?.first?.defaultValue, "action")
        
        // Pages
        guard let pages = manifest.pages, let firstPage = pages.first else {
            XCTFail("Missing pages in manifest")
            return
        }
        XCTAssertEqual(firstPage.id, "home")
        XCTAssertEqual(firstPage.dashboards?.count, 1)
        XCTAssertEqual(firstPage.dashboards?.first?.catalogId, "movies_popular")
    }
    
    // MARK: - Catalog Response & MediaItem Parsing
    func testCatalogMoviesResponseParsing() throws {
        let data = MockAddonData.sampleCatalogMoviesResponseJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(CatalogResponse.self, from: data)
        
        XCTAssertEqual(response.items.count, 2)
        XCTAssertEqual(response.nextCursor?.stringValue, "page_2_cursor_token")
        
        let fightClub = response.items[0]
        XCTAssertEqual(fightClub.id, "movie_101")
        XCTAssertEqual(fightClub.type, "movie")
        XCTAssertEqual(fightClub.originalName, "Fight Club")
        XCTAssertEqual(fightClub.year, 1999)
        XCTAssertEqual(fightClub.runtime, 139)
        XCTAssertEqual(fightClub.score, 8.8)
        XCTAssertEqual(fightClub.genres, ["Drama", "Thriller"])
        XCTAssertEqual(fightClub.cast?.count, 2)
        XCTAssertEqual(fightClub.director?.count, 1)
        XCTAssertEqual(fightClub.posterUrl, "https://image.tmdb.org/t/p/w500/fight_club.jpg")
        XCTAssertEqual(fightClub.backdropUrl, "https://image.tmdb.org/t/p/w1280/fight_club_bg.jpg")
        XCTAssertFalse(fightClub.isSeries)
        XCTAssertFalse(fightClub.isIPTV)
    }
    
    // MARK: - Series Item Detail Parsing
    func testSeriesDetailParsing() throws {
        let data = MockAddonData.sampleItemDetailSeriesResponseJSON.data(using: .utf8)!
        let series = try JSONDecoder().decode(MediaItem.self, from: data)
        
        XCTAssertEqual(series.id, "series_201")
        XCTAssertEqual(series.type, "series")
        XCTAssertTrue(series.isSeries)
        XCTAssertEqual(series.episodes?.count, 2)
        
        let ep1 = series.episodes![0]
        XCTAssertEqual(ep1.id, "bb_s1e1")
        XCTAssertEqual(ep1.season, 1)
        XCTAssertEqual(ep1.episode, 1)
        XCTAssertEqual(ep1.releaseDate, "2008-01-20")
    }
    
    // MARK: - MediaSource & Subtitle Parsing
    func testSourcesAndSubtitlesParsing() throws {
        let data = MockAddonData.sampleSourcesResponseJSON.data(using: .utf8)!
        let sources = try JSONDecoder().decode([MediaSource].self, from: data)
        
        XCTAssertEqual(sources.count, 2)
        
        let directSrc = sources[0]
        XCTAssertEqual(directSrc.id, "src_1080p")
        XCTAssertEqual(directSrc.quality, "1080p")
        XCTAssertEqual(directSrc.format, "hls")
        XCTAssertTrue(directSrc.isDirectStream)
        XCTAssertEqual(directSrc.headers?["User-Agent"], "DezorPlayer/1.0")
        XCTAssertEqual(directSrc.subtitles?.count, 2)
        
        let sub1 = directSrc.subtitles![0]
        XCTAssertEqual(sub1.displayLanguage, "DE")
        XCTAssertEqual(sub1.format, .vtt)
        
        let sub2 = directSrc.subtitles![1]
        XCTAssertEqual(sub2.displayLanguage, "EN")
        XCTAssertEqual(sub2.format, .srt)
        
        let gatewaySrc = sources[1]
        XCTAssertEqual(gatewaySrc.type, "resolver")
        XCTAssertFalse(gatewaySrc.isDirectStream)
    }
    
    // MARK: - ResolvedUrl & StreamFormat Tests
    func testResolvedUrlParsing() throws {
        let data = MockAddonData.sampleResolvedUrlJSON.data(using: .utf8)!
        let resolved = try JSONDecoder().decode(ResolvedUrl.self, from: data)
        
        XCTAssertEqual(resolved.url, "https://stream.resolved-host.com/live/index.m3u8")
        XCTAssertEqual(resolved.quality, "1080p")
        XCTAssertEqual(resolved.format, "hls")
        XCTAssertEqual(resolved.headers?["Authorization"], "Bearer sample_token_123")
        XCTAssertEqual(resolved.resolveAgain, false)
        
        let format = StreamFormat.detect(from: resolved.url, hint: resolved.format)
        XCTAssertEqual(format, .hls)
    }
    
    // MARK: - Storage Models Tests
    func testStorageModelsLogic() {
        let addon = SavedAddon(id: "test.hub", url: "https://test.hub", name: "Test Hub", isEnabled: true)
        XCTAssertEqual(addon.id, "test.hub")
        XCTAssertTrue(addon.isEnabled)
        
        let history = WatchHistoryItem(
            mediaItemId: "m1",
            title: "Test Movie",
            posterUrl: "https://img.com/p.jpg",
            itemType: "movie",
            season: 2,
            episode: 4,
            lastPositionSeconds: 920,
            durationSeconds: 1000
        )
        XCTAssertEqual(history.id, "m1_s2e4")
        XCTAssertEqual(history.progressRatio, 0.92)
        XCTAssertTrue(history.isCompleted) // >= 90% completed
        
        let favorite = FavoriteItem(mediaItemId: "m1", title: "Test Movie", posterUrl: nil, itemType: "movie", addedAt: Date())
        XCTAssertEqual(favorite.id, "m1")
        
        let settings = AppSettings()
        XCTAssertEqual(settings.defaultQuality, "1080p")
        XCTAssertTrue(settings.autoPlayNextEpisode)
    }

    /// Addons disagree about the unit of `runtime`: most send minutes, some seconds, some
    /// milliseconds. Printing it raw produced "800000 Min" in the detail view.
    func testRuntimeIsInterpretedByMagnitude() {
        func item(_ runtime: Int?) -> MediaItem {
            MediaItem(customId: "x", type: "movie", name: .single("X"), runtime: runtime)
        }

        // Already minutes — the common case, and what the mock catalog sends.
        XCTAssertEqual(item(139).formattedRuntime, "2 \(L("Std.")) 19 \(L("Min."))")
        XCTAssertEqual(item(45).formattedRuntime, "45 \(L("Min."))")
        // Exactly on the hour drops the dangling "0 Min".
        XCTAssertEqual(item(120).formattedRuntime, "2 \(L("Std."))")
        // Seconds.
        XCTAssertEqual(item(8_340).formattedRuntime, "2 \(L("Std.")) 19 \(L("Min."))")
        // Milliseconds — the value that produced the bug.
        XCTAssertEqual(item(8_340_000).formattedRuntime, "2 \(L("Std.")) 19 \(L("Min."))")
        XCTAssertEqual(item(800_000).formattedRuntime, "13 \(L("Min."))")
        // Nothing usable stays nil rather than rendering "0 Min".
        XCTAssertNil(item(nil).formattedRuntime)
        XCTAssertNil(item(0).formattedRuntime)
    }

    /// Some addons' `item` action for an IPTV channel echoes only type/ids/name. Replacing the
    /// catalog entry with it lost the stream URL and logo, so the channel had no sources.
    func testDetailResponseKeepsCatalogStreamUrlAndArtwork() throws {
        let catalog = try JSONDecoder().decode(MediaItem.self, from: Data("""
        {"type":"iptv","ids":{"id":"abc"},"name":"SKY","url":"https://other-addon.example/demo-iptv/play/abc",
         "logo":"https://logo.example/abc.png","images":{"poster":"https://img/p.jpg","backdrop":""}}
        """.utf8))
        let detail = try JSONDecoder().decode(MediaItem.self, from: Data("""
        {"type":"iptv","ids":{"id":"abc"},"name":"SKY","images":{"backdrop":"https://img/b.jpg"}}
        """.utf8))

        let merged = detail.filled(from: catalog)

        XCTAssertEqual(merged.url, "https://other-addon.example/demo-iptv/play/abc")
        XCTAssertEqual(merged.logo, "https://logo.example/abc.png")
        XCTAssertEqual(merged.images?.poster, "https://img/p.jpg")
        XCTAssertEqual(merged.images?.backdrop, "https://img/b.jpg")
        XCTAssertEqual(merged.id, catalog.id)
    }

}
