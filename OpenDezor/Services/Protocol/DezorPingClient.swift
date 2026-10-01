import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Dezor App API Transport
//
// The Dezor backend exposes a single RPC endpoint: POST https://www.dezor.net/api/app/ping.
// Every call — plain keep-alive, login, register, connect-code pairing — is that same POST
// with a large state envelope; the `call` field selects the remote procedure and `params`
// carries its arguments. The procedure's return value comes back in `result`, while the
// envelope itself always carries a fresh `token`, the resolved `region` and the current
// `user` record.
//
// Known `call` values: user.login, user.register, user.logout, user.passwordLost,
// connect.check, connect.remove, coupon.redeem, iap.*, partner.*.

/// What this client tells the backend about its VPN capabilities.
///
/// `supported` gates the response: only a client that lists `ss` is handed the
/// Shadowsocks cipher and password. OpenVPN is never claimed — it needs a system tun
/// device that sideloaded iOS cannot open.
public struct DezorProxyState: Equatable {
    public let enabled: Bool
    public let autoServer: Bool
    public let id: String?

    public init(enabled: Bool, autoServer: Bool, id: String?) {
        self.enabled = enabled
        self.autoServer = autoServer
        self.id = id
    }
}

public struct DezorPingResult: Codable, Equatable {
    public let status: String?
    public let code: String?
    public let error: String?
    public let nextPing: Double?
}

/// The `proxy` object of a ping response — the real VPN configuration.
///
/// Dezor's VPN is Shadowsocks: `shadowsocks` carries the cipher, the account password and
/// the port, and `locations` is a country -> city -> server tree whose leaves hold the
/// actual server IPs plus their current load. This app feeds it into
/// `LocalProxyServer`.
///
/// `openvpn` is deliberately not modelled: an OpenVPN tunnel needs a system tun device,
/// which requires a NetworkExtension entitlement that ad-hoc sideloading cannot grant.
public struct DezorProxyConfig: Codable {
    public struct Shadowsocks: Codable {
        public let method: String?
        public let password: String?
        public let port: Int?
    }

    /// One node of the locations tree. `type` is `country`, `city` or `server`; only
    /// server leaves carry `ip`.
    public struct Node: Codable {
        public let type: String?
        public let name: String?
        public let id: String?
        public let free: Bool?
        public let ip: String?
        public let load: Double?
        public let speed: Double?
        /// Per-server key. When present it replaces the global password, in the
        /// `"<key>:<key>"` form the backend expects.
        public let ssKey: String?
        public let children: [Node]?
    }

    public let dns: String?
    public let shadowsocks: Shadowsocks?
    public let locations: [Node]?
}

public struct DezorPingResponse: Codable {
    public let token: String?
    public let region: String?
    public let user: DezorUser?
    public let nextPing: Double?
    public let result: DezorPingResult?
    public let error: String?
    public let proxy: DezorProxyConfig?

    // Decoded field by field so that an unexpected shape in `proxy` — a part of the
    // envelope nothing else depends on — can never break login or token refresh.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decodeIfPresent(String.self, forKey: .token)
        region = try c.decodeIfPresent(String.self, forKey: .region)
        user = try c.decodeIfPresent(DezorUser.self, forKey: .user)
        nextPing = try c.decodeIfPresent(Double.self, forKey: .nextPing)
        result = try c.decodeIfPresent(DezorPingResult.self, forKey: .result)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        proxy = try? c.decodeIfPresent(DezorProxyConfig.self, forKey: .proxy)
    }
}

public struct DezorDeviceMetadata: Codable {
    public struct Device: Codable {
        public let type: String
        public let uniqueId: String
    }
    public struct OS: Codable {
        public let name: String
        public let version: String
        public let abis: [String]
        public let host: String
    }
    public struct Platform: Codable {
        public let isAndroid: Bool
        public let isIOS: Bool
        public let isTV: Bool
        public let isWeb: Bool
        public let isMobile: Bool
        public let isWebTV: Bool
        public let isElectron: Bool
    }
    public struct App: Codable {
        public let platform: String
    }
    public struct Version: Codable {
        public let package: String
        public let binary: String
        public let js: String
    }

    public let device: Device
    public let os: OS
    public let platform: Platform
    public let app: App
    public let version: Version
}

@MainActor
public class DezorPingClient {
    public static let shared = DezorPingClient()

    /// Client identification the Dezor ping API expects.
    /// The backend keys entitlements off the package id, so these must match.
    public static let apiEndpoint = "https://www.dezor.net/api/app"
    public static let connectEndpointTemplate = "https://www.dezor.net/connect?code={code}&lng={lng}"
    public static let appPackage = "net.dezor.browser"
    public static let appVersion = "4.8.0"

    private static let deviceIdKey = "opendezor_device_id"

    private let session: URLSession
    private let firstAppStart: Double
    private let appStart: Double

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 30
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }

        let now = Date().timeIntervalSince1970 * 1000
        let storedFirstStart = UserDefaults.standard.double(forKey: "opendezor_first_app_start")
        if storedFirstStart > 0 {
            self.firstAppStart = storedFirstStart
        } else {
            UserDefaults.standard.set(now, forKey: "opendezor_first_app_start")
            self.firstAppStart = now
        }
        self.appStart = now
    }

    /// Stable per-installation identifier. The backend ties the anonymous token and the
    /// connect code to it, so it must survive app restarts.
    public static var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIdKey), !existing.isEmpty {
            return existing
        }
        #if canImport(UIKit)
        let generated = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        let generated = UUID().uuidString
        #endif
        UserDefaults.standard.set(generated, forKey: deviceIdKey)
        return generated
    }

    public static var metadata: DezorDeviceMetadata {
        #if os(iOS)
        let osName = "ios"
        let osVersion = UIDevice.current.systemVersion
        let host = UIDevice.current.model
        let deviceType = UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "mobile"
        let isPhone = true
        let appPlatform = "ios"
        #else
        let osName = "macos"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let host = Host.current().localizedName ?? "Mac"
        let deviceType = "desktop"
        let isPhone = false
        let appPlatform = "macos"
        #endif

        return DezorDeviceMetadata(
            device: .init(type: deviceType, uniqueId: deviceId),
            os: .init(name: osName, version: osVersion, abis: ["arm64"], host: host),
            platform: .init(
                isAndroid: false,
                isIOS: isPhone,
                isTV: false,
                isWeb: false,
                isMobile: isPhone,
                isWebTV: false,
                isElectron: false
            ),
            app: .init(platform: appPlatform),
            version: .init(package: appPackage, binary: appVersion, js: appVersion)
        )
    }

    /// Performs one `/ping` round trip. `call` selects the remote procedure; passing nil
    /// makes it a plain keep-alive that still refreshes token, region and user.
    ///
    /// `proxyState` must describe the VPN engines this build can actually drive. The
    /// backend only returns `proxy.shadowsocks` — the cipher and password — to a client
    /// that declares it speaks `ss`; omit this and the server list comes back without
    /// credentials and the VPN cannot connect.
    public func ping(
        token: String?,
        reason: String,
        call: String? = nil,
        params: [String: Any]? = nil,
        playDuration: Double = 0,
        playerActive: Bool = false,
        hasAddon: Bool = false,
        proxyState: DezorProxyState? = nil
    ) async throws -> DezorPingResponse {
        guard let url = URL(string: "\(Self.apiEndpoint)/ping") else {
            throw MediaHubError.invalidUrl("\(Self.apiEndpoint)/ping")
        }

        let metadataDict: Any
        if let data = try? JSONEncoder().encode(Self.metadata),
           let dict = try? JSONSerialization.jsonObject(with: data) {
            metadataDict = dict
        } else {
            metadataDict = NSNull()
        }

        var body: [String: Any] = [
            "token": token as Any,
            "reason": reason,
            "locale": Locale.current.language.languageCode?.identifier ?? "de",
            "theme": "dark",
            "metadata": metadataDict,
            "appFocusTime": 0,
            "playerActive": playerActive,
            "playDuration": playDuration,
            "devMode": false,
            "hasAddon": hasAddon,
            "castConnected": false,
            "package": Self.appPackage,
            "version": Self.appVersion,
            "process": "main",
            "firstAppStart": firstAppStart,
            "lastAppStart": appStart
        ]
        if token == nil {
            body["token"] = NSNull()
        }
        if let proxyState {
            // `supported`, `engine` and `ssVersion` describe what this build can drive, not
            // anything the caller chooses — Shadowsocks, always. They are fixed here rather
            // than carried as never-varied fields on `DezorProxyState`.
            body["proxy"] = [
                "supported": ["ss"],
                "engine": "ss",
                "ssVersion": 0,
                "enabled": proxyState.enabled,
                "autoServer": proxyState.autoServer,
                "id": proxyState.id as Any
            ]
        }
        if let call {
            body["call"] = call
        }
        if let params {
            body["params"] = params
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MediaHubError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw MediaHubError.httpError(statusCode: -1, message: L("Keine gültige HTTP-Antwort"))
        }
        guard (200...299).contains(http.statusCode) else {
            throw MediaHubError.httpError(
                statusCode: http.statusCode,
                message: String(data: data, encoding: .utf8) ?? ""
            )
        }

        do {
            return try JSONDecoder().decode(DezorPingResponse.self, from: data)
        } catch {
            throw MediaHubError.decodingError("Antwort von dezor.net nicht lesbar: \(error.localizedDescription)")
        }
    }
}
