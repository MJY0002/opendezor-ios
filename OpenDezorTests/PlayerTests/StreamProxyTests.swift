import XCTest
@testable import OpenDezor

/// Films and series play from a loopback proxy that sends every request through the VPN.
/// These pin the part that decides whether anything could still bypass it: the path
/// round trip and the playlist rewrite.
final class StreamProxyTests: XCTestCase {

    func testPathRoundTripsUpstreamURL() throws {
        let upstream = URL(string: "https://cdn.test/hls/abc/index.m3u8?token=a+b/c==&x=1")!
        let path = StreamProxyPaths.path(streamId: "s1", upstream: upstream)
        XCTAssertTrue(path.hasSuffix("/index.m3u8"), "extension kept for AVPlayer's demuxer choice")
        let parsed = try XCTUnwrap(StreamProxyPaths.parse(path))
        XCTAssertEqual(parsed.streamId, "s1")
        XCTAssertEqual(parsed.upstream, upstream)
    }

    func testParseRejectsNonHTTPTargets() {
        let encoded = Data("file:///etc/passwd".utf8).base64EncodedString()
        XCTAssertNil(StreamProxyPaths.parse("/s1/\(encoded)/x"))
        XCTAssertNil(StreamProxyPaths.parse("/only-one-part"))
    }

    /// Every URI in the playlist — segments, variants, keys, maps, renditions — must point
    /// back at the proxy, or AVPlayer fetches it directly and outside the VPN.
    func testPlaylistRewriteLeavesNoDirectURI() {
        let playlist = """
        #EXTM3U
        #EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x1
        #EXT-X-MAP:URI="/init.mp4"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="de",URI="audio/de.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=800000
        720p/index.m3u8
        #EXTINF:6.0,
        https://other.test/seg1.ts
        """
        let base = URL(string: "https://cdn.test/hls/master.m3u8")!
        var mapped: [String] = []
        let rewritten = StreamProxyPaths.rewritePlaylist(playlist, base: base) { url in
            mapped.append(url.absoluteString)
            return "PROXY(\(url.absoluteString))"
        }

        XCTAssertEqual(mapped, [
            "https://cdn.test/hls/key.bin",
            "https://cdn.test/init.mp4",
            "https://cdn.test/hls/audio/de.m3u8",
            "https://cdn.test/hls/720p/index.m3u8",
            "https://other.test/seg1.ts"
        ])
        XCTAssertFalse(rewritten.contains("\"key.bin\""))
        XCTAssertTrue(rewritten.contains("#EXTINF:6.0,"))
        for line in rewritten.split(separator: "\n") where !line.hasPrefix("#") {
            XCTAssertTrue(line.hasPrefix("PROXY("), String(line))
        }
    }

    func testPlaylistDetection() {
        XCTAssertTrue(StreamProxyPaths.isPlaylist(contentType: "application/vnd.apple.mpegURL", url: URL(string: "https://x/a")!))
        XCTAssertTrue(StreamProxyPaths.isPlaylist(contentType: "text/plain", url: URL(string: "https://x/a.m3u8")!))
        XCTAssertFalse(StreamProxyPaths.isPlaylist(contentType: "video/mp4", url: URL(string: "https://x/a.mp4")!))
    }
}
