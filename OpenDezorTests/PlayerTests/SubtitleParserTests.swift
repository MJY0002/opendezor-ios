import XCTest
@testable import OpenDezor

final class SubtitleParserTests: XCTestCase {
    var parser: SubtitleParser!
    
    override func setUp() {
        super.setUp()
        parser = SubtitleParser()
    }
    
    override func tearDown() {
        parser = nil
        super.tearDown()
    }
    
    // MARK: - Timestamp Parsing Tests
    func testParseTimestampSRTFormat() {
        // 00:01:23,456 = 1 min (60s) + 23.456s = 83.456s
        let time = parser.parseTimestamp("00:01:23,456")
        XCTAssertNotNil(time)
        XCTAssertEqual(time!, 83.456, accuracy: 0.001)
        
        // 01:30:15,000 = 1.5h + 15s = 5400 + 15 = 5415.0s
        let time2 = parser.parseTimestamp("01:30:15,000")
        XCTAssertNotNil(time2)
        XCTAssertEqual(time2!, 5415.0, accuracy: 0.001)
    }
    
    func testParseTimestampVTTFormat() {
        // hh:mm:ss.ms
        let time1 = parser.parseTimestamp("00:02:10.500")
        XCTAssertNotNil(time1)
        XCTAssertEqual(time1!, 130.5, accuracy: 0.001)
        
        // mm:ss.ms (short form)
        let time2 = parser.parseTimestamp("05:20.125")
        XCTAssertNotNil(time2)
        XCTAssertEqual(time2!, 320.125, accuracy: 0.001)
    }
    
    func testParseTimestampInvalid() {
        let invalid = parser.parseTimestamp("invalid_time")
        XCTAssertNil(invalid)
    }
    
    // MARK: - SRT Parsing Tests
    func testParseSRTSingleCue() {
        let srtContent = """
        1
        00:00:01,000 --> 00:00:04,500
        Hallo und willkommen bei OpenDezor!
        """
        
        let cues = parser.parseSRT(content: srtContent)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].id, 1)
        XCTAssertEqual(cues[0].startTime, 1.0, accuracy: 0.001)
        XCTAssertEqual(cues[0].endTime, 4.5, accuracy: 0.001)
        XCTAssertEqual(cues[0].text, "Hallo und willkommen bei OpenDezor!")
    }
    
    func testParseSRTMultipleCuesWithFormattingTags() {
        let srtContent = """
        1
        00:00:01,500 --> 00:00:03,000
        <b>Erster Untertitel</b>
        
        2
        00:00:04,000 --> 00:00:07,200
        <i>Zweiter Untertitel</i>
        Zweite Zeile mit <font color="red">Farbe</font>
        
        3
        00:00:10,000 --> 00:00:12,000
        {\\an8}Dritter Untertitel oben
        """
        
        let cues = parser.parseSRT(content: srtContent)
        XCTAssertEqual(cues.count, 3)
        
        XCTAssertEqual(cues[0].text, "Erster Untertitel")
        XCTAssertEqual(cues[1].text, "Zweiter Untertitel\nZweite Zeile mit Farbe")
        XCTAssertEqual(cues[2].text, "Dritter Untertitel oben")
        XCTAssertEqual(cues[2].startTime, 10.0, accuracy: 0.001)
        XCTAssertEqual(cues[2].endTime, 12.0, accuracy: 0.001)
    }
    
    // MARK: - WebVTT Parsing Tests
    func testParseVTTWithHeadersAndSettings() {
        let vttContent = """
        WEBVTT - Demo WebVTT File
        
        NOTE This is a comment block that should be ignored
        
        STYLE
        ::cue { color: yellow; }
        
        1
        00:00:02.000 --> 00:00:05.500 line:0% position:50%
        <v John>Guten Tag allerseits!</v>
        
        2
        00:00:06.000 --> 00:00:09.000
        Schön, dass ihr da seid.
        """
        
        let cues = parser.parseVTT(content: vttContent)
        XCTAssertEqual(cues.count, 2)
        
        XCTAssertEqual(cues[0].startTime, 2.0, accuracy: 0.001)
        XCTAssertEqual(cues[0].endTime, 5.5, accuracy: 0.001)
        XCTAssertEqual(cues[0].text, "Guten Tag allerseits!")
        
        XCTAssertEqual(cues[1].startTime, 6.0, accuracy: 0.001)
        XCTAssertEqual(cues[1].endTime, 9.0, accuracy: 0.001)
        XCTAssertEqual(cues[1].text, "Schön, dass ihr da seid.")
    }
    
    // MARK: - Active Cue Query Tests
    func testActiveCueLookup() {
        let cues = [
            SubtitleCue(id: 1, startTime: 1.0, endTime: 3.0, text: "Cue 1"),
            SubtitleCue(id: 2, startTime: 5.0, endTime: 8.0, text: "Cue 2"),
            SubtitleCue(id: 3, startTime: 10.0, endTime: 12.0, text: "Cue 3")
        ]
        
        // Before first cue
        XCTAssertNil(parser.activeCue(in: cues, at: 0.5))
        
        // During cue 1
        let active1 = parser.activeCue(in: cues, at: 2.0)
        XCTAssertNotNil(active1)
        XCTAssertEqual(active1?.id, 1)
        XCTAssertEqual(active1?.text, "Cue 1")
        
        // Between cue 1 and 2
        XCTAssertNil(parser.activeCue(in: cues, at: 4.0))
        
        // During cue 2
        let active2 = parser.activeCue(in: cues, at: 6.5)
        XCTAssertNotNil(active2)
        XCTAssertEqual(active2?.id, 2)
        XCTAssertEqual(active2?.text, "Cue 2")
        
        // At exact boundary
        let active3 = parser.activeCue(in: cues, at: 10.0)
        XCTAssertNotNil(active3)
        XCTAssertEqual(active3?.id, 3)
        
        // After all cues
        XCTAssertNil(parser.activeCue(in: cues, at: 15.0))
    }
    
    // MARK: - HTML Tag Cleaning Tests
    func testCleanSubtitleText() {
        let input = "<b><i>Hello</i></b> <font color=\"#ff0000\">World</font> <c.yellow>Test</c> {\\an5}Special"
        let cleaned = parser.cleanSubtitleText(input)
        XCTAssertEqual(cleaned, "Hello World Test Special")
    }
}
