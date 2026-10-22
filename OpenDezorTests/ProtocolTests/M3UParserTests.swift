import XCTest
@testable import OpenDezor

final class M3UParserTests: XCTestCase {
    
    func testM3UParserWithEXTINFMetadata() {
        let content = """
        #EXTM3U
        #EXTINF:-1 tvg-id="ARD.de" tvg-name="Das Erste" tvg-logo="https://example.com/ard.png" group-title="Öffentlich-Rechtlich",Das Erste HD
        https://example.com/live/ard.m3u8
        #EXTINF:-1 tvg-id="ZDF.de" tvg-name="ZDF HD" tvg-logo="https://example.com/zdf.png" group-title="Öffentlich-Rechtlich",ZDF
        https://example.com/live/zdf.m3u8
        """
        
        let items = M3UParser.parse(content: content)
        XCTAssertEqual(items.count, 2)
        
        let item1 = items[0]
        XCTAssertEqual(item1.id, "ARD.de")
        XCTAssertEqual(item1.displayName, "Das Erste HD")
        XCTAssertEqual(item1.url, "https://example.com/live/ard.m3u8")
        XCTAssertEqual(item1.group, "Öffentlich-Rechtlich")
        XCTAssertEqual(item1.logo, "https://example.com/ard.png")
        
        let item2 = items[1]
        XCTAssertEqual(item2.id, "ZDF.de")
        XCTAssertEqual(item2.displayName, "ZDF")
        XCTAssertEqual(item2.url, "https://example.com/live/zdf.m3u8")
    }
    
    func testM3UParserFallbackChannelNames() {
        let content = """
        #EXTM3U
        #EXTINF:-1,Einfacher Sender
        http://example.com/stream1.m3u8
        #EXTINF:-1 tvg-name="Nur Tvg Name"
        http://example.com/stream2.m3u8
        """
        
        let items = M3UParser.parse(content: content)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].displayName, "Einfacher Sender")
        XCTAssertEqual(items[1].displayName, "Nur Tvg Name")
    }
    
    func testAppSettingsBiometrics() throws {
        var settings = AppSettings()
        XCTAssertFalse(settings.requireBiometrics)
        
        settings.requireBiometrics = true
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertTrue(decoded.requireBiometrics)
    }
    
    @MainActor
    func testPlayerSubtitleOffsetAndSleepTimer() {
        let player = PlayerService.shared
        player.subtitleOffset = 1.5
        XCTAssertEqual(player.subtitleOffset, 1.5)
        
        player.subtitleOffset = -2.0
        XCTAssertEqual(player.subtitleOffset, -2.0)
        
        player.setSleepTimer(minutes: 30)
        XCTAssertEqual(player.sleepTimerMinutesRemaining, 30)
        
        player.setSleepTimer(minutes: 0)
        XCTAssertNil(player.sleepTimerMinutesRemaining)
    }
}
final class M3UParserValidationTests: XCTestCase {
    func testNonPlaylistTextYieldsNoChannels() {
        XCTAssertTrue(M3UParser.parse(content: "https://example.invalid/list.m3u").isEmpty)
        XCTAssertTrue(M3UParser.parse(content: "<html>404</html>").isEmpty)
    }

    func testPlaylistWithNonStreamLineIsSkipped() {
        let content = "#EXTM3U\n#EXTINF:-1,Eins\nhttps://example.com/a.m3u8\n#EXTINF:-1,Zwei\nnot a url\n"
        XCTAssertEqual(M3UParser.parse(content: content).count, 1)
    }
}
