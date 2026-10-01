import XCTest
@testable import OpenDezor

final class StreamResolverTests: XCTestCase {
    
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
    
    // MARK: - Direct Stream Resolution
    func testDirectHlsStreamResolution() async throws {
        let source = MediaSource(
            customId: "src_direct",
            type: "url",
            url: "https://cdn.example.com/live/stream.m3u8",
            name: "Direct HLS Stream",
            quality: "1080p",
            format: "hls",
            subtitles: [
                Subtitle(name: "Deutsch", language: "de", type: "vtt", url: "https://cdn.example.com/subs/de.vtt")
            ],
            headers: ["Referer": "https://source-site.com"]
        )
        
        let resolved = try await resolver.resolve(source: source)
        XCTAssertEqual(resolved.url.absoluteString, "https://cdn.example.com/live/stream.m3u8")
        XCTAssertEqual(resolved.format, StreamFormat.hls)
        XCTAssertEqual(resolved.quality, "1080p")
        XCTAssertEqual(resolved.headers["Referer"], "https://source-site.com")
        XCTAssertNotNil(resolved.headers["User-Agent"])
        XCTAssertEqual(resolved.subtitles.count, 1)
    }
    
    func testDirectMp4StreamResolution() async throws {
        let source = MediaSource(
            customId: "src_mp4",
            type: "url",
            url: "https://cdn.example.com/video/movie.mp4",
            quality: "720p",
            format: "mp4"
        )
        
        let resolved = try await resolver.resolve(source: source)
        XCTAssertEqual(resolved.url.absoluteString, "https://cdn.example.com/video/movie.mp4")
        XCTAssertEqual(resolved.format, StreamFormat.mp4)
    }
    
    // MARK: - Dynamic Gateway Resolution via Protocol Action
    func testDynamicGatewayResolution() async throws {
        let source = MediaSource(
            customId: "src_resolver",
            type: "resolver",
            url: "https://gateway.example.com/resolve?id=xyz789",
            name: "Gateway Source",
            quality: "720p",
            format: "hls"
        )
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/mediahubmx-resolve.json")
            
            let data = MockAddonData.sampleResolvedUrlJSON.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        
        let resolved = try await resolver.resolve(
            source: source,
            addonEndpoint: "https://gateway.example.com"
        )
        
        XCTAssertEqual(resolved.url.absoluteString, "https://stream.resolved-host.com/live/index.m3u8")
        XCTAssertEqual(resolved.format, StreamFormat.hls)
        XCTAssertEqual(resolved.headers["Authorization"], "Bearer sample_token_123")
        XCTAssertEqual(resolved.headers["Referer"], "https://gateway.example.com")
    }
    
    // MARK: - Recursive Multi-Hop Resolution
    func testRecursiveMultiHopResolution() async throws {
        let source = MediaSource(
            customId: "src_recursive",
            type: "resolver",
            url: "https://gateway.example.com/step1",
            name: "Recursive Stream"
        )
        
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            if requestCount == 1 {
                let data = MockAddonData.sampleRecursiveResolvedUrlJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            } else {
                let data = MockAddonData.sampleResolvedUrlJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
        }
        
        let resolved = try await resolver.resolve(
            source: source,
            addonEndpoint: "https://gateway.example.com"
        )
        
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(resolved.url.absoluteString, "https://stream.resolved-host.com/live/index.m3u8")
        XCTAssertEqual(resolved.format, StreamFormat.hls)
    }
}
