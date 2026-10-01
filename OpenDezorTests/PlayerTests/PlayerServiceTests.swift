import XCTest
@testable import OpenDezor

final class PlayerServiceTests: XCTestCase {
    
    @MainActor
    func testTrackOptions() {
        let audio = AudioTrackOption(id: "de_audio", displayName: "Deutsch [Dolby 5.1]", languageCode: "de")
        XCTAssertEqual(audio.id, "de_audio")
        XCTAssertEqual(audio.displayName, "Deutsch [Dolby 5.1]")
        XCTAssertEqual(audio.languageCode, "de")
        
        let sub = SubtitleOption(
            id: "en_sub",
            displayName: "Englisch",
            languageCode: "en",
            isExternal: true,
            externalUrl: URL(string: "https://example.com/subs/en.vtt")
        )
        XCTAssertEqual(sub.id, "en_sub")
        XCTAssertTrue(sub.isExternal)
        XCTAssertEqual(sub.externalUrl?.absoluteString, "https://example.com/subs/en.vtt")
    }
    
    @MainActor
    func testPlayerServiceStateReset() {
        let playerService = PlayerService()
        playerService.stopAndCleanup()
        
        XCTAssertFalse(playerService.isPlaying)
        XCTAssertFalse(playerService.isBuffering)
        XCTAssertEqual(playerService.currentTime, 0)
        XCTAssertEqual(playerService.duration, 0)
        XCTAssertNil(playerService.currentSubtitleCueText)
    }
}
