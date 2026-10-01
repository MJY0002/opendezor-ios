import XCTest
@testable import OpenDezor

// =============================================================================
// MARK: - 1. MODEL DESERIALIZATION ADVERSARIAL STRESS TESTS
// =============================================================================

final class ModelDeserializationStressTests: XCTestCase {
    
    // MARK: - TranslatedText Stress
    func testTranslatedText_ExtremeVariants() throws {
        // Empty string
        let emptyJson = "\"\"".data(using: .utf8)!
        let emptyText = try JSONDecoder().decode(TranslatedText.self, from: emptyJson)
        XCTAssertEqual(emptyText.value, "")
        
        // Dictionary with empty string values
        let dictEmptyJson = "{\"en\": \"\", \"de\": \"\"}".data(using: .utf8)!
        let dictEmptyText = try JSONDecoder().decode(TranslatedText.self, from: dictEmptyJson)
        XCTAssertEqual(dictEmptyText.value, "")
        
        // Unicode, Emoji, RTL, Newlines, and Quotes
        let rawUnicodeJson = "\"🚀 Dezor Stream & 🍿 العربية 简体中文\"".data(using: .utf8)!
        let unicodeText = try JSONDecoder().decode(TranslatedText.self, from: rawUnicodeJson)
        XCTAssertFalse(unicodeText.value.isEmpty)
        
        // Localized dictionary with unknown language keys
        let exoticDictJson = "{\"xx\": \"Exotic 1\", \"yy\": \"Exotic 2\"}".data(using: .utf8)!
        let exoticText = try JSONDecoder().decode(TranslatedText.self, from: exoticDictJson)
        XCTAssertTrue(exoticText.value == "Exotic 1" || exoticText.value == "Exotic 2")
        
        // Non-string fallback (e.g. integer in container)
        let intJson = "12345".data(using: .utf8)!
        let fallbackText = try JSONDecoder().decode(TranslatedText.self, from: intJson)
        XCTAssertEqual(fallbackText.value, "")
    }
    
    // MARK: - AnyCodableValue Stress
    func testAnyCodableValue_ExtremeVariants() throws {
        // Zero, Negative, Max Int
        let zeroJson = "0".data(using: .utf8)!
        let zeroVal = try JSONDecoder().decode(AnyCodableValue.self, from: zeroJson)
        XCTAssertEqual(zeroVal.stringValue, "0")
        
        let negJson = "-999999".data(using: .utf8)!
        let negVal = try JSONDecoder().decode(AnyCodableValue.self, from: negJson)
        XCTAssertEqual(negVal.stringValue, "-999999")
        
        // Float precision
        let floatJson = "0.0000001".data(using: .utf8)!
        let floatVal = try JSONDecoder().decode(AnyCodableValue.self, from: floatJson)
        XCTAssertNotNil(floatVal.stringValue)
        
        // Boolean values
        let falseJson = "false".data(using: .utf8)!
        let falseVal = try JSONDecoder().decode(AnyCodableValue.self, from: falseJson)
        XCTAssertEqual(falseVal.stringValue, "false")
        
        // Null value
        let nullJson = "null".data(using: .utf8)!
        let nullVal = try JSONDecoder().decode(AnyCodableValue.self, from: nullJson)
        XCTAssertNil(nullVal.stringValue)
        XCTAssertEqual(nullVal, .null)
        
        // Round-trip encoding and decoding
        let originalValues: [AnyCodableValue] = [
            .string("test_str"),
            .int(42),
            .double(12.34),
            .bool(true),
            .null
        ]
        
        for orig in originalValues {
            let encoded = try JSONEncoder().encode(orig)
            let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: encoded)
            XCTAssertEqual(orig, decoded)
        }
    }
    
    // MARK: - FilterValue Stress
    func testFilterValue_ExtremeVariants() throws {
        // Standard string filter
        let strJson = "\"Drama\"".data(using: .utf8)!
        let strFilter = try JSONDecoder().decode(FilterValue.self, from: strJson)
        XCTAssertEqual(strFilter.displayTitle, "Drama")
        XCTAssertEqual(strFilter.keyString, "Drama")
        
        // Object filter with localized value
        let objJson = """
        {
            "key": "action_genre",
            "value": {
                "en": "Action & Adventure",
                "de": "Action & Abenteuer"
            }
        }
        """.data(using: .utf8)!
        let objFilter = try JSONDecoder().decode(FilterValue.self, from: objJson)
        XCTAssertEqual(objFilter.keyString, "action_genre")
        XCTAssertTrue(objFilter.displayTitle.contains("Action"))
        
        // Empty / Malformed fallback
        let badJson = "123".data(using: .utf8)!
        let badFilter = try JSONDecoder().decode(FilterValue.self, from: badJson)
        XCTAssertEqual(badFilter.keyString, "")
        XCTAssertEqual(badFilter.displayTitle, "")
    }
    
    // MARK: - AddonManifest Minimal & Edge Cases
    func testAddonManifest_MinimalAndEdgeCaseJSON() throws {
        // Minimal manifest with only required fields
        let minimalJson = """
        {
            "id": "minimal.addon",
            "name": "Minimal Addon"
        }
        """.data(using: .utf8)!
        
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: minimalJson)
        XCTAssertEqual(manifest.id, "minimal.addon")
        XCTAssertEqual(manifest.displayName, "Minimal Addon")
        XCTAssertNil(manifest.version)
        XCTAssertNil(manifest.catalogs)
        XCTAssertNil(manifest.pages)
        XCTAssertNil(manifest.endpoints)
        XCTAssertNil(manifest.actions)
        XCTAssertNil(manifest.adult)
    }
    
    func testAddonManifest_DeeplyNestedAndHeterogeneousFlags() throws {
        let complexJson = """
        {
            "id": "complex.addon",
            "name": {
                "de": "Komplexes Addon",
                "en": "Complex Addon"
            },
            "version": "2.0.0-beta.1",
            "flags": {
                "requiresAuth": false,
                "maxConnections": 10,
                "timeout": 3.5,
                "tag": "experimental",
                "optionalField": null
            },
            "catalogs": [
                {
                    "id": "cat_empty",
                    "options": null,
                    "features": null
                },
                {
                    "id": "cat_full",
                    "name": "Vollständiger Katalog",
                    "kind": "vod",
                    "adult": true,
                    "options": {
                        "shape": "landscape",
                        "size": "large",
                        "displayName": false
                    },
                    "features": {
                        "search": { "enabled": false },
                        "sort": [
                            { "id": "date", "name": "Datum" },
                            { "id": "views", "name": { "en": "Views", "de": "Aufrufe" } }
                        ],
                        "filter": [
                            {
                                "id": "year",
                                "name": "Erscheinungsjahr",
                                "multiselect": true,
                                "values": ["2024", "2023", "2022", "2021"],
                                "defaultValue": "2024"
                            }
                        ]
                    }
                }
            ],
            "pages": [
                {
                    "id": "page_empty"
                },
                {
                    "id": "page_multi",
                    "name": "Dashboard Page",
                    "dashboards": [
                        { "id": "d1", "type": "movie", "catalogId": "cat_full" },
                        { "id": "d2", "type": "iptv", "catalogId": "cat_empty" },
                        { "type": "series", "name": "Trending Series" }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!
        
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: complexJson)
        XCTAssertEqual(manifest.id, "complex.addon")
        XCTAssertEqual(manifest.flags?["requiresAuth"], .bool(false))
        XCTAssertEqual(manifest.flags?["maxConnections"], .int(10))
        XCTAssertEqual(manifest.flags?["timeout"], .double(3.5))
        XCTAssertEqual(manifest.flags?["tag"], .string("experimental"))
        XCTAssertEqual(manifest.flags?["optionalField"], .null)
        
        XCTAssertEqual(manifest.catalogs?.count, 2)
        XCTAssertEqual(manifest.catalogs?[0].id, "cat_empty")
        XCTAssertEqual(manifest.catalogs?[1].features?.sort?.count, 2)
        XCTAssertEqual(manifest.catalogs?[1].features?.filter?[0].values?.count, 4)
        
        XCTAssertEqual(manifest.pages?.count, 2)
        let page2 = manifest.pages?[1]
        XCTAssertEqual(page2?.dashboards?.count, 3)
        // Dashboard item without explicit id should synthesize fallback from catalogId/name/UUID
        XCTAssertFalse(page2!.dashboards![2].id.isEmpty)
    }
    
    // MARK: - MediaItem Edge Cases & Fallback Identifiers
    func testMediaItem_MissingFieldsAndFallbackIDs() throws {
        // MediaItem with no id and no name (fallback UUID generation)
        let emptyItemJson = "{}".data(using: .utf8)!
        let item = try JSONDecoder().decode(MediaItem.self, from: emptyItemJson)
        XCTAssertFalse(item.id.isEmpty)
        // The placeholder is localized, so compare against the same lookup rather than
        // pinning the assertion to whichever language the test host happens to run in.
        XCTAssertEqual(item.displayName, L("Unbekannter Titel"))
        XCTAssertNil(item.posterUrl)
        XCTAssertNil(item.backdropUrl)
        XCTAssertFalse(item.isSeries)
        XCTAssertFalse(item.isIPTV)
        XCTAssertFalse(item.isDirectory)
        
        // Item with tmdb_id in ids dict
        let tmdbItemJson = """
        {
            "ids": { "tmdb_id": "999" }
        }
        """.data(using: .utf8)!
        let tmdbItem = try JSONDecoder().decode(MediaItem.self, from: tmdbItemJson)
        XCTAssertEqual(tmdbItem.id, "tmdb_999")
        
        // Item with imdb_id in ids dict
        let imdbItemJson = """
        {
            "ids": { "imdb_id": "tt1234567" }
        }
        """.data(using: .utf8)!
        let imdbItem = try JSONDecoder().decode(MediaItem.self, from: imdbItemJson)
        XCTAssertEqual(imdbItem.id, "imdb_tt1234567")
        
        // Item with custom id taking precedence
        let customItemJson = """
        {
            "id": "custom_override_id",
            "ids": { "tmdb_id": "999", "imdb_id": "tt123" }
        }
        """.data(using: .utf8)!
        let customItem = try JSONDecoder().decode(MediaItem.self, from: customItemJson)
        XCTAssertEqual(customItem.id, "custom_override_id")
    }
    
    func testMediaItem_ExtremeNumericAndTypeValues() throws {
        let extremeJson = """
        {
            "id": "item_extreme",
            "type": "iptv",
            "rating": 9.9999,
            "year": 2099,
            "runtime": 0,
            "url": "https://stream.iptv.com/live.m3u8",
            "logo": "https://img.com/logo.png",
            "images": {
                "poster": "https://img.com/p.jpg",
                "backdrop": "https://img.com/b.jpg"
            },
            "genres": [],
            "cast": [],
            "director": [],
            "episodes": []
        }
        """.data(using: .utf8)!
        
        let item = try JSONDecoder().decode(MediaItem.self, from: extremeJson)
        XCTAssertEqual(item.score, 9.9999)
        XCTAssertEqual(item.year, 2099)
        XCTAssertEqual(item.runtime, 0)
        XCTAssertTrue(item.isIPTV)
        XCTAssertEqual(item.posterUrl, "https://img.com/p.jpg")
    }
    
    // MARK: - StreamFormat Detection Edge Cases
    func testMediaSource_FormatDetectionEdgeCases() {
        // Query parameters after extension
        XCTAssertEqual(StreamFormat.detect(from: "https://example.com/stream.m3u8?token=xyz&exp=1234"), .hls)
        XCTAssertEqual(StreamFormat.detect(from: "https://example.com/video.mp4?auth=abc"), .mp4)
        XCTAssertEqual(StreamFormat.detect(from: "https://example.com/manifest.mpd?type=live"), .dash)
        XCTAssertEqual(StreamFormat.detect(from: "https://example.com/clip.webm?hd=1"), .webm)
        
        // Casing variations
        XCTAssertEqual(StreamFormat.detect(from: "HTTPS://EXAMPLE.COM/STREAM.M3U8"), .hls)
        XCTAssertEqual(StreamFormat.detect(from: "https://example.com/MOVIE.MP4"), .mp4)
        
        // Path indicator without extension
        XCTAssertEqual(StreamFormat.detect(from: "https://example.com/hls/live-channel-1"), .hls)
        
        // Explicit hint takes precedence
        XCTAssertEqual(StreamFormat.detect(from: "https://example.com/opaque-stream-id", hint: "HLS"), .hls)
        XCTAssertEqual(StreamFormat.detect(from: "https://example.com/opaque-stream-id", hint: "mp4"), .mp4)
        XCTAssertEqual(StreamFormat.detect(from: "https://example.com/opaque-stream-id", hint: "DASH"), .dash)
        
        // Unknown format
        XCTAssertEqual(StreamFormat.detect(from: "https://example.com/stream/unknown_format"), .unknown)
    }
    
    // MARK: - CatalogResponse Large & Diverse Items
    func testCatalogResponse_LargeAndMalformedCursors() throws {
        // Numeric nextCursor
        let intCursorJson = """
        {
            "items": [],
            "nextCursor": 42
        }
        """.data(using: .utf8)!
        let r1 = try JSONDecoder().decode(CatalogResponse.self, from: intCursorJson)
        XCTAssertEqual(r1.nextCursor?.stringValue, "42")
        
        // Null nextCursor (when key is null, Swift Decodable decodes optional field as nil)
        let nullCursorJson = """
        {
            "items": [],
            "nextCursor": null
        }
        """.data(using: .utf8)!
        let r2 = try JSONDecoder().decode(CatalogResponse.self, from: nullCursorJson)
        XCTAssertNil(r2.nextCursor)
        
        // Missing nextCursor
        let noCursorJson = "{\"items\": []}".data(using: .utf8)!
        let r3 = try JSONDecoder().decode(CatalogResponse.self, from: noCursorJson)
        XCTAssertNil(r3.nextCursor)
    }
}

// =============================================================================
// MARK: - 2. ADDON DETECTOR ADVERSARIAL STRESS TESTS
// =============================================================================

final class AddonDetectorStressTests: XCTestCase {
    
    private var mockSession: URLSession!
    private var client: MediaHubClient!
    private var detector: AddonDetector!
    
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        mockSession = MockSessionFactory.makeMockSession()
        client = MediaHubClient(session: mockSession)
        client.retryBaseDelay = 0  // Kein Backoff in Tests
        detector = AddonDetector(client: client)
    }
    
    override func tearDown() {
        MockURLProtocol.reset()
        mockSession = nil
        client = nil
        detector = nil
        super.tearDown()
    }
    
    // MARK: - Strange / Malformed URL Inputs
    func testAddonDetector_CustomSchemeCasingAndWhitespace() async throws {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/mediahubmx.json" {
                let data = MockAddonData.sampleManifestJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        // Scheme with leading/trailing whitespaces and mixed casing
        let (m1, _) = try await detector.detect(from: "   MHUB://demo-addon.example   \n")
        XCTAssertEqual(m1.id, "demo-addon.example")
        
        let (m2, _) = try await detector.detect(from: "  MEDIAURL://demo-addon.example\t")
        XCTAssertEqual(m2.id, "demo-addon.example")
        
        let (m3, _) = try await detector.detect(from: "  DEZOR://demo-addon.example  ")
        XCTAssertEqual(m3.id, "demo-addon.example")
    }
    
    func testAddonDetector_EdgeCaseDomainInputs() async throws {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/mediahubmx.json" {
                let data = MockAddonData.sampleManifestJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        // IP with custom port
        let (m1, _) = try await detector.detect(from: "192.168.1.100:9000")
        XCTAssertEqual(m1.id, "demo-addon.example")
        
        // Localhost with port
        let (m2, _) = try await detector.detect(from: "localhost:3000")
        XCTAssertEqual(m2.id, "demo-addon.example")
    }
    
    func testAddonDetector_ProbeChainFailureAndFallbacks() async throws {
        var probedPaths: [String] = []
        
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            probedPaths.append(path)
            
            // Fail all probe attempts except the 4th fallback: /mediaurl.json
            if path == "/mediaurl.json" {
                let data = MockAddonData.sampleManifestJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        let (manifest, _) = try await detector.detect(from: "https://myhub.net/addons/v1")
        XCTAssertEqual(manifest.id, "demo-addon.example")
        
        // Verify probe sequence probed nested paths before root paths
        XCTAssertTrue(probedPaths.contains("/addons/v1/mediahubmx.json"))
        XCTAssertTrue(probedPaths.contains("/addons/v1/mediaurl.json"))
        XCTAssertTrue(probedPaths.contains("/mediahubmx.json"))
        XCTAssertTrue(probedPaths.contains("/mediaurl.json"))
    }
    
    func testAddonDetector_NetworkFailuresAndCorruptData() async {
        // Server returning 500 server error on all endpoints
        MockURLProtocol.requestHandler = { request in
            return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, "Internal Server Error".data(using: .utf8)!)
        }
        
        do {
            _ = try await detector.detect(from: "https://broken-server.org")
            XCTFail("Should throw discoveryFailed when all probes return 500")
        } catch let error as MediaHubError {
            switch error {
            case .discoveryFailed:
                XCTAssertTrue(true)
            default:
                XCTFail("Expected discoveryFailed but got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// =============================================================================
// MARK: - 3. STREAM RESOLVER ADVERSARIAL STRESS TESTS
// =============================================================================

final class StreamResolverStressTests: XCTestCase {
    
    private var mockSession: URLSession!
    private var client: MediaHubClient!
    private var resolver: StreamResolver!
    
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        mockSession = MockSessionFactory.makeMockSession()
        client = MediaHubClient(session: mockSession)
        client.retryBaseDelay = 0  // Kein Backoff in Tests
        resolver = StreamResolver(client: client)
    }
    
    override func tearDown() {
        MockURLProtocol.reset()
        mockSession = nil
        client = nil
        resolver = nil
        super.tearDown()
    }
    
    // MARK: - Cyclical Redirects & Depth Limit
    func testStreamResolver_CyclicalLoopDepthLimit() async throws {
        // A malicious or misconfigured resolver returns resolveAgain: true endlessly
        resolver.maxResolveDepth = 5
        
        var invocationCount = 0
        MockURLProtocol.requestHandler = { request in
            invocationCount += 1
            let cyclicJson = """
            {
                "url": "https://gateway.example.com/loop_step_\(invocationCount)",
                "resolveAgain": true
            }
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cyclicJson)
        }
        
        let source = MediaSource(
            customId: "src_cyclic",
            type: "resolver",
            url: "https://gateway.example.com/loop_step_0"
        )
        
        let resolved = try await resolver.resolve(source: source, addonEndpoint: "https://gateway.example.com")
        
        // Must stop exactly at maxResolveDepth without infinite hanging or crashing
        XCTAssertEqual(invocationCount, 5)
        XCTAssertEqual(resolved.url.absoluteString, "https://gateway.example.com/loop_step_5")
    }
    
    // MARK: - Multi-Hop Header Accumulation and Overrides
    func testStreamResolver_MultiHopHeaderPreservationAndOverrides() async throws {
        var step = 0
        MockURLProtocol.requestHandler = { request in
            step += 1
            if step == 1 {
                let json = """
                {
                    "url": "https://gateway.example.com/step2",
                    "headers": {
                        "X-Custom-Step1": "Value1",
                        "Authorization": "Bearer initial_token"
                    },
                    "resolveAgain": true
                }
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            } else {
                let json = """
                {
                    "url": "https://cdn.example.com/final_video.m3u8",
                    "headers": {
                        "Authorization": "Bearer final_token",
                        "X-Custom-Step2": "Value2"
                    },
                    "resolveAgain": false
                }
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
        }
        
        let source = MediaSource(
            customId: "src_headers",
            type: "resolver",
            url: "https://gateway.example.com/step1",
            headers: ["Initial-Header": "Init"]
        )
        
        let resolved = try await resolver.resolve(source: source, addonEndpoint: "https://gateway.example.com")
        
        XCTAssertEqual(resolved.url.absoluteString, "https://cdn.example.com/final_video.m3u8")
        XCTAssertEqual(resolved.format, .hls)
        XCTAssertEqual(resolved.headers["Initial-Header"], "Init")
        XCTAssertEqual(resolved.headers["X-Custom-Step1"], "Value1")
        XCTAssertEqual(resolved.headers["X-Custom-Step2"], "Value2")
        // Step 2 override of Authorization header
        XCTAssertEqual(resolved.headers["Authorization"], "Bearer final_token")
        // User-Agent fallback presence
        XCTAssertNotNil(resolved.headers["User-Agent"])
    }
    
    // MARK: - Array vs Single Object Resolver Responses
    func testStreamResolver_ArrayResponseCompatibility() async throws {
        MockURLProtocol.requestHandler = { request in
            let arrayJson = """
            [
                {
                    "url": "https://cdn.example.com/primary_stream.m3u8",
                    "quality": "1080p",
                    "format": "hls",
                    "resolveAgain": false
                },
                {
                    "url": "https://cdn.example.com/backup_stream.mp4",
                    "quality": "720p",
                    "format": "mp4",
                    "resolveAgain": false
                }
            ]
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, arrayJson)
        }
        
        let source = MediaSource(
            customId: "src_array_res",
            type: "resolver",
            url: "https://resolver.example.com/get"
        )
        
        let resolved = try await resolver.resolve(source: source, addonEndpoint: "https://resolver.example.com")
        XCTAssertEqual(resolved.url.absoluteString, "https://cdn.example.com/primary_stream.m3u8")
        XCTAssertEqual(resolved.quality, "1080p")
        XCTAssertEqual(resolved.format, .hls)
    }
    
    // MARK: - Resolver Network and Invalid URL Errors
    func testStreamResolver_InvalidResolvedUrlThrowsError() async {
        MockURLProtocol.requestHandler = { request in
            let invalidUrlJson = """
            {
                "url": "",
                "resolveAgain": false
            }
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, invalidUrlJson)
        }
        
        let source = MediaSource(
            customId: "src_bad_url",
            type: "resolver",
            url: "https://gateway.example.com/resolve"
        )
        
        do {
            _ = try await resolver.resolve(source: source, addonEndpoint: "https://gateway.example.com")
            XCTFail("Should fail with resolveFailed for empty stream URL")
        } catch let error as MediaHubError {
            switch error {
            case .resolveFailed:
                XCTAssertTrue(true)
            default:
                XCTFail("Expected resolveFailed but got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// =============================================================================
// MARK: - 4. SUBTITLE PARSER ADVERSARIAL STRESS TESTS
// =============================================================================

final class SubtitleParserStressTests: XCTestCase {
    
    private var parser: SubtitleParser!
    
    override func setUp() {
        super.setUp()
        parser = SubtitleParser()
    }
    
    override func tearDown() {
        parser = nil
        super.tearDown()
    }
    
    // MARK: - Timestamp Parsing Stress
    func testSubtitleParser_TimestampVariations() {
        // High hour count (e.g. 100 hours)
        let time100h = parser.parseTimestamp("100:00:00,000")
        XCTAssertEqual(time100h, 360000.0)
        
        // Single digit minutes / seconds
        let shortVtt = parser.parseTimestamp("1:05.500")
        XCTAssertEqual(shortVtt, 65.5)
        
        // Zero time
        let zeroSrt = parser.parseTimestamp("00:00:00,000")
        XCTAssertEqual(zeroSrt, 0.0)
        
        let mmssZero = parser.parseTimestamp("00:00")
        XCTAssertEqual(mmssZero, 0.0)
        
        // Invalid non-numeric timestamps
        XCTAssertNil(parser.parseTimestamp("abc:def:ghi"))
        XCTAssertNil(parser.parseTimestamp(""))
        XCTAssertNil(parser.parseTimestamp("invalid_time_string"))
        XCTAssertNil(parser.parseTimestamp("12:xx:34"))
    }
    
    // MARK: - Heavy Formatting Tags & Special Characters
    func testSubtitleParser_HeavyFormattingAndSSATags() {
        let rawSrt = """
        1
        00:00:01,000 --> 00:00:04,000
        <font color="#00ff00" face="Arial"><b><i>{\\an8\\pos(192,10)\\c&H0000FF&}Top Subtitle</i></b></font>
        
        2
        00:00:05,000 --> 00:00:08,000
        <c.yellow.bg_blue><v Announcer>Breaking News!</v></c>
        Line 2 &amp; special chars: & [brackets] {braces} " '
        """
        
        let cues = parser.parseSRT(content: rawSrt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].text, "Top Subtitle")
        XCTAssertTrue(cues[1].text.contains("Breaking News!"))
        // Note: SSA tag regex strips anything within {...}, so {braces} is stripped
        XCTAssertTrue(cues[1].text.contains("Line 2 &amp; special chars: & [brackets]"))
    }
    
    // MARK: - Out-of-Order and Overlapping Cues
    func testSubtitleParser_OutOfOrderAndOverlappingCues() {
        let outOfOrderSrt = """
        3
        00:00:10,000 --> 00:00:15,000
        Late Cue
        
        1
        00:00:01,000 --> 00:00:05,000
        Early Cue
        
        2
        00:00:03,000 --> 00:00:07,000
        Overlapping Cue
        """
        
        let cues = parser.parseSRT(content: outOfOrderSrt)
        XCTAssertEqual(cues.count, 3)
        
        // Check activeCue query lookup during overlapping window (time = 4.0s matches both cue 1 and 2, returns first matching)
        let activeAt4 = parser.activeCue(in: cues, at: 4.0)
        XCTAssertNotNil(activeAt4)
        XCTAssertEqual(activeAt4?.text, "Early Cue")
        
        // Time at 6.0s (only cue 2 active)
        let activeAt6 = parser.activeCue(in: cues, at: 6.0)
        XCTAssertNotNil(activeAt6)
        XCTAssertEqual(activeAt6?.text, "Overlapping Cue")
        
        // Time at 12.0s (cue 3 active)
        let activeAt12 = parser.activeCue(in: cues, at: 12.0)
        XCTAssertNotNil(activeAt12)
        XCTAssertEqual(activeAt12?.text, "Late Cue")
    }
    
    // MARK: - Empty and Corrupt Inputs
    func testSubtitleParser_EmptyAndGarbageContent() {
        // Completely empty
        XCTAssertEqual(parser.parse(content: "").count, 0)
        
        // Only spaces and newlines
        XCTAssertEqual(parser.parse(content: "   \n\n\r\n   ").count, 0)
        
        // Header only WebVTT
        XCTAssertEqual(parser.parse(content: "WEBVTT\n\nNOTE comment\n").count, 0)
        
        // Corrupt SRT without timestamps
        let corruptSrt = """
        1
        Just a text without timestamp arrow
        
        2
        Another random block
        """
        XCTAssertEqual(parser.parseSRT(content: corruptSrt).count, 0)
    }
}

// =============================================================================
// MARK: - 5. DATABASE MANAGER & STORAGE CONCURRENCY STRESS TESTS
// =============================================================================

final class DatabaseConcurrencyStressTests: XCTestCase {
    
    private var db: DatabaseManager!
    
    override func setUp() {
        super.setUp()
        // Use fresh in-memory database for isolated concurrency testing
        db = DatabaseManager(inMemory: true)
    }
    
    override func tearDown() {
        db = nil
        super.tearDown()
    }
    
    // MARK: - Concurrent Multi-Threaded Access
    func testDatabase_ConcurrentMultiThreadedAccess() {
        let iterations = 100
        let expectation = XCTestExpectation(description: "Concurrent reads and writes complete without deadlocks or crashes")
        expectation.expectedFulfillmentCount = iterations * 4
        
        let writeAddonQueue = DispatchQueue(label: "test.write.addon", attributes: .concurrent)
        let writeHistoryQueue = DispatchQueue(label: "test.write.history", attributes: .concurrent)
        let writeFavQueue = DispatchQueue(label: "test.write.fav", attributes: .concurrent)
        let readQueue = DispatchQueue(label: "test.read.all", attributes: .concurrent)
        
        for i in 0..<iterations {
            // Task 1: Write Addons
            writeAddonQueue.async {
                let addon = SavedAddon(
                    id: "addon_\(i)",
                    url: "https://hub_\(i).org/api",
                    name: "Addon Name \(i)",
                    isEnabled: (i % 2 == 0)
                )
                self.db.saveAddon(addon)
                expectation.fulfill()
            }
            
            // Task 2: Write History
            writeHistoryQueue.async {
                let history = WatchHistoryItem(
                    mediaItemId: "item_\(i)",
                    title: "Title \(i)",
                    posterUrl: "https://img.org/\(i).jpg",
                    itemType: "movie",
                    lastPositionSeconds: Double(i * 10),
                    durationSeconds: 1000.0,
                    updatedAt: Date().addingTimeInterval(Double(i))
                )
                self.db.saveHistoryItem(history)
                expectation.fulfill()
            }
            
            // Task 3: Write Favorites
            writeFavQueue.async {
                let fav = FavoriteItem(
                    mediaItemId: "fav_\(i)",
                    title: "Favorite Title \(i)",
                    posterUrl: nil,
                    itemType: "movie",
                    addedAt: Date()
                )
                self.db.saveFavorite(fav)
                expectation.fulfill()
            }
            
            // Task 4: Read All Concurrently
            readQueue.async {
                _ = self.db.getAllAddons()
                _ = self.db.getWatchHistory()
                _ = self.db.getAllFavorites()
                _ = self.db.getSearchHistory()
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        // Assert all items were inserted safely
        let addons = db.getAllAddons()
        let favorites = db.getAllFavorites()
        let history = db.getWatchHistory()
        
        XCTAssertEqual(addons.count, iterations)
        XCTAssertEqual(favorites.count, iterations)
        // History is capped at LIMIT 100
        XCTAssertEqual(history.count, min(iterations, 100))
    }
    
    // MARK: - SQL Injection & Special Characters
    func testDatabase_SqlInjectionAndSpecialCharacters() {
        let maliciousTitle = "Movie'); DROP TABLE history; DROP TABLE addons; --"
        let maliciousQuery = "'; DELETE FROM search_history; --"
        let emojiUnicode = "🚀🍿 猎罪图鉴 \"Special Quotes\" & <xml> / 100%"
        
        // Save Malicious Addon
        let evilAddon = SavedAddon(
            id: "evil_addon_id",
            url: "https://evil.com/api",
            name: maliciousTitle,
            iconUrl: emojiUnicode,
            description: "Some 'quoted' description \\n \\r"
        )
        db.saveAddon(evilAddon)
        
        // Save Malicious History Item
        let evilHistory = WatchHistoryItem(
            mediaItemId: "evil_m1",
            title: maliciousTitle,
            posterUrl: emojiUnicode,
            lastPositionSeconds: 50.0,
            durationSeconds: 100.0
        )
        db.saveHistoryItem(evilHistory)
        
        // Save Malicious Search Query
        db.addSearchQuery(maliciousQuery)
        db.addSearchQuery(emojiUnicode)
        
        // Verify tables are still intact and data was safely escaped/bound
        let addons = db.getAllAddons()
        let history = db.getWatchHistory()
        let search = db.getSearchHistory()
        
        XCTAssertEqual(addons.count, 1)
        XCTAssertEqual(addons.first?.name, maliciousTitle)
        XCTAssertEqual(addons.first?.iconUrl, emojiUnicode)
        
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.title, maliciousTitle)
        XCTAssertEqual(history.first?.posterUrl, emojiUnicode)
        
        XCTAssertEqual(search.count, 2)
        XCTAssertTrue(search.contains(maliciousQuery))
        XCTAssertTrue(search.contains(emojiUnicode))
    }
    
    // MARK: - Watch History Progress & Resumption Math
    func testDatabase_WatchHistoryBoundaryAndResumeCalculations() {
        let h1 = WatchHistoryItem(
            mediaItemId: "m1",
            title: "Zero Duration",
            lastPositionSeconds: 100.0,
            durationSeconds: 0.0
        )
        XCTAssertEqual(h1.progressRatio, 0.0)
        XCTAssertFalse(h1.isCompleted)
        
        let h2 = WatchHistoryItem(
            mediaItemId: "m2",
            title: "Almost Done",
            lastPositionSeconds: 950.0,
            durationSeconds: 1000.0
        )
        XCTAssertEqual(h2.progressRatio, 0.95)
        XCTAssertTrue(h2.isCompleted) // >= 90%
        
        let h3 = WatchHistoryItem(
            mediaItemId: "m3",
            title: "Over Position Beyond Duration",
            lastPositionSeconds: 1200.0,
            durationSeconds: 1000.0
        )
        XCTAssertEqual(h3.progressRatio, 1.0) // clamped to 1.0
        XCTAssertTrue(h3.isCompleted)
    }
    
    // MARK: - Database Non-Existent Operations
    func testDatabase_NonExistentOperationsDoNotCrash() {
        // Deleting non-existent records
        db.deleteAddon(id: "non_existent_addon")
        db.deleteHistoryItem(id: "non_existent_history")
        db.deleteFavorite(mediaItemId: "non_existent_favorite")
        
        // Clearing empty database
        db.clearAllHistory()
        db.clearSearchHistory()
        
        XCTAssertEqual(db.getAllAddons().count, 0)
        XCTAssertEqual(db.getWatchHistory().count, 0)
        XCTAssertEqual(db.getAllFavorites().count, 0)
        XCTAssertEqual(db.getSearchHistory().count, 0)
    }
}

// =============================================================================
// MARK: - 6. MEDIAHUB CLIENT & PROTOCOL RESILIENCE STRESS TESTS
// =============================================================================

final class MediaHubClientStressTests: XCTestCase {
    
    private var mockSession: URLSession!
    private var client: MediaHubClient!
    
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        mockSession = MockSessionFactory.makeMockSession()
        client = MediaHubClient(session: mockSession)
        client.retryBaseDelay = 0  // Kein Backoff in Tests
    }
    
    override func tearDown() {
        MockURLProtocol.reset()
        mockSession = nil
        client = nil
        super.tearDown()
    }
    
    // MARK: - Single vs Array Polymorphic Fallbacks
    func testFetchSources_SingleObjectFallback() async throws {
        MockURLProtocol.requestHandler = { request in
            let singleSourceJson = """
            {
                "id": "single_src_1",
                "type": "url",
                "url": "https://cdn.example.com/single.m3u8",
                "quality": "1080p",
                "format": "hls"
            }
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, singleSourceJson)
        }
        
        let item = MediaItem(customId: "movie_item", type: "movie", name: "Test Item")
        let sources = try await client.fetchSources(endpoint: "https://hub.example.com/api", item: item)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.id, "single_src_1")
        XCTAssertEqual(sources.first?.format, "hls")
    }
    
    func testFetchSubtitles_SingleObjectFallback() async throws {
        MockURLProtocol.requestHandler = { request in
            let singleSubJson = """
            {
                "id": "single_sub_de",
                "name": "Deutsch",
                "language": "de",
                "type": "vtt",
                "url": "https://cdn.example.com/sub.vtt"
            }
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, singleSubJson)
        }
        
        let item = MediaItem(customId: "movie_item", type: "movie", name: "Test Item")
        let subs = try await client.fetchSubtitles(endpoint: "https://hub.example.com/api", item: item)
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs.first?.id, "single_sub_de")
        XCTAssertEqual(subs.first?.language, "de")
    }
    
    // MARK: - HTTP Error Status Codes
    func testExecuteAction_PropagatesHttpErrors() async {
        let errorCodes = [400, 401, 403, 404, 500, 502, 503]
        
        for code in errorCodes {
            MockURLProtocol.requestHandler = { request in
                let body = "Error details for HTTP \(code)".data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, body)
            }
            
            do {
                _ = try await client.fetchCatalog(endpoint: "https://hub.org/api", catalogId: "cat_1")
                XCTFail("Should throw httpError for HTTP \(code)")
            } catch let error as MediaHubError {
                switch error {
                case .httpError(let statusCode, let message):
                    XCTAssertEqual(statusCode, code)
                    XCTAssertTrue(message.contains("\(code)"))
                default:
                    XCTFail("Expected httpError but got \(error)")
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    // MARK: - Corrupt JSON Server Response
    func testExecuteAction_CorruptJSONThrowsDecodingError() async {
        MockURLProtocol.requestHandler = { request in
            let corruptHTML = "<html><head><title>502 Bad Gateway</title></head><body><h1>Server Error</h1></body></html>".data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, corruptHTML)
        }
        
        do {
            _ = try await client.fetchCatalog(endpoint: "https://hub.org/api", catalogId: "cat_1")
            XCTFail("Should throw decodingError for HTML in 200 OK")
        } catch let error as MediaHubError {
            switch error {
            case .decodingError:
                XCTAssertTrue(true)
            default:
                XCTFail("Expected decodingError but got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
