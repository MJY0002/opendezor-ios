import Foundation

/// Reachability of one installed addon: host, HTTP status and round-trip time. The host
/// is shown because a developer needs to tell the addons apart; path and query never are.
public struct AddonCheckResult: Identifiable, Equatable {
    public let id: String
    public let host: String
    public let status: String
    public let latencyMs: Int?
    public var line: String {
        "\(host): \(status)" + (latencyMs.map { " (\($0) ms)" } ?? "")
    }
}

@MainActor
public enum AddonCheck {
    public static func run() async -> [AddonCheckResult] {
        let addons = AddonManager.shared.activeAddons.filter(\.isEnabled)
        var results: [AddonCheckResult] = []
        for addon in addons {
            let host = URL(string: addon.endpoint)?.host ?? "?"
            guard let url = URL(string: addon.endpoint) else {
                results.append(AddonCheckResult(id: addon.id, host: host, status: "ungültige Adresse", latencyMs: nil))
                continue
            }
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "HEAD"
            let start = Date()
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode
                results.append(AddonCheckResult(
                    id: addon.id, host: host,
                    status: code.map { "HTTP \($0)" } ?? "Antwort",
                    latencyMs: Int(Date().timeIntervalSince(start) * 1000)
                ))
            } catch {
                results.append(AddonCheckResult(id: addon.id, host: host, status: "Fehler \((error as NSError).code)", latencyMs: nil))
            }
        }
        for r in results { DebugLog.log(r.status.hasPrefix("HTTP 2") ? .info : .warning, "Addon", r.line) }
        return results
    }
}

/// A compact picture of the app's state at one moment: what is on, what is connected,
/// what is playing. No titles, no account data, no addon addresses.
@MainActor
public enum AppStateSnapshot {
    public static func lines() -> [String] {
        let vpn = VPNManager.shared
        let app = AppState.shared
        let storage = StorageService.shared
        let addons = AddonManager.shared.activeAddons
        let player = PlayerService.shared
        return [
            "VPN: " + (vpn.isConnected ? "verbunden" : (vpn.isConnecting ? "verbindet" : "getrennt"))
                + ", Server: \(vpn.selectedServer.country) \(vpn.selectedServer.city)"
                + (vpn.isProxyLocked ? ", Kontingent aufgebraucht" : ""),
            "Addons: \(addons.count) installiert, \(addons.filter(\.isEnabled).count) aktiv",
            "Wiedergabe: " + (app.isPlayerPresented ? (player.isPlaying ? "läuft" : "pausiert") : "aus")
                + (app.isPreparingPlayback ? ", Stream wird vorbereitet" : ""),
            "Player-Fehler: \(player.errorMessage.map(DebugLogSanitizer.clean) ?? "keiner")",
            "Bevorzugte Qualität: \(storage.settings.defaultQuality)",
            "Verlauf: \(storage.watchHistory.count) Einträge, Favoriten: \(storage.favorites.count)",
        ]
    }
}

public enum DebugReport {
    /// The text a tester exports or copies: device, network, state, player, then the log.
    @MainActor
    public static func text(
        entries: [DebugLogEntry],
        device: DeviceSnapshot? = nil,
        addonChecks: [AddonCheckResult] = []
    ) -> String {
        let device = device ?? DeviceSnapshot.current()
        let network = NetworkDiagnostics.shared
        func section(_ title: String, _ lines: [String]) -> String {
            "## \(title)\n" + lines.map { "- \($0)" }.joined(separator: "\n")
        }
        var parts = [
            "# OpenDezor Debug-Bericht",
            "Erstellt: \(ISO8601DateFormatter().string(from: Date()))",
            "Hinweis: Enthält keine Kontodaten, Titel, IP-Adressen oder Netzwerknamen.",
            section("Gerät", device.lines),
            section("Netzwerk", network.lines),
            section("App-Zustand", AppStateSnapshot.lines()),
            section("Player", PlayerStats.current().lines),
        ]
        if !addonChecks.isEmpty { parts.append(section("Addon-Check", addonChecks.map(\.line))) }
        let log = entries.isEmpty ? "(leer – Logging einschalten und den Fehler nachstellen)" : entries.map(\.line).joined(separator: "\n")
        parts.append("## Log (\(entries.count) Zeilen)\n```\n\(log)\n```")
        return parts.joined(separator: "\n\n")
    }
}
