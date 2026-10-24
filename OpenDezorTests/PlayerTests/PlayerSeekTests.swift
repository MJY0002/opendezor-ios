import XCTest
@testable import OpenDezor

final class PlayerSeekTests: XCTestCase {
    func testDoubleTapSplitsAtHalfWidthInPortraitAndLandscape() {
        // iPhone 17 Pro: 402 pt wide in portrait, 874 pt in landscape.
        for width: CGFloat in [402, 874] {
            XCTAssertEqual(PlayerSeek.doubleTapSeconds(tapX: 10, width: width), -10)
            XCTAssertEqual(PlayerSeek.doubleTapSeconds(tapX: width / 2 - 1, width: width), -10)
            XCTAssertEqual(PlayerSeek.doubleTapSeconds(tapX: width / 2, width: width), 10)
            XCTAssertEqual(PlayerSeek.doubleTapSeconds(tapX: width - 10, width: width), 10)
        }
    }
}
