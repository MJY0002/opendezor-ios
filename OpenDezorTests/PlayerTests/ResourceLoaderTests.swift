import XCTest
@testable import OpenDezor

final class ResourceLoaderTests: XCTestCase {
    
    func testMakeCustomURLAndRestore() {
        let originalURL = URL(string: "https://example.com/live/stream.m3u8?token=12345")!
        
        let customURL = CustomResourceLoader.makeCustomURL(from: originalURL)
        XCTAssertEqual(customURL.scheme, CustomResourceLoader.customScheme)
        XCTAssertEqual(customURL.host, "example.com")
        XCTAssertEqual(customURL.path, "/live/stream.m3u8")
        XCTAssertEqual(customURL.query, "token=12345")
        
        let restoredURL = CustomResourceLoader.restoreOriginalURL(from: customURL)
        XCTAssertNotNil(restoredURL)
        XCTAssertEqual(restoredURL?.scheme, "https")
        XCTAssertEqual(restoredURL?.absoluteString, originalURL.absoluteString)
    }
    
    @MainActor
    func testResourceLoaderInitWithHeaders() {
        let headers = [
            "User-Agent": "OpenDezor/1.0",
            "Referer": "https://mediahubmx.com",
            "Authorization": "Bearer sample_token"
        ]
        
        let loader = CustomResourceLoader(headers: headers)
        XCTAssertNotNil(loader)
    }
}
