import XCTest
@testable import OpenDezor

final class DebugLogTests: XCTestCase {
    func testSanitizerRemovesPersonalAndSecretData() {
        let clean = DebugLogSanitizer.clean
        XCTAssertFalse(clean("login katja@web.de failed").contains("katja"))
        XCTAssertFalse(clean("from 192.168.178.23 to 45.148.10.67").contains("192.168"))
        XCTAssertFalse(clean("fe80:0:0:0:1c2d:3e4f:5a6b:7c8d").contains("fe80"))
        let url = clean("GET https://user:pw@voe.sx/e/abc123?token=SECRETVALUE&expiry=1792806859365 failed")
        XCTAssertTrue(url.contains("voe.sx"))
        XCTAssertFalse(url.contains("SECRETVALUE"))
        XCTAssertFalse(url.contains("abc123"))
        XCTAssertFalse(url.contains("pw@"))
        XCTAssertFalse(clean("Authorization: Bearer abcdefghijklmnop").contains("abcdefghijklmnop"))
        XCTAssertFalse(clean("open /Users/mjy/Library/db.sqlite failed").contains("mjy"))
        XCTAssertFalse(clean("id QWERTYUIOPASDFGHJKLZXCVBNM123456").contains("QWERTY"))
    }

    func testSanitizerKeepsUsefulFacts() {
        XCTAssertEqual(DebugLogSanitizer.clean("Quelle 2 von 8: dood.to 1080p"), "Quelle 2 von 8: dood.to 1080p")
        XCTAssertEqual(DebugLogSanitizer.clean("Speedtest: 42.5 Mbit/s, Latenz 31 ms"), "Speedtest: 42.5 Mbit/s, Latenz 31 ms")
    }

    @MainActor
    func testLogIsOffByDefaultAndKeepsOnlyTheLastLines() async {
        let log = DebugLog.shared
        log.setEnabled(false)
        log.clear()
        DebugLog.log(.info, "T", "ignored while off")
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(log.entries.isEmpty || log.entries.allSatisfy { $0.category == "Log" })

        log.setEnabled(true)
        for i in 0..<(DebugLog.capacity + 50) { DebugLog.log(.info, "T", "line \(i)") }
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(log.entries.count, DebugLog.capacity)
        XCTAssertTrue(log.entries.last?.message.hasSuffix("\(DebugLog.capacity + 49)") ?? false)
        log.setEnabled(false)
        log.clear()
    }
}
