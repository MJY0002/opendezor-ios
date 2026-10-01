import XCTest
@testable import OpenDezor

final class AddonDetectionTests: XCTestCase {
    
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
    
    // MARK: - Direct JSON Manifest Discovery
    func testDirectJSONManifestDetection() async throws {
        let targetUrl = "https://example.com/addons/myaddon.json"
        
        MockURLProtocol.requestHandler = { request in
            guard request.url?.absoluteString == targetUrl else {
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            let data = MockAddonData.sampleManifestJSON.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        
        let (manifest, endpoint) = try await detector.detect(from: targetUrl)
        XCTAssertEqual(manifest.id, "demo-addon.example")
        // Custom endpoint from manifest.endpoints
        XCTAssertEqual(endpoint, "https://demo-addon.example/api")
    }
    
    // MARK: - Probing mediahubmx.json
    func testMediahubmxProbeSuccess() async throws {
        let inputUrl = "https://demo-addon.example"
        let expectedProbeUrl = "https://demo-addon.example/mediahubmx.json"
        
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString == expectedProbeUrl {
                let data = MockAddonData.sampleManifestJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        let (manifest, endpoint) = try await detector.detect(from: inputUrl)
        XCTAssertEqual(manifest.id, "demo-addon.example")
        XCTAssertEqual(endpoint, "https://demo-addon.example/api")
    }
    
    // MARK: - Probing mediaurl.json Fallback
    func testMediaurlJsonProbeFallback() async throws {
        let inputUrl = "https://other-addon.example"
        let expectedProbeUrl = "https://other-addon.example/mediaurl.json"
        
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString == "https://other-addon.example/mediahubmx.json" {
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            if request.url?.absoluteString == expectedProbeUrl {
                let data = MockAddonData.sampleManifestJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        let (manifest, endpoint) = try await detector.detect(from: inputUrl)
        XCTAssertEqual(manifest.id, "demo-addon.example")
        XCTAssertEqual(endpoint, "https://demo-addon.example/api")
    }
    
    // MARK: - Custom URL Schemes Normalization (mhub://, mediaurl://, dezor://, bare domain)
    func testCustomURLSchemes() async throws {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/mediahubmx.json" {
                let data = MockAddonData.sampleManifestJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        // 1. mhub://
        let (m1, _) = try await detector.detect(from: "mhub://demo-addon.example")
        XCTAssertEqual(m1.id, "demo-addon.example")
        
        // 2. mediaurl://
        let (m2, _) = try await detector.detect(from: "mediaurl://demo-addon.example")
        XCTAssertEqual(m2.id, "demo-addon.example")
        
        // 3. dezor://
        let (m3, _) = try await detector.detect(from: "dezor://demo-addon.example")
        XCTAssertEqual(m3.id, "demo-addon.example")
        
        // 4. Bare domain without scheme
        let (m4, _) = try await detector.detect(from: "demo-addon.example")
        XCTAssertEqual(m4.id, "demo-addon.example")
        
        // 5. Trailing slash
        let (m5, _) = try await detector.detect(from: "https://demo-addon.example/")
        XCTAssertEqual(m5.id, "demo-addon.example")
    }
    
    // MARK: - Fallback Action POST /addon
    func testFallbackActionAddon() async throws {
        let inputUrl = "https://custom-addon.org"
        
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
        
        let (manifest, _) = try await detector.detect(from: inputUrl)
        XCTAssertEqual(manifest.id, "demo-addon.example")
    }
    
    // MARK: - Discovery Failure
    func testDiscoveryFailureThrowsError() async {
        let inputUrl = "https://nonexistent-server.xyz"
        MockURLProtocol.requestHandler = { request in
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        do {
            _ = try await detector.detect(from: inputUrl)
            XCTFail("Should throw discoveryFailed error")
        } catch let error as MediaHubError {
            switch error {
            case .discoveryFailed:
                XCTAssertTrue(true)
            default:
                XCTFail("Expected discoveryFailed but got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    // MARK: - Relative Endpoints Resolution
    func testRelativeCustomEndpointsResolution() async throws {
        let inputUrl = "http://192.168.1.50:8080"
        
        let customManifestJSON = """
        {
            "id": "lan.addon",
            "name": "LAN MediaHub",
            "endpoints": ["custom/v1", "/root/api"]
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/mediahubmx.json" {
                let data = customManifestJSON.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        
        let (manifest, endpoint) = try await detector.detect(from: inputUrl)
        XCTAssertEqual(manifest.id, "lan.addon")
        XCTAssertEqual(endpoint, "http://192.168.1.50:8080/custom/v1")
    }
}
