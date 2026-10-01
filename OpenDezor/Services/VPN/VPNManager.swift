import Foundation
import Combine
#if canImport(WebKit)
import WebKit
#endif
#if canImport(Network)
import Network
#endif

public enum ProxyProtocol: String, Codable, CaseIterable, Identifiable {
    case http = "HTTP"
    case https = "HTTPS"
    case socks5 = "SOCKS5"
    public var id: String { rawValue }
}

public struct VPNServerLocation: Identifiable, Equatable, Codable {
    public let id: String
    public let name: String
    public let city: String
    public let country: String
    public let flag: String
    public var host: String
    public var port: Int
    public var proto: ProxyProtocol
    public var isCustom: Bool
    /// Per-server Shadowsocks key, when the backend supplies one for this node.
    public var ssKey: String?
    /// Current server load, 0...1. Drives the "automatic" pick and the UI bars.
    public var load: Double?

    public init(
        id: String,
        name: String,
        city: String,
        country: String,
        flag: String,
        host: String,
        port: Int,
        proto: ProxyProtocol = .http,
        isCustom: Bool = false,
        ssKey: String? = nil,
        load: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.city = city
        self.country = country
        self.flag = flag
        self.host = host
        self.port = port
        self.proto = proto
        self.isCustom = isCustom
        self.ssKey = ssKey
        self.load = load
    }
}

/// Owns the in-app VPN.
///
/// Dezor's VPN is a Shadowsocks proxy, and the server list, cipher and password all come
/// from the `proxy` object of a ping response — nothing here is hardcoded. Because iOS
/// cannot spawn a helper binary, `LocalProxyServer` speaks
/// the same protocol in-process and exposes a loopback SOCKS5 port that WKWebView and the
/// app's URLSessions point at.
///
/// Scope is deliberately limited to traffic this app makes. A system-wide tunnel would
/// need a NetworkExtension entitlement, which ad-hoc sideloading cannot grant — and the
/// VPN is scoped to this app, not the system.
@MainActor
public class VPNManager: ObservableObject {
    public static let shared = VPNManager()

    @Published public var isEnabled: Bool = false
    @Published public var selectedServer: VPNServerLocation
    @Published public var availableServers: [VPNServerLocation] = []
    @Published public var isConnecting: Bool = false
    /// True only once the tunnel is up *and* a request through it has succeeded.
    /// Mirrored into `VPNRoute`, which is what playback and addon fetches route through:
    /// a proxy that is set up but not yet proven never carries a stream.
    @Published public var isConnected: Bool = false {
        didSet { VPNRoute.set(isConnected ? proxyDictionary() : nil) }
    }
    @Published public var currentPublicIP: String? = nil
    @Published public var proxyRevision: Int = 0
    @Published public var statusMessage: String = ""

    /// Set when the backend reports the free proxy budget is used up.
    @Published public var isProxyLocked: Bool = false

    #if canImport(Network)
    private let proxyServer = LocalProxyServer()
    #endif
    private var localPort: UInt16?
    private var shadowsocksMethod: SSMethod?
    private var shadowsocksPassword: String?
    private var shadowsocksPort: UInt16?
    private var budgetTask: Task<Void, Never>?
    /// Servers still to try for the current connection attempt, least loaded first.
    private var candidates: [VPNServerLocation] = []
    private var candidateIndex = 0

    /// Builds the session used to prove the tunnel carries traffic. Injectable so tests
    /// can verify without touching the network.
    var sessionFactory: (URLSessionConfiguration) -> URLSession = { URLSession(configuration: $0) }

    private init() {
        let settings = StorageService.shared.settings
        let custom = VPNManager.customServer(from: settings)
        // Real servers arrive with the first ping; until then only the user's own proxy
        // can be offered. No placeholder hosts.
        self.availableServers = [custom]
        self.selectedServer = custom
        // Connect on launch only when the user asked for it. Nothing is routed yet —
        // `effectiveProxy` stays nil until a listener is up — and `applyProxyConfig`
        // connects as soon as the first ping delivers the server list.
        self.isEnabled = settings.vpnAutoConnect
    }

    private static func customServer(from settings: AppSettings) -> VPNServerLocation {
        VPNServerLocation(
            id: "custom",
            name: L("Eigener Proxy"),
            city: L("Eigener Host"),
            country: "Custom",
            flag: "⚙️",
            host: settings.customProxyHost,
            port: settings.customProxyPort,
            proto: ProxyProtocol(rawValue: settings.customProxyType.uppercased()) ?? .http,
            isCustom: true
        )
    }

    // MARK: - Server list from the backend

    /// Folds the `proxy` object of a ping response into the server list.
    ///
    /// Idempotent and defensive: the backend only sends `proxy` on some pings, so a
    /// response without it must never wipe a good list.
    public func applyProxyConfig(_ config: DezorProxyConfig) {
        if let ss = config.shadowsocks,
           let method = ss.method.flatMap({ SSMethod(rawValue: $0) }),
           let password = ss.password,
           let port = ss.port,
           let port16 = UInt16(exactly: port) {
            shadowsocksMethod = method
            shadowsocksPassword = password
            shadowsocksPort = port16
        } else if let ss = config.shadowsocks, let raw = ss.method, SSMethod(rawValue: raw) == nil {
            // A cipher CryptoKit cannot service (e.g. the 2022-blake3 family). Better to
            // say so than to emit traffic that silently fails the tag check.
            shadowsocksMethod = nil
            statusMessage = L("Verschlüsselung nicht unterstützt") + ": \(raw)"
        }

        let servers = VPNManager.flatten(config.locations ?? [], port: Int(shadowsocksPort ?? 8388))
        guard !servers.isEmpty else { return }

        var list: [VPNServerLocation] = []
        if let best = servers.min(by: { ($0.load ?? 1) < ($1.load ?? 1) }) {
            list.append(VPNManager.automaticEntry(for: best))
        }
        list.append(contentsOf: servers)
        list.append(VPNManager.customServer(from: StorageService.shared.settings))
        availableServers = list

        // Keep the user's choice if it still exists, otherwise fall back to automatic.
        let wantedId = StorageService.shared.settings.selectedVpnServerId
        if let match = list.first(where: { $0.id == wantedId }) {
            selectedServer = match
        } else if let auto = list.first {
            selectedServer = auto
        }

        if isEnabled { restartTunnel() }
    }

    /// Walks the country -> city -> server tree into a flat list of server leaves.
    /// Pure, so it stays callable off the main actor.
    nonisolated static func flatten(_ nodes: [DezorProxyConfig.Node], port: Int) -> [VPNServerLocation] {
        var out: [VPNServerLocation] = []

        func walk(_ node: DezorProxyConfig.Node, country: String?, city: String?) {
            let type = node.type ?? ""
            if type == "server", let ip = node.ip, !ip.isEmpty {
                let countryName = country ?? node.name ?? ""
                out.append(
                    VPNServerLocation(
                        id: node.id ?? ip,
                        name: countryName,
                        city: city ?? "",
                        country: countryName,
                        flag: VPNManager.flag(for: countryName),
                        host: ip,
                        port: port,
                        proto: .socks5,
                        ssKey: node.ssKey,
                        load: node.load
                    )
                )
                return
            }
            let nextCountry = type == "country" ? (node.name ?? country) : country
            let nextCity = type == "city" ? (node.name ?? city) : city
            for child in node.children ?? [] {
                walk(child, country: nextCountry, city: nextCity)
            }
        }

        for node in nodes { walk(node, country: nil, city: nil) }
        return out
    }

    /// Turns a two-letter country code into its flag emoji.
    nonisolated static func flag(for code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.count == 2 else { return "🌍" }
        var result = ""
        for scalar in trimmed.unicodeScalars {
            guard let flagScalar = UnicodeScalar(127397 + scalar.value) else { return "🌍" }
            result.unicodeScalars.append(flagScalar)
        }
        return result
    }

    // MARK: - Connect / disconnect

    public func toggleVPN() {
        setEnabled(!isEnabled)
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled else {
            isEnabled = false
            teardownTunnel()
            persist(enabled: false)
            statusMessage = L("VPN getrennt")
            return
        }

        if isProxyLocked && DezorAuthService.shared.hasUnlimitedVPN == false {
            statusMessage = L("Freies VPN-Kontingent aufgebraucht")
            return
        }

        isEnabled = true
        persist(enabled: true)
        restartTunnel()
    }

    public func selectServer(_ server: VPNServerLocation) {
        selectedServer = server
        var settings = StorageService.shared.settings
        settings.selectedVpnServerId = server.id
        StorageService.shared.updateSettings(settings)

        guard isEnabled else { return }
        restartTunnel()
    }

    public func updateCustomProxy(host: String, port: Int, proto: ProxyProtocol) {
        var settings = StorageService.shared.settings
        settings.customProxyHost = host
        settings.customProxyPort = port
        settings.customProxyType = proto.rawValue
        StorageService.shared.updateSettings(settings)

        if let idx = availableServers.firstIndex(where: { $0.id == "custom" }) {
            availableServers[idx].host = host
            availableServers[idx].port = port
            availableServers[idx].proto = proto
            if selectedServer.id == "custom" {
                selectedServer = availableServers[idx]
                if isEnabled { restartTunnel() }
            }
        }
    }

    /// Brings the tunnel up for the current selection.
    ///
    /// A user-supplied proxy is used directly; every Dezor server goes through the
    /// in-process Shadowsocks listener.
    private func restartTunnel() {
        budgetTask?.cancel()
        budgetTask = nil

        if selectedServer.isCustom {
            #if canImport(Network)
            proxyServer.stop()
            #endif
            localPort = nil
            guard !selectedServer.host.isEmpty else {
                statusMessage = L("Kein Proxy-Host angegeben")
                isConnected = false
                return
            }
            bumpRevision()
            statusMessage = L("Verbinde…")
            Task { await verifyConnection() }
            return
        }

        // The backend advertises servers that are not always reachable — a live check
        // found the least-loaded one refusing connections entirely. "Automatic" therefore
        // walks the least-loaded servers in turn.
        // An explicit choice of country is never
        // silently swapped for another one: that would defeat the point of picking it.
        if selectedServer.id == "auto" {
            candidates = Array(
                availableServers
                    .filter { !$0.isCustom && $0.id != "auto" }
                    .sorted { ($0.load ?? 1) < ($1.load ?? 1) }
                    .prefix(3)
            )
        } else {
            candidates = [selectedServer]
        }
        candidateIndex = 0
        attemptNextCandidate()
    }

    /// Tries `candidates[candidateIndex]`, advancing on failure.
    private func attemptNextCandidate() {
        #if canImport(Network)
        guard isEnabled else { return }
        guard let method = shadowsocksMethod,
              let password = shadowsocksPassword,
              let ssPort = shadowsocksPort else {
            statusMessage = L("Keine VPN-Konfiguration vom Server erhalten")
            isConnecting = false
            isConnected = false
            return
        }
        guard candidateIndex < candidates.count else {
            isConnecting = false
            isConnected = false
            localPort = nil
            statusMessage = L("Proxy-Server nicht erreichbar")
            return
        }

        let server = candidates[candidateIndex]
        guard !server.host.isEmpty else {
            candidateIndex += 1
            attemptNextCandidate()
            return
        }

        // A per-server key replaces the account password, in the "<key>:<key>" form the
        // backend expects.
        let effectivePassword: String
        if let key = server.ssKey, !key.isEmpty {
            effectivePassword = "\(key):\(key)"
        } else {
            effectivePassword = password
        }

        let config = SSServerConfig(
            host: server.host,
            port: UInt16(exactly: server.port) ?? ssPort,
            method: method,
            password: effectivePassword
        )

        isConnecting = true
        isConnected = false
        statusMessage = L("Verbinde…")

        proxyServer.start(config: config) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let port):
                    self.localPort = port
                    self.bumpRevision()
                    if await self.verifyConnection() != nil {
                        self.noteConnected(to: server)
                        self.armBudgetTimer()
                    } else {
                        self.candidateIndex += 1
                        self.attemptNextCandidate()
                    }
                case .failure:
                    self.candidateIndex += 1
                    self.attemptNextCandidate()
                }
            }
        }
        #else
        statusMessage = L("VPN auf dieser Plattform nicht verfügbar")
        #endif
    }

    /// Keeps the "Automatic" entry showing the location actually in use, so the UI never
    /// names a city the traffic is not going through.
    private func noteConnected(to server: VPNServerLocation) {
        guard selectedServer.id == "auto" else { return }
        let updated = VPNManager.automaticEntry(for: server)
        if let idx = availableServers.firstIndex(where: { $0.id == "auto" }) {
            availableServers[idx] = updated
        }
        selectedServer = updated
    }

    /// The synthetic "Automatic" entry, carrying the city it currently resolves to.
    private static func automaticEntry(for server: VPNServerLocation) -> VPNServerLocation {
        VPNServerLocation(
            id: "auto",
            name: L("Automatisch"),
            city: server.city,
            country: server.country,
            flag: "⚡",
            host: server.host,
            port: server.port,
            proto: .socks5,
            ssKey: server.ssKey,
            load: server.load
        )
    }

    private func teardownTunnel() {
        budgetTask?.cancel()
        budgetTask = nil
        #if canImport(Network)
        proxyServer.stop()
        #endif
        localPort = nil
        isConnected = false
        isConnecting = false
        currentPublicIP = nil
        bumpRevision()
    }

    private func bumpRevision() {
        proxyRevision += 1
    }

    private func persist(enabled: Bool) {
        var settings = StorageService.shared.settings
        settings.vpnEnabled = enabled
        StorageService.shared.updateSettings(settings)
    }

    /// Disconnects automatically when the free budget runs out, mirroring how the
    /// VPN stops at the limit instead of quietly continuing.
    private func armBudgetTimer() {
        guard !DezorAuthService.shared.hasUnlimitedVPN else { return }
        let remaining = DezorAuthService.shared.currentUser?.remainingProxyDuration ?? 0
        guard remaining > 0 else { return }
        budgetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isEnabled else { return }
                self.isProxyLocked = true
                self.setEnabled(false)
                self.statusMessage = L("Freies VPN-Kontingent aufgebraucht")
            }
        }
    }

    // MARK: - Verification

    /// Confirms the tunnel actually carries traffic. Only after this succeeds does the UI
    /// claim to be connected — the old build reported "connected" before ever trying.
    @discardableResult
    public func verifyConnection() async -> String? {
        isConnecting = true
        defer { isConnecting = false }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 12
        applyToURLSessionConfiguration(sessionConfig)
        let session = sessionFactory(sessionConfig)

        guard let url = URL(string: "https://api.ipify.org?format=json") else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ip = json["ip"] as? String else {
                isConnected = false
                statusMessage = L("Proxy-Antwort nicht lesbar")
                return nil
            }
            currentPublicIP = ip
            isConnected = true
            statusMessage = "\(L("Verbunden")) · \(ip)"
            return ip
        } catch {
            isConnected = false
            currentPublicIP = nil
            statusMessage = L("Proxy-Server nicht erreichbar")
            return nil
        }
    }

    // MARK: - Applying the proxy

    /// The endpoint every proxied client should talk to, or nil when traffic must go
    /// direct. Single source of truth so WebKit and URLSession can never disagree.
    private var effectiveProxy: (host: String, port: UInt16, proto: ProxyProtocol)? {
        guard isEnabled else { return nil }
        if selectedServer.isCustom {
            guard !selectedServer.host.isEmpty,
                  let port = UInt16(exactly: selectedServer.port) else { return nil }
            return (selectedServer.host, port, selectedServer.proto)
        }
        guard let localPort else { return nil }
        return ("127.0.0.1", localPort, .socks5)
    }

    #if canImport(WebKit)
    public func applyToWebsiteDataStore(_ dataStore: WKWebsiteDataStore) {
        #if canImport(Network)
        if #available(iOS 17.0, macOS 14.0, *) {
            guard let proxy = effectiveProxy else {
                dataStore.proxyConfigurations = []
                return
            }
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(proxy.host),
                port: NWEndpoint.Port(rawValue: proxy.port) ?? .https
            )
            let configuration: ProxyConfiguration
            switch proxy.proto {
            case .socks5:
                configuration = ProxyConfiguration(socksv5Proxy: endpoint)
            case .http, .https:
                configuration = ProxyConfiguration(httpCONNECTProxy: endpoint)
            }
            dataStore.proxyConfigurations = [configuration]
        }
        #endif
    }
    #endif

    public func applyToURLSessionConfiguration(_ config: URLSessionConfiguration) {
        config.connectionProxyDictionary = proxyDictionary()
    }

    /// CFNetwork proxy settings for the current tunnel, or nil when traffic goes direct.
    private func proxyDictionary() -> [AnyHashable: Any]? {
        guard let proxy = effectiveProxy else { return nil }
        let dictionary: [AnyHashable: Any]
        switch proxy.proto {
        case .socks5:
            dictionary = [
                kCFStreamPropertySOCKSProxyHost as String: proxy.host,
                kCFStreamPropertySOCKSProxyPort as String: Int(proxy.port),
                kCFStreamPropertySOCKSVersion as String: kCFStreamSocketSOCKSVersion5,
                "SOCKSEnable": 1
            ]
        case .http, .https:
            dictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: proxy.host,
                kCFNetworkProxiesHTTPPort as String: Int(proxy.port),
                // The HTTPS equivalents are unavailable as constants on iOS; the literal
                // keys are what CFNetwork actually looks for.
                "HTTPSEnable": true,
                "HTTPSProxy": proxy.host,
                "HTTPSPort": Int(proxy.port)
            ]
        }
        return dictionary
    }

    // MARK: - Waiting for the tunnel

    /// Switches the VPN on if needed and waits until it has proven itself, or until
    /// `timeout` passes. Playback calls this so a film never starts outside the tunnel.
    public func ensureConnected(timeout: TimeInterval = 25) async -> Bool {
        if isConnected { return true }
        if !isEnabled { setEnabled(true) }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isConnected { return true }
            // Switched off again (quota, user) — no point waiting.
            if !isEnabled { return false }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return isConnected
    }
}

/// The proxy that traffic which must not leave outside the VPN goes through.
///
/// Readable from any thread — the stream proxy and the addon task fetches run off the
/// main actor — and only ever set by `VPNManager` once the tunnel has been verified.
/// `nil` means "not connected": those callers then refuse to fetch rather than go direct.
public enum VPNRoute {
    private static let lock = NSLock()
    private static var dictionary: [AnyHashable: Any]?

    public static var proxyDictionary: [AnyHashable: Any]? {
        lock.lock(); defer { lock.unlock() }
        return dictionary
    }

    static func set(_ value: [AnyHashable: Any]?) {
        lock.lock(); defer { lock.unlock() }
        dictionary = value
    }
}
