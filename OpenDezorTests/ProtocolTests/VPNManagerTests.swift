import XCTest
@testable import OpenDezor

/// The VPN no longer ships a hardcoded server list — everything comes from the `proxy`
/// object of a ping response, so these tests drive that path.
final class VPNManagerTests: XCTestCase {

    /// A locations tree shaped like the one dezor.net actually returns.
    private func sampleProxyConfig(method: String = "aes-256-gcm") -> DezorProxyConfig {
        let json = """
        {
          "dns": "1.1.1.1",
          "shadowsocks": { "method": "\(method)", "password": "secret", "port": 8388 },
          "locations": [
            {
              "type": "country", "name": "DE", "id": "de", "free": true,
              "children": [
                {
                  "type": "city", "name": "Frankfurt", "id": "de-fra", "free": true,
                  "children": [
                    { "type": "server", "name": "141.95.102.126", "id": "141.95.102.126",
                      "ip": "141.95.102.126", "speed": 1, "load": 0.10, "free": true, "children": [] }
                  ]
                }
              ]
            },
            {
              "type": "country", "name": "PL", "id": "pl", "free": true,
              "children": [
                {
                  "type": "city", "name": "Warsaw", "id": "pl-waw", "free": true,
                  "children": [
                    { "type": "server", "name": "146.59.116.19", "id": "146.59.116.19",
                      "ip": "146.59.116.19", "speed": 0.25, "load": 0.85, "free": true, "children": [] }
                  ]
                }
              ]
            }
          ]
        }
        """
        return try! JSONDecoder().decode(DezorProxyConfig.self, from: Data(json.utf8))
    }

    func testFlattenBuildsServersFromLocationTree() {
        let config = sampleProxyConfig()
        let servers = VPNManager.flatten(config.locations ?? [], port: 8388)

        XCTAssertEqual(servers.count, 2)
        let frankfurt = servers.first { $0.host == "141.95.102.126" }
        XCTAssertNotNil(frankfurt)
        XCTAssertEqual(frankfurt?.city, "Frankfurt")
        XCTAssertEqual(frankfurt?.country, "DE")
        XCTAssertEqual(frankfurt?.port, 8388)
        XCTAssertEqual(frankfurt?.load, 0.10)
        // Every Dezor server is reached through the local Shadowsocks listener.
        XCTAssertEqual(frankfurt?.proto, .socks5)
    }

    func testFlagDerivedFromCountryCode() {
        XCTAssertEqual(VPNManager.flag(for: "DE"), "🇩🇪")
        XCTAssertEqual(VPNManager.flag(for: "pl"), "🇵🇱")
        // Anything that is not a two-letter code falls back rather than emitting garbage.
        XCTAssertEqual(VPNManager.flag(for: "Germany"), "🌍")
    }

    @MainActor
    func testApplyProxyConfigPicksLowestLoadForAutomatic() {
        let vpn = VPNManager.shared
        vpn.applyProxyConfig(sampleProxyConfig())

        let ids = vpn.availableServers.map { $0.id }
        XCTAssertEqual(ids.first, "auto")
        XCTAssertTrue(ids.contains("custom"))
        XCTAssertTrue(ids.contains("141.95.102.126"))

        // Frankfurt has load 0.10 versus Warsaw's 0.85.
        let auto = vpn.availableServers.first { $0.id == "auto" }
        XCTAssertEqual(auto?.host, "141.95.102.126")
    }

    @MainActor
    func testUnsupportedCipherIsRejectedRatherThanGuessed() {
        let vpn = VPNManager.shared
        // BLAKE3-based Shadowsocks-2022 is outside what CryptoKit can do.
        vpn.applyProxyConfig(sampleProxyConfig(method: "2022-blake3-aes-256-gcm"))
        XCTAssertTrue(vpn.statusMessage.contains("2022-blake3-aes-256-gcm"))
    }

    @MainActor
    func testCustomProxyIsUsedDirectly() {
        let vpn = VPNManager.shared
        vpn.sessionFactory = { _ in MockSessionFactory.makeMockSession() }
        defer { vpn.setEnabled(false) }

        vpn.updateCustomProxy(host: "192.168.1.100", port: 1080, proto: .socks5)
        guard let custom = vpn.availableServers.first(where: { $0.id == "custom" }) else {
            XCTFail("Custom proxy entry missing")
            return
        }
        XCTAssertEqual(custom.host, "192.168.1.100")
        XCTAssertEqual(custom.port, 1080)
        XCTAssertEqual(custom.proto, .socks5)

        vpn.selectServer(custom)
        vpn.setEnabled(true)

        let config = URLSessionConfiguration.default
        vpn.applyToURLSessionConfiguration(config)
        // A user-supplied proxy bypasses Shadowsocks and is contacted directly.
        XCTAssertEqual(config.connectionProxyDictionary?["SOCKSProxy"] as? String, "192.168.1.100")
    }

    @MainActor
    func testDisabledVPNClearsProxyConfiguration() {
        let vpn = VPNManager.shared
        vpn.setEnabled(false)

        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = ["stale": true]
        vpn.applyToURLSessionConfiguration(config)
        XCTAssertNil(config.connectionProxyDictionary)
    }

    @MainActor
    func testNoPlaceholderServersRemain() {
        let vpn = VPNManager.shared
        // The old build shipped unresolvable *.proxy.opendezor.org hosts and reported
        // "connected" for them. Nothing may reintroduce a fake host.
        for server in vpn.availableServers {
            XCTAssertFalse(server.host.hasSuffix("opendezor.org"), "placeholder host: \(server.host)")
        }
    }
}
