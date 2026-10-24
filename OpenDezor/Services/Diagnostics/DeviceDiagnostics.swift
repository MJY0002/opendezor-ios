import Foundation
import Network
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// What the developer needs to know about the device a log came from. Deliberately only
/// hardware and system facts: no name, no account, no network name, no location.
public struct DeviceSnapshot: Equatable {
    public var model: String            // e.g. "iPhone16,2"
    public var systemVersion: String
    public var appVersion: String
    public var memoryTotalMB: Int
    public var memoryAppMB: Int?
    public var diskFreeGB: Double?
    public var diskTotalGB: Double?
    public var batteryPercent: Int?
    public var batteryState: String
    public var lowPowerMode: Bool
    public var thermalState: String
    public var languageCode: String
    public var uptimeMinutes: Int

    public static func current() -> DeviceSnapshot {
        let info = ProcessInfo.processInfo
        var disk: (free: Double, total: Double)?
        if let v = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
           let free = v.volumeAvailableCapacityForImportantUsage, let total = v.volumeTotalCapacity {
            disk = (Double(free) / 1e9, Double(total) / 1e9)
        }
        var battery: Int?
        var batteryState = "n/a"
        #if os(iOS)
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        if device.batteryLevel >= 0 { battery = Int((device.batteryLevel * 100).rounded()) }
        switch device.batteryState {
        case .charging: batteryState = "charging"
        case .full: batteryState = "full"
        case .unplugged: batteryState = "unplugged"
        default: batteryState = "unknown"
        }
        #endif
        let thermal: String
        switch info.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return DeviceSnapshot(
            model: machineIdentifier(),
            systemVersion: info.operatingSystemVersionString,
            appVersion: "\(version) (\(build))",
            memoryTotalMB: Int(info.physicalMemory / 1_048_576),
            memoryAppMB: appMemoryMB(),
            diskFreeGB: disk?.free,
            diskTotalGB: disk?.total,
            batteryPercent: battery,
            batteryState: batteryState,
            lowPowerMode: info.isLowPowerModeEnabled,
            thermalState: thermal,
            languageCode: LocalizationController.shared.code,
            uptimeMinutes: Int(info.systemUptime / 60)
        )
    }

    /// Hardware identifier such as "iPhone16,2"; the Simulator reports the host model in
    /// an environment variable instead.
    static func machineIdentifier() -> String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "Simulator (\(sim))"
        }
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    /// Resident memory of this app.
    static func appMemoryMB() -> Int? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size / 1_048_576) : nil
    }

    public var lines: [String] {
        var out = [
            "Modell: \(model)",
            "System: \(systemVersion)",
            "App: \(appVersion)",
            "Sprache: \(languageCode)",
            "RAM gesamt: \(memoryTotalMB) MB" + (memoryAppMB.map { ", App belegt: \($0) MB" } ?? ""),
        ]
        if let free = diskFreeGB, let total = diskTotalGB {
            out.append(String(format: "Speicher frei: %.1f von %.0f GB", free, total))
        }
        out.append("Akku: " + (batteryPercent.map { "\($0) %" } ?? "n/a") + " (\(batteryState))" + (lowPowerMode ? ", Stromsparmodus an" : ""))
        out.append("Temperatur-Status: \(thermalState)")
        out.append("Laufzeit seit Neustart: \(uptimeMinutes) min")
        return out
    }
}

/// Connection type and quality, live. Uses the system path monitor, which exposes the kind
/// of link but never the network's name, so nothing about where the user is leaks.
@MainActor
public final class NetworkDiagnostics: ObservableObject {
    public static let shared = NetworkDiagnostics()

    @Published public private(set) var status = "unbekannt"
    @Published public private(set) var link = "unbekannt"
    @Published public private(set) var isExpensive = false
    @Published public private(set) var isConstrained = false
    @Published public private(set) var supportsIPv4 = false
    @Published public private(set) var supportsIPv6 = false
    @Published public private(set) var supportsDNS = false

    @Published public private(set) var isTesting = false
    @Published public private(set) var downMbps: Double?
    @Published public private(set) var latencyMs: Int?
    @Published public private(set) var testNote: String?

    private let monitor = NWPathMonitor()
    private var started = false

    public func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.apply(path) }
        }
        monitor.start(queue: DispatchQueue(label: "org.opendezor.netdiag"))
    }

    private func apply(_ path: NWPath) {
        let new: String
        switch path.status {
        case .satisfied: new = "online"
        case .unsatisfied: new = "offline"
        case .requiresConnection: new = "benötigt Verbindung"
        @unknown default: new = "unbekannt"
        }
        let types: [(NWInterface.InterfaceType, String)] = [
            (.wifi, "WLAN"), (.cellular, "Mobilfunk"), (.wiredEthernet, "Ethernet"), (.loopback, "Loopback"), (.other, "Sonstiges")
        ]
        let newLink = types.first { path.usesInterfaceType($0.0) }?.1 ?? "keine"
        if new != status { DebugLog.log(.info, "Netz", "Status: \(new)") }
        if newLink != link { DebugLog.log(.info, "Netz", "Verbindung: \(newLink)") }
        status = new
        link = newLink
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        supportsIPv4 = path.supportsIPv4
        supportsIPv6 = path.supportsIPv6
        supportsDNS = path.supportsDNS
    }

    /// Measures real throughput by downloading a fixed test file, plus round-trip time of
    /// a tiny request. Only the numbers are kept. The server sees an anonymous request
    /// like any web page would.
    public func runSpeedTest() async {
        guard !isTesting else { return }
        isTesting = true
        testNote = nil
        downMbps = nil
        latencyMs = nil
        defer { isTesting = false }

        let session = URLSession(configuration: {
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = 15
            c.requestCachePolicy = .reloadIgnoringLocalCacheData
            return c
        }())
        do {
            let pingStart = Date()
            _ = try await session.data(from: URL(string: "https://speed.cloudflare.com/__down?bytes=1")!)
            latencyMs = Int(Date().timeIntervalSince(pingStart) * 1000)

            let bytes = 8_000_000
            let start = Date()
            let (data, _) = try await session.data(from: URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)")!)
            let seconds = max(Date().timeIntervalSince(start), 0.001)
            downMbps = Double(data.count) * 8 / seconds / 1_000_000
            DebugLog.log(.info, "Netz", String(format: "Speedtest: %.1f Mbit/s, Latenz %d ms (%@)", downMbps ?? 0, latencyMs ?? 0, link))
        } catch {
            testNote = "Test fehlgeschlagen: \(error.localizedDescription)"
            DebugLog.log(.warning, "Netz", "Speedtest fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    public var lines: [String] {
        guard status != "unbekannt" else { return ["Status: noch nicht ermittelt (Panel öffnen startet die Messung)"] }
        var out = [
            "Status: \(status), Verbindung: \(link)",
            "Teuer: \(isExpensive ? "ja" : "nein"), Datensparmodus: \(isConstrained ? "ja" : "nein")",
        ]
        // The Simulator reports all three as unsupported while online; a real "no" only means something offline.
        if status != "online" || supportsIPv4 || supportsIPv6 || supportsDNS {
            out.append("IPv4: \(supportsIPv4 ? "ja" : "nein"), IPv6: \(supportsIPv6 ? "ja" : "nein"), DNS: \(supportsDNS ? "ja" : "nein")")
        }
        if let down = downMbps {
            out.append(String(format: "Speedtest: %.1f Mbit/s Download, Latenz %d ms", down, latencyMs ?? 0))
        } else if let note = testNote {
            out.append(note)
        }
        return out
    }
}

/// Live numbers from the current stream, read from AVFoundation's access log.
public struct PlayerStats: Equatable {
    public var active = false
    public var observedKbps: Int?
    public var indicatedKbps: Int?
    public var segmentsDownloaded: Int?
    public var stalls: Int?
    public var droppedFrames: Int?
    public var bufferedSeconds: Double?
    public var viaVPN = false
    public var isLive = false

    @MainActor
    public static func current() -> PlayerStats {
        let p = PlayerService.shared
        guard let item = p.player?.currentItem else { return PlayerStats() }
        var s = PlayerStats()
        s.active = true
        s.viaVPN = p.isRoutedThroughVPN
        s.isLive = p.isLive
        s.bufferedSeconds = max(0, p.bufferedTime - p.currentTime)
        if let e = item.accessLog()?.events.last {
            if e.observedBitrate > 0 { s.observedKbps = Int(e.observedBitrate / 1000) }
            if e.indicatedBitrate > 0 { s.indicatedKbps = Int(e.indicatedBitrate / 1000) }
            s.segmentsDownloaded = e.numberOfMediaRequests
            s.stalls = e.numberOfStalls
            s.droppedFrames = e.numberOfDroppedVideoFrames
        }
        return s
    }

    public var lines: [String] {
        guard active else { return ["Kein Stream aktiv"] }
        func v(_ n: Int?, _ unit: String = "") -> String { n.map { "\($0)\(unit)" } ?? "n/a" }
        return [
            "Über VPN: \(viaVPN ? "ja" : "nein"), Live: \(isLive ? "ja" : "nein")",
            "Bitrate gemessen: \(v(observedKbps, " kbit/s")), angeboten: \(v(indicatedKbps, " kbit/s"))",
            "Segmente: \(v(segmentsDownloaded)), Aussetzer: \(v(stalls)), verworfene Bilder: \(v(droppedFrames))",
            "Puffer: " + (bufferedSeconds.map { String(format: "%.1f s", $0) } ?? "n/a"),
        ]
    }
}
