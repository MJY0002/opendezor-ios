import XCTest
@testable import OpenDezor

@MainActor
final class AddonE2ETests: XCTestCase {
    
    private var mockSession: URLSession!
    private var client: MediaHubClient!
    private var detector: AddonDetector!
    private var resolver: StreamResolver!
    private var db: DatabaseManager!
    private var storage: StorageService!
    private var addonManager: AddonManager!
    private var subtitleParser: SubtitleParser!
    
    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()
        mockSession = MockSessionFactory.makeMockSession()
        client = MediaHubClient(session: mockSession)
        client.retryBaseDelay = 0  // Kein Backoff in Tests
        detector = AddonDetector(client: client)
        resolver = StreamResolver(client: client)
        db = DatabaseManager(inMemory: true)
        storage = StorageService(databaseManager: db)
        addonManager = AddonManager(client: client, detector: detector, storage: storage)
        subtitleParser = SubtitleParser()
    }
    
    override func tearDown() async throws {
        MockURLProtocol.reset()
        mockSession = nil
        client = nil
        detector = nil
        resolver = nil
        storage = nil
        db = nil
        addonManager = nil
        subtitleParser = nil
        try await super.tearDown()
    }
    
    // MARK: - 1. Full E2E Workflow: Movie Discovery, Pagination, Stream Resolution, Subtitles & Persistence
    func testFullE2EMovieWorkflow() async throws {
        // Step 1: User inputs "mhub://demo-addon.example" into the Omnibox / Addon installation prompt
        let inputUrl = "mhub://demo-addon.example"
        let manifestProbeUrl = "https://demo-addon.example/mediahubmx.json"
        
        let sampleCatalogPage1JSON = """
        {
            "items": [
                {
                    "id": "movie_101",
                    "type": "movie",
                    "ids": { "tmdb_id": "550", "imdb_id": "tt0137523" },
                    "name": { "en": "Fight Club", "de": "Fight Club" },
                    "year": 1999,
                    "runtime": 139,
                    "rating": 8.8,
                    "images": {
                        "poster": "https://image.tmdb.org/t/p/w500/fight_club.jpg",
                        "backdrop": "https://image.tmdb.org/t/p/w1280/fight_club_bg.jpg"
                    }
                }
            ],
            "nextCursor": "page_2_cursor_token"
        }
        """
        
        let sampleCatalogPage2JSON = """
        {
            "items": [
                {
                    "id": "movie_102",
                    "type": "movie",
                    "ids": { "tmdb_id": "27205" },
                    "name": "Inception",
                    "year": 2010,
                    "runtime": 148,
                    "rating": 8.7,
                    "images": {
                        "poster": "https://image.tmdb.org/t/p/w500/inception.jpg"
                    }
                }
            ],
            "nextCursor": null
        }
        """
        
        let sampleMovieSourcesJSON = """
        [
            {
                "id": "src_gateway_movie",
                "type": "resolver",
                "url": "https://gateway.demo-addon.example/resolve?id=movie_102",
                "name": "Fast Cloud Stream (1080p)",
                "quality": "1080p",
                "format": "hls",
                "subtitles": [
                    {
                        "id": "sub_de",
                        "name": "Deutsch",
                        "language": "de",
                        "type": "vtt",
                        "url": "https://cdn.demo-addon.example/subs/inception_de.vtt"
                    }
                ]
            }
        ]
        """
        
        let sampleResolvedMovieJSON = """
        {
            "url": "https://stream.resolved-demo.example/live/inception_1080p.m3u8",
            "name": "Resolved Fast HLS Stream",
            "quality": "1080p",
            "format": "hls",
            "headers": {
                "Authorization": "Bearer token_movie_102",
                "Referer": "https://gateway.demo-addon.example"
            },
            "resolveAgain": false
        }
        """
        
        let sampleVttContent = """
        WEBVTT - Inception Subtitles

        1
        00:00:01.000 --> 00:00:04.000
        Was ist der widerstandsfähigste Parasit?

        2
        00:00:04.500 --> 00:00:08.000
        Ein Gedanke. Resistent, hochansteckend.
        """
        
        // Setup Network Interceptor for all actions in this flow
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                return (HTTPURLResponse(url: URL(string: "about:blank")!, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data())
            }
            
            // 1. Manifest discovery probe
            if url.absoluteString == manifestProbeUrl {
                let data = MockAddonData.sampleManifestJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            
            // 2. Catalog fetch (Page 1 vs Page 2)
            if url.path == "/api/mediahubmx-catalog.json" && request.httpMethod == "POST" {
                if let bodyData = request.extractedBodyData,
                   let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    if json["cursor"] as? String == "page_2_cursor_token" {
                        let data = sampleCatalogPage2JSON.data(using: .utf8)!
                        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
                    } else {
                        let data = sampleCatalogPage1JSON.data(using: .utf8)!
                        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
                    }
                }
            }
            
            // 3. Source fetch
            if url.path == "/api/mediahubmx-source.json" && request.httpMethod == "POST" {
                let data = sampleMovieSourcesJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            
            // 4. Stream Resolver
            if url.path == "/api/mediahubmx-resolve.json" && request.httpMethod == "POST" {
                let data = sampleResolvedMovieJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            
            // 5. Subtitle fetch
            if url.absoluteString == "https://cdn.demo-addon.example/subs/inception_de.vtt" {
                let data = sampleVttContent.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            
            return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        // Execute Step 1: Addon Discovery via custom scheme mhub://
        let (manifest, endpoint) = try await detector.detect(from: inputUrl)
        XCTAssertEqual(manifest.id, "demo-addon.example")
        XCTAssertEqual(manifest.displayName, "Demo Hub")
        XCTAssertEqual(endpoint, "https://demo-addon.example/api")
        
        // Execute Step 2: Install Addon into Storage & AddonManager
        let installedManifest = try await addonManager.addAddon(from: inputUrl)
        XCTAssertEqual(installedManifest.id, "demo-addon.example")
        XCTAssertEqual(storage.savedAddons.count, 1)
        XCTAssertTrue(storage.savedAddons[0].isEnabled)
        XCTAssertEqual(addonManager.activeAddons.count, 1)
        
        // Execute Step 3: Fetch Catalog with Filters & Pagination (Page 1)
        let catalogPage1 = try await client.fetchCatalog(
            endpoint: endpoint,
            catalogId: "movies_popular",
            search: nil,
            sort: "trending",
            filter: ["genre": "action"],
            cursor: nil
        )
        XCTAssertEqual(catalogPage1.items.count, 1)
        XCTAssertEqual(catalogPage1.items[0].id, "movie_101")
        XCTAssertEqual(catalogPage1.items[0].displayName, "Fight Club")
        XCTAssertEqual(catalogPage1.nextCursor?.stringValue, "page_2_cursor_token")
        
        // Execute Step 4: Paginate to Page 2 using cursor token
        let catalogPage2 = try await client.fetchCatalog(
            endpoint: endpoint,
            catalogId: "movies_popular",
            search: nil,
            sort: "trending",
            filter: ["genre": "action"],
            cursor: catalogPage1.nextCursor?.stringValue
        )
        XCTAssertEqual(catalogPage2.items.count, 1)
        let selectedMovie = catalogPage2.items[0]
        XCTAssertEqual(selectedMovie.id, "movie_102")
        XCTAssertEqual(selectedMovie.displayName, "Inception")
        XCTAssertNil(catalogPage2.nextCursor)
        
        // Execute Step 5: Fetch Stream Sources for Selected Movie
        let sources = try await client.fetchSources(endpoint: endpoint, item: selectedMovie)
        XCTAssertEqual(sources.count, 1)
        let source = sources[0]
        XCTAssertEqual(source.type, "resolver")
        XCTAssertEqual(source.quality, "1080p")
        XCTAssertEqual(source.subtitles?.count, 1)
        
        // Execute Step 6: Dynamic Stream Resolution via StreamResolver
        let resolvedStream = try await resolver.resolve(source: source, addonEndpoint: endpoint)
        XCTAssertEqual(resolvedStream.url.absoluteString, "https://stream.resolved-demo.example/live/inception_1080p.m3u8")
        XCTAssertEqual(resolvedStream.format, .hls)
        XCTAssertEqual(resolvedStream.quality, "1080p")
        XCTAssertEqual(resolvedStream.headers["Authorization"], "Bearer token_movie_102")
        XCTAssertEqual(resolvedStream.headers["Referer"], "https://gateway.demo-addon.example")
        XCTAssertNotNil(resolvedStream.headers["User-Agent"])
        
        // Execute Step 7: Parse Subtitles (.vtt)
        let subtitleObj = source.subtitles![0]
        XCTAssertEqual(subtitleObj.format, .vtt)
        let cues = subtitleParser.parse(content: sampleVttContent, format: "vtt")
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].startTime, 1.0)
        XCTAssertEqual(cues[0].endTime, 4.0)
        XCTAssertEqual(cues[0].text, "Was ist der widerstandsfähigste Parasit?")
        
        // Check active cue during playback at 2.5s
        let activeCue = subtitleParser.activeCue(in: cues, at: 2.5)
        XCTAssertNotNil(activeCue)
        XCTAssertEqual(activeCue?.id, 1)
        
        // Execute Step 8: Update Playback State in Persistent Storage
        // Watch movie for 20 minutes (1200s out of 8880s)
        storage.updateHistory(
            mediaItemId: selectedMovie.id,
            title: selectedMovie.displayName,
            posterUrl: selectedMovie.posterUrl,
            itemType: "movie",
            position: 1200.0,
            duration: 8880.0
        )
        
        // Verify Watch History progress ratio and resume timestamp
        XCTAssertEqual(storage.watchHistory.count, 1)
        XCTAssertEqual(storage.getProgress(for: selectedMovie.id), 1200.0 / 8880.0, accuracy: 0.001)
        XCTAssertEqual(storage.getResumeTimestamp(for: selectedMovie.id), 1200.0)
        
        // Add movie to Favorites
        storage.toggleFavorite(mediaItem: selectedMovie)
        XCTAssertTrue(storage.isFavorite(mediaItemId: selectedMovie.id))
        XCTAssertEqual(storage.favorites.count, 1)
        XCTAssertEqual(storage.favorites[0].title, "Inception")
    }
    
    // MARK: - 2. Full E2E Workflow: Series Discovery via Direct .json, Recursive Resolver & Multi-Episode Progress
    func testFullE2ESeriesWithEpisodesAndRecursiveResolver() async throws {
        // Step 1: Direct JSON Manifest Discovery
        let directJsonUrl = "https://media.dezor.tv/bundles/addon.json"
        
        let sampleSeriesSourcesJSON = """
        [
            {
                "id": "src_recursive_ep1",
                "type": "resolver",
                "url": "https://gateway.example.com/step1",
                "name": "Multi-Hop Cloud Stream",
                "subtitles": [
                    {
                        "id": "sub_en_srt",
                        "name": "English",
                        "language": "en",
                        "type": "srt",
                        "url": "https://cdn.example.com/bb_s1e1.srt"
                    }
                ]
            }
        ]
        """
        
        let sampleRecursiveStep1JSON = """
        {
            "url": "https://stream.step2-host.com/resolve_final",
            "name": "Intermediate Gateway Hop",
            "format": "hls",
            "resolveAgain": true
        }
        """
        
        let sampleRecursiveStep2JSON = """
        {
            "url": "https://stream.resolved-final.com/episodes/s1e1.m3u8",
            "name": "Final Playable HLS Stream",
            "quality": "1080p",
            "format": "hls",
            "headers": {
                "X-Custom-Auth": "SecretToken789"
            },
            "resolveAgain": false
        }
        """
        
        let sampleSRTContent = """
        1
        00:00:01,000 --> 00:00:03,500
        <b>Pilot Episode</b>
        
        2
        00:00:04,000 --> 00:00:07,000
        <i>Chemistry is the study of change.</i>
        """
        
        var hopCount = 0
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                return (HTTPURLResponse(url: URL(string: "about:blank")!, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data())
            }
            
            // 1. Direct JSON manifest
            if url.absoluteString == directJsonUrl {
                let data = MockAddonData.sampleManifestJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            
            // 2. Fetch Series item detail with episodes
            if url.path == "/api/mediahubmx-item.json" && request.httpMethod == "POST" {
                let data = MockAddonData.sampleItemDetailSeriesResponseJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            
            // 3. Fetch sources for episode
            if url.path == "/api/mediahubmx-source.json" && request.httpMethod == "POST" {
                let data = sampleSeriesSourcesJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            
            // 4. Recursive Stream Resolver
            if url.path == "/api/mediahubmx-resolve.json" && request.httpMethod == "POST" {
                hopCount += 1
                if hopCount == 1 {
                    let data = sampleRecursiveStep1JSON.data(using: .utf8)!
                    return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
                } else {
                    let data = sampleRecursiveStep2JSON.data(using: .utf8)!
                    return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
                }
            }
            
            return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        // Step 1: Detect Addon from direct JSON URL
        let (manifest, endpoint) = try await detector.detect(from: directJsonUrl)
        XCTAssertEqual(manifest.id, "demo-addon.example")
        
        // Install to storage
        storage.saveAddon(manifest: manifest, endpoint: endpoint)
        XCTAssertEqual(storage.savedAddons.count, 1)
        
        // Step 2: Fetch Series Item Detail
        let seriesDetail = try await client.fetchItemDetail(
            endpoint: endpoint,
            itemType: "series",
            ids: ["tmdb_id": "1396"],
            name: "Breaking Bad"
        )
        XCTAssertEqual(seriesDetail.id, "series_201")
        XCTAssertTrue(seriesDetail.isSeries)
        XCTAssertEqual(seriesDetail.episodes?.count, 2)
        
        let episode1 = seriesDetail.episodes![0]
        let episode2 = seriesDetail.episodes![1]
        XCTAssertEqual(episode1.season, 1)
        XCTAssertEqual(episode1.episode, 1)
        XCTAssertEqual(episode1.displayName, "Pilot")
        
        // Step 3: Fetch Sources for Episode 1
        let ep1Sources = try await client.fetchSources(endpoint: endpoint, item: seriesDetail, episode: episode1)
        XCTAssertEqual(ep1Sources.count, 1)
        let ep1Source = ep1Sources[0]
        XCTAssertEqual(ep1Source.type, "resolver")
        
        // Step 4: Resolve Multi-Hop Stream via StreamResolver
        let resolvedEp1 = try await resolver.resolve(source: ep1Source, addonEndpoint: endpoint)
        XCTAssertEqual(hopCount, 2)
        XCTAssertEqual(resolvedEp1.url.absoluteString, "https://stream.resolved-final.com/episodes/s1e1.m3u8")
        XCTAssertEqual(resolvedEp1.format, .hls)
        XCTAssertEqual(resolvedEp1.quality, "1080p")
        XCTAssertEqual(resolvedEp1.headers["X-Custom-Auth"], "SecretToken789")
        
        // Step 5: Subtitle Parsing (.srt with HTML tag cleanup)
        let srtSub = ep1Source.subtitles![0]
        XCTAssertEqual(srtSub.format, .srt)
        let cues = subtitleParser.parseSRT(content: sampleSRTContent)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].text, "Pilot Episode")
        XCTAssertEqual(cues[1].text, "Chemistry is the study of change.")
        
        // Step 6: Multi-Episode Watch History & Resume Logic
        // Episode 1: watched 2900s out of 3000s (>96% -> completed -> resume at 0)
        storage.updateHistory(
            mediaItemId: seriesDetail.id,
            title: "\(seriesDetail.displayName) - S01E01",
            posterUrl: seriesDetail.posterUrl,
            itemType: "series",
            season: episode1.season,
            episode: episode1.episode,
            position: 2900.0,
            duration: 3000.0
        )
        
        let ep1Resume = storage.getResumeTimestamp(for: seriesDetail.id, episodeKey: "_s1e1")
        XCTAssertEqual(ep1Resume, 0.0, "Completed episode (>95%) must reset resume timestamp to 0")
        
        // Episode 2: watched 600s out of 3000s (20% -> resume at 600s)
        storage.updateHistory(
            mediaItemId: seriesDetail.id,
            title: "\(seriesDetail.displayName) - S01E02",
            posterUrl: seriesDetail.posterUrl,
            itemType: "series",
            season: episode2.season,
            episode: episode2.episode,
            position: 600.0,
            duration: 3000.0
        )
        
        let ep2Resume = storage.getResumeTimestamp(for: seriesDetail.id, episodeKey: "_s1e2")
        XCTAssertEqual(ep2Resume, 600.0, "Partially watched episode (<95%) must return current timestamp")
        
        // Verify database holds both history records
        XCTAssertEqual(storage.watchHistory.count, 2)
    }
    
    // MARK: - 3. End-to-End ViewModel Integration: CatalogViewModel & DetailViewModel
    func testE2EViewModelIntegration() async throws {
        let catalogMoviesJSON = """
        {
            "items": [
                {
                    "id": "matrix_1",
                    "type": "movie",
                    "name": "The Matrix",
                    "year": 1999,
                    "images": { "poster": "https://img.com/matrix.jpg" }
                }
            ],
            "nextCursor": null
        }
        """
        
        let matrixSourcesJSON = """
        [
            {
                "id": "src_matrix_direct",
                "type": "url",
                "url": "https://cdn.example.com/matrix/master.m3u8",
                "quality": "4K",
                "format": "hls",
                "headers": { "Referer": "https://matrix.org" }
            }
        ]
        """
        
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                return (HTTPURLResponse(url: URL(string: "about:blank")!, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data())
            }
            if url.path == "/api/mediahubmx-catalog.json" {
                let data = catalogMoviesJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            if url.path == "/api/mediahubmx-source.json" {
                let data = matrixSourcesJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        // 1. CatalogViewModel loads items
        let catalogVM = CatalogViewModel(
            addonEndpoint: "https://demo-addon.example/api",
            catalogId: "movies_sci_fi",
            catalogName: "Sci-Fi Movies",
            client: client
        )
        
        await catalogVM.loadCatalog(reset: true)
        XCTAssertEqual(catalogVM.items.count, 1)
        let matrixItem = catalogVM.items[0]
        XCTAssertEqual(matrixItem.displayName, "The Matrix")
        
        // 2. Pass item to DetailViewModel and fetch sources
        let manifest = AddonManifest(id: "demo-addon.example", name: "Demo", version: "1.0.0", endpoints: ["https://demo-addon.example/api"])
        addonManager.activeAddons = [ActiveAddon(manifest: manifest, endpoint: "https://demo-addon.example/api", isEnabled: true)]
        
        let detailVM = DetailViewModel(
            item: matrixItem,
            client: client,
            storage: storage,
            addonManager: addonManager
        )
        
        await detailVM.fetchSources()
        XCTAssertEqual(detailVM.availableSources.count, 1)
        let directSource = detailVM.availableSources[0]
        XCTAssertEqual(directSource.quality, "4K")
        
        // 3. Resolve stream via DetailViewModel
        let (streamUrl, headers) = try await detailVM.resolveAndGetStreamUrl(source: directSource)
        XCTAssertEqual(streamUrl.absoluteString, "https://cdn.example.com/matrix/master.m3u8")
        XCTAssertEqual(headers?["Referer"], "https://matrix.org")
        
        // 4. Toggle Favorite via DetailViewModel
        XCTAssertFalse(detailVM.isFavorite)
        detailVM.toggleFavorite()
        XCTAssertTrue(detailVM.isFavorite)
        XCTAssertTrue(storage.isFavorite(mediaItemId: matrixItem.id))
    }
    
    // MARK: - 4. Probing Fallback Strategies: mediahubmx.json -> mediaurl.json -> POST /addon
    func testAddonDetectionProbeFallbackChain() async throws {
        let baseUrl = "https://fallback-addon.net"
        
        // 1. Test fallback from mediahubmx.json (404) to mediaurl.json (200)
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/mediahubmx.json" {
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            if request.url?.path == "/mediaurl.json" {
                let data = MockAddonData.sampleManifestJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        let (manifest1, _) = try await detector.detect(from: baseUrl)
        XCTAssertEqual(manifest1.id, "demo-addon.example")
        
        // 2. Test fallback from mediahubmx (404) & mediaurl (404) to POST action="addon"
        MockURLProtocol.requestHandler = { request in
            // The manifest GET probe misses; discovery then falls back to POSTing the
            // `addon` action at the same URL, which is where the manifest comes from.
            if request.url?.path == "/mediahubmx.json" && request.httpMethod == "POST" {
                let data = MockAddonData.sampleManifestJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            if request.url?.path == "/mediahubmx.json" || request.url?.path == "/mediaurl.json" {
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        let (manifest2, _) = try await detector.detect(from: baseUrl)
        XCTAssertEqual(manifest2.id, "demo-addon.example")
    }
    
    // MARK: - 5. Live TV / IPTV E2E Channel Streaming Workflow
    func testLiveTVE2EWorkflow() async throws {
        let iptvCatalogJSON = """
        {
            "items": [
                {
                    "id": "channel_das_erste",
                    "type": "iptv",
                    "name": "Das Erste HD",
                    "url": "https://mcdn.daserste.de/live/hls/de/master.m3u8",
                    "logo": "https://img.example.com/ard.png",
                    "group": "Germany",
                    "country": "DE"
                },
                {
                    "id": "channel_zdf",
                    "type": "iptv",
                    "name": "ZDF HD",
                    "url": "https://zdf-hls-15.akamaized.net/hls/live/2004274/de/master.m3u8",
                    "group": "Germany",
                    "country": "DE"
                }
            ],
            "nextCursor": null
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/mediahubmx-catalog.json" && request.httpMethod == "POST" {
                let data = iptvCatalogJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        // 1. Fetch IPTV catalog
        let response = try await client.fetchCatalog(endpoint: "https://demo-addon.example/api", catalogId: "iptv_germany")
        XCTAssertEqual(response.items.count, 2)
        
        let channel1 = response.items[0]
        XCTAssertTrue(channel1.isIPTV)
        XCTAssertEqual(channel1.displayName, "Das Erste HD")
        XCTAssertEqual(channel1.url, "https://mcdn.daserste.de/live/hls/de/master.m3u8")
        
        // 2. Resolve direct IPTV stream source
        let source = MediaSource(
            url: channel1.url!,
            name: channel1.name,
            quality: "1080p",
            format: "hls",
            headers: ["User-Agent": "Demo/2.0", "Referer": "https://demo-addon.example"]
        )
        
        let resolvedLiveStream = try await resolver.resolve(source: source)
        XCTAssertEqual(resolvedLiveStream.url.absoluteString, "https://mcdn.daserste.de/live/hls/de/master.m3u8")
        XCTAssertEqual(resolvedLiveStream.format, .hls)
        XCTAssertEqual(resolvedLiveStream.headers["Referer"], "https://demo-addon.example")
        XCTAssertEqual(resolvedLiveStream.headers["User-Agent"], "Demo/2.0")
        
        // 3. Mark channel as recent search / history
        storage.addSearchQuery(channel1.displayName)
        XCTAssertEqual(storage.searchHistory.first, "Das Erste HD")
    }
    
    // MARK: - 6. Multi-Addon Aggregation & Universal Search
    func testMultiAddonDashboardsAndUniversalSearch() async throws {
        let manifestAddon1 = AddonManifest(
            id: "addon.movies",
            name: "Movies Hub",
            catalogs: [
                Catalog(id: "popular_movies", name: "Popular Movies", features: CatalogFeatures(search: CatalogSearchFeature(enabled: true)), kind: "vod")
            ]
        )
        let manifestAddon2 = AddonManifest(
            id: "addon.series",
            name: "Series Hub",
            catalogs: [
                Catalog(id: "popular_series", name: "Popular Series", features: CatalogFeatures(search: CatalogSearchFeature(enabled: true)), kind: "vod")
            ]
        )
        
        addonManager.activeAddons = [
            ActiveAddon(manifest: manifestAddon1, endpoint: "https://movies.hub/api", isEnabled: true),
            ActiveAddon(manifest: manifestAddon2, endpoint: "https://series.hub/api", isEnabled: true)
        ]
        
        // Dashboards aggregation
        let dashboards = await addonManager.fetchAllDashboards()
        XCTAssertEqual(dashboards.count, 2)
        XCTAssertEqual(dashboards[0].dashboard.id, "popular_movies")
        XCTAssertEqual(dashboards[1].dashboard.id, "popular_series")
        
        // Universal search setup
        let searchMovieResultJSON = """
        {
            "items": [
                { "id": "search_m1", "type": "movie", "name": "Batman Begins" }
            ]
        }
        """
        let searchSeriesResultJSON = """
        {
            "items": [
                { "id": "search_s1", "type": "series", "name": "Batman The Animated Series" }
            ]
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                return (HTTPURLResponse(url: URL(string: "about:blank")!, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data())
            }
            if url.host == "movies.hub" {
                let data = searchMovieResultJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            if url.host == "series.hub" {
                let data = searchSeriesResultJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        let searchResults = await addonManager.searchAll(query: "Batman")
        XCTAssertEqual(searchResults.count, 2)
        let titles = Set(searchResults.map { $0.displayName })
        XCTAssertTrue(titles.contains("Batman Begins"))
        XCTAssertTrue(titles.contains("Batman The Animated Series"))
    }
    
    // MARK: - 7. Adversarial & Edge Case Tests: Network Errors, 500 Codes, Malformed Subtitles & Recursive Depth
    func testAdversarialEdgeCases() async throws {
        // Edge Case A: Server 500 error during catalog loading
        MockURLProtocol.requestHandler = { request in
            return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, "Internal Server Error".data(using: .utf8)!)
        }
        
        do {
            _ = try await client.fetchCatalog(endpoint: "https://broken.server/api", catalogId: "any")
            XCTFail("Should throw HTTP error on status code 500")
        } catch let error as MediaHubError {
            if case .httpError(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 500)
            } else {
                XCTFail("Expected httpError but got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Edge Case B: Resolver infinite loop reaches maxResolveDepth (5 hops) without crashing
        let loopingSource = MediaSource(
            customId: "src_infinite",
            type: "resolver",
            url: "https://gateway.example.com/loop_start"
        )
        
        var hopCount = 0
        MockURLProtocol.requestHandler = { request in
            hopCount += 1
            let loopJSON = """
            {
                "url": "https://gateway.example.com/loop_hop_\(hopCount)",
                "resolveAgain": true
            }
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, loopJSON.data(using: .utf8)!)
        }
        
        let finalResolved = try await resolver.resolve(source: loopingSource, addonEndpoint: "https://gateway.example.com")
        XCTAssertEqual(hopCount, 5, "StreamResolver should safely stop at maxResolveDepth = 5")
        XCTAssertTrue(finalResolved.url.absoluteString.contains("loop_hop_5"))
        
        // Edge Case C: Completely malformed / empty subtitle content parses safely into 0 cues
        let garbageSubtitle = "%%% SOME NON-SUBTITLE GARBAGE TEXT WITH NO TIMESTAMPS %%%"
        let emptyCues = subtitleParser.parse(content: garbageSubtitle)
        XCTAssertEqual(emptyCues.count, 0)
        
        // Edge Case D: Subtitle with mixed line endings (\r\n and \r) and messy formatting
        let messySRT = "1\r00:00:01,000 --> 00:00:02,000\rLine 1\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nLine 2\r\n"
        let messyCues = subtitleParser.parseSRT(content: messySRT)
        XCTAssertEqual(messyCues.count, 2)
        XCTAssertEqual(messyCues[0].text, "Line 1")
        XCTAssertEqual(messyCues[1].text, "Line 2")
    }
    
    // MARK: - 8. Cross-Instance SQLite Database Persistence Verification
    func testSQLiteDatabaseCrossInstancePersistence() async throws {
        // 1. Save data through storage instance A
        let addon = SavedAddon(id: "test.hub", url: "https://test.hub/api", name: "Test Addon", isEnabled: true)
        storage.saveAddon(addon)
        
        let movie = MediaItem(customId: "fav_101", type: "movie", name: "Dune", images: ItemImages(poster: "https://img.com/dune.jpg"))
        storage.toggleFavorite(mediaItem: movie)
        
        storage.updateHistory(mediaItemId: "fav_101", title: "Dune", posterUrl: "https://img.com/dune.jpg", itemType: "movie", position: 1500, duration: 9000)
        storage.addSearchQuery("Sci-Fi")
        
        // 2. Instantiate a second storage instance B on the same DatabaseManager
        let secondaryStorage = StorageService(databaseManager: db)
        
        // Verify all data survived and was reloaded identically
        XCTAssertEqual(secondaryStorage.savedAddons.count, 1)
        XCTAssertEqual(secondaryStorage.savedAddons[0].name, "Test Addon")
        XCTAssertEqual(secondaryStorage.favorites.count, 1)
        XCTAssertEqual(secondaryStorage.favorites[0].title, "Dune")
        XCTAssertEqual(secondaryStorage.watchHistory.count, 1)
        XCTAssertEqual(secondaryStorage.getResumeTimestamp(for: "fav_101"), 1500)
        XCTAssertEqual(secondaryStorage.searchHistory.first, "Sci-Fi")
    }
}
