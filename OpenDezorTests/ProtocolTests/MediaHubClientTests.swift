import XCTest
@testable import OpenDezor

final class MediaHubClientTests: XCTestCase {
    
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
    
    // MARK: - Fetch Manifest Tests
    func testFetchManifestSuccess() async throws {
        let manifestUrl = "https://demo-addon.example/mediahubmx.json"
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let data = MockAddonData.sampleManifestJSON.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        
        let manifest = try await client.fetchManifest(from: manifestUrl)
        XCTAssertEqual(manifest.id, "demo-addon.example")
        XCTAssertEqual(manifest.version, "1.4.2")
    }
    
    // MARK: - Fetch Catalog Action
    func testFetchCatalogWithAllFiltersAndCursor() async throws {
        let endpoint = "https://demo-addon.example/api"
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/mediahubmx-catalog.json")
            
            // Validate JSON body
            if let bodyData = request.extractedBodyData,
               let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                XCTAssertEqual(json["catalogId"] as? String, "movies_popular")
                XCTAssertEqual(json["search"] as? String, "Batman")
                XCTAssertEqual(json["sort"] as? String, "trending")
                XCTAssertEqual(json["cursor"] as? String, "token_123")
                XCTAssertEqual(json["language"] as? String, "de")
                XCTAssertEqual(json["region"] as? String, "DE")
            }
            
            let data = MockAddonData.sampleCatalogMoviesResponseJSON.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        
        let response = try await client.fetchCatalog(
            endpoint: endpoint,
            catalogId: "movies_popular",
            search: "Batman",
            sort: "trending",
            filter: ["genre": "action"],
            cursor: "token_123",
            adult: false
        )
        
        XCTAssertEqual(response.items.count, 2)
        XCTAssertEqual(response.nextCursor?.stringValue, "page_2_cursor_token")
    }
    
    // MARK: - Fetch Item Detail Action
    func testFetchItemDetail() async throws {
        let endpoint = "https://demo-addon.example/api"
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/mediahubmx-item.json")
            
            let data = MockAddonData.sampleItemDetailSeriesResponseJSON.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        
        let item = try await client.fetchItemDetail(
            endpoint: endpoint,
            itemType: "series",
            ids: ["tmdb_id": "1396"],
            name: "Breaking Bad"
        )
        
        XCTAssertEqual(item.id, "series_201")
        XCTAssertEqual(item.type, "series")
        XCTAssertEqual(item.episodes?.count, 2)
    }
    
    // MARK: - Fetch Sources (Movie & Episode)
    func testFetchSourcesMovie() async throws {
        let endpoint = "https://demo-addon.example/api"
        let movie = MediaItem(customId: "m1", type: "movie", name: "Inception")
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/mediahubmx-source.json")
            
            let data = MockAddonData.sampleSourcesResponseJSON.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        
        let sources = try await client.fetchSources(endpoint: endpoint, item: movie)
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(sources[0].quality, "1080p")
        XCTAssertEqual(sources[0].subtitles?.count, 2)
    }
    
    func testFetchSourcesSingleObjectFallback() async throws {
        let endpoint = "https://demo-addon.example/api"
        let movie = MediaItem(customId: "m1", type: "movie", name: "Inception")
        
        // Single MediaSource object JSON instead of array
        let singleSourceJSON = """
        {
            "id": "single_src",
            "url": "https://cdn.example.com/single.m3u8",
            "quality": "720p",
            "format": "hls"
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            let data = singleSourceJSON.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        
        let sources = try await client.fetchSources(endpoint: endpoint, item: movie)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0].id, "single_src")
        XCTAssertEqual(sources[0].quality, "720p")
    }
    
    // MARK: - Resolve Source Action
    func testResolveSourceSuccess() async throws {
        let endpoint = "https://demo-addon.example/api"
        let sourceUrl = "https://gateway.example.com/resolve?id=xyz789"
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/mediahubmx-resolve.json")
            
            let data = MockAddonData.sampleResolvedUrlJSON.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        
        let resolved = try await client.resolveSource(endpoint: endpoint, sourceUrl: sourceUrl)
        XCTAssertEqual(resolved.url, "https://stream.resolved-host.com/live/index.m3u8")
        XCTAssertEqual(resolved.quality, "1080p")
        XCTAssertEqual(resolved.headers?["Authorization"], "Bearer sample_token_123")
    }
    
    // MARK: - HTTP Error & Decoding Error Handling
    func testHTTPErrorHandling() async {
        let endpoint = "https://demo-addon.example/api"
        
        MockURLProtocol.requestHandler = { request in
            let errorMsg = "Internal Server Error"
            let data = errorMsg.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, data)
        }
        
        do {
            _ = try await client.fetchCatalog(endpoint: endpoint, catalogId: "popular")
            XCTFail("Should throw httpError")
        } catch let error as MediaHubError {
            switch error {
            case .httpError(let statusCode, _):
                XCTAssertEqual(statusCode, 500)
            default:
                XCTFail("Expected httpError but got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testDecodingErrorHandling() async {
        let endpoint = "https://demo-addon.example/api"
        
        MockURLProtocol.requestHandler = { request in
            let corruptData = "{ invalid json content ...".data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, corruptData)
        }
        
        do {
            _ = try await client.fetchCatalog(endpoint: endpoint, catalogId: "popular")
            XCTFail("Should throw decodingError")
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

    // MARK: - Addon Tasks

    /// Some addons' resolve answers with a fetch task for the hoster page. The client has to
    /// fetch it and send a taskResponse; only the second answer carries the stream.
    func testResolveRunsFetchTaskAndSendsTaskResponse() async throws {
        var taskResponse: [String: Any]?
        var hosterRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.host == "hoster.test" {
                hosterRequest = request
                let headers = ["Content-Type": "text/html; charset=utf-8"]
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!,
                        Data("<html>player</html>".utf8))
            }
            let body = try JSONSerialization.jsonObject(with: request.extractedBodyData ?? Data()) as? [String: Any] ?? [:]
            let reply: String
            if body["kind"] as? String == "taskResponse" {
                taskResponse = body
                reply = #"{"url":"https://cdn.test/master.m3u8","headers":{"Referer":"https://hoster.test/"}}"#
            } else {
                reply = #"{"kind":"taskRequest","id":"t1","data":{"type":"fetch","url":"https://hoster.test/e/abc","params":{"method":"GET","headers":{"user-agent":"TaskUA/1"}}}}"#
            }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(reply.utf8))
        }

        let resolved = try await client.resolveSource(endpoint: "https://addon.test/mediahubmx.json",
                                                      sourceUrl: "https://hoster.test/e/abc")

        XCTAssertEqual(resolved.url, "https://cdn.test/master.m3u8")
        XCTAssertEqual(hosterRequest?.value(forHTTPHeaderField: "User-Agent"), "TaskUA/1")
        XCTAssertTrue(hosterRequest?.url?.query?.contains("_t=") ?? false)
        XCTAssertEqual(taskResponse?["id"] as? String, "t1")
        let data = taskResponse?["data"] as? [String: Any]
        XCTAssertEqual(data?["type"] as? String, "fetch")
        XCTAssertEqual(data?["status"] as? Int, 200)
        XCTAssertEqual(data?["text"] as? String, "<html>player</html>")
    }

    /// A task must not turn the app into a probe for the user's own network.
    func testFetchTaskToPrivateNetworkIsRefused() async throws {
        var taskResponse: [String: Any]?
        MockURLProtocol.requestHandler = { request in
            XCTAssertNotEqual(request.url?.host, "192.168.1.1", "the private address must never be fetched")
            let body = try JSONSerialization.jsonObject(with: request.extractedBodyData ?? Data()) as? [String: Any] ?? [:]
            let reply: String
            if body["kind"] as? String == "taskResponse" {
                taskResponse = body
                reply = "null"
            } else {
                reply = #"{"kind":"taskRequest","id":"t2","data":{"type":"fetch","url":"http://192.168.1.1/admin"}}"#
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(reply.utf8))
        }

        do {
            _ = try await client.resolveSource(endpoint: "https://addon.test/mediahubmx.json", sourceUrl: "https://x.test/")
            XCTFail("a null resolve must throw")
        } catch {}
        XCTAssertNotNil((taskResponse?["data"] as? [String: Any])?["error"])

        for host in ["localhost", "127.0.0.1", "10.0.0.8", "172.20.1.1", "192.168.0.1", "169.254.1.1", "::1", "fd00::1", "nas.local"] {
            XCTAssertTrue(MediaHubClient.isPrivateHost(host), host)
        }
        for host in ["voe.sx", "172.32.0.1", "8.8.8.8", "fdhoster.com"] {
            XCTAssertFalse(MediaHubClient.isPrivateHost(host), host)
        }
    }
}
