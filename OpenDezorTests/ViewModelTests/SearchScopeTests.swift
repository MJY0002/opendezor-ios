import XCTest
@testable import OpenDezor

final class SearchScopeTests: XCTestCase {
    func testClassifiesByProtocolType() {
        XCTAssertEqual(SearchScope.classify(MediaItem(customId: "a", type: "movie", name: "A")), .movies)
        XCTAssertEqual(SearchScope.classify(MediaItem(customId: "b", type: "series", name: "B")), .series)
        XCTAssertEqual(SearchScope.classify(MediaItem(customId: "c", type: "iptv", name: "C")), .live)
        XCTAssertEqual(SearchScope.classify(MediaItem(customId: "d", type: "channel", name: "D")), .live)
        XCTAssertEqual(SearchScope.classify(MediaItem(customId: "e", type: "directory", name: "E")), .other)
        XCTAssertEqual(SearchScope.classify(MediaItem(customId: "f", type: nil, name: "F")), .other)
    }
}
