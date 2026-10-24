import Foundation
import Combine

public enum DebugLogLevel: Int, CaseIterable, Comparable, Identifiable {
    case info, warning, error

    public var id: Int { rawValue }
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

public struct DebugLogEntry: Identifiable, Equatable {
    public let id: Int
    public let date: Date
    public let level: DebugLogLevel
    public let category: String
    public let message: String

    /// One line in the export format.
    public var line: String {
        "\(DebugLogFormat.time.string(from: date)) \(level.label.padding(toLength: 5, withPad: " ", startingAt: 0)) [\(category)] \(message)"
    }
}

enum DebugLogFormat {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

/// In-memory app log for the developer panel.
///
/// Lives only in memory on purpose: it survives the app going to the background and is
/// gone once the app is fully closed, and logging is off again on the next launch. Nothing
/// is written to disk, so there is nothing to clean up and nothing to leak.
///
/// Everything passes through `DebugLogSanitizer` before it is stored, so the log carries
/// facts about the app and the device, never about the person using it.
@MainActor
public final class DebugLog: ObservableObject {
    public static let shared = DebugLog()

    @Published public private(set) var entries: [DebugLogEntry] = []
    @Published public private(set) var isEnabled = false
    public private(set) var startedAt: Date?

    /// Ring buffer size: old lines drop off instead of growing memory without bound.
    public static let capacity = 3000
    private var nextId = 0

    private init() {}

    public func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        Flag.set(on)
        if on {
            startedAt = Date()
            append(.info, "Log", "Logging eingeschaltet")
        } else {
            append(.info, "Log", "Logging ausgeschaltet", force: true)
        }
    }

    public func clear() {
        entries.removeAll()
        nextId = 0
    }

    /// A line the tester inserts by hand right before reproducing a problem.
    public func marker(_ text: String = "MARKER") {
        append(.info, "Marker", text, force: true)
    }

    fileprivate func append(_ level: DebugLogLevel, _ category: String, _ message: String, force: Bool = false) {
        guard isEnabled || force else { return }
        entries.append(DebugLogEntry(
            id: nextId, date: Date(), level: level, category: category,
            message: DebugLogSanitizer.clean(message)
        ))
        nextId += 1
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    // MARK: Logging from anywhere

    /// Thread-safe mirror of `isEnabled`, so callers on any thread skip the work (and the
    /// hop to the main actor) entirely while logging is off.
    private enum Flag {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var on = false
        static func set(_ value: Bool) { lock.lock(); on = value; lock.unlock() }
        static var value: Bool { lock.lock(); defer { lock.unlock() }; return on }
    }

    /// Logs a line. The message is an autoclosure, so building it costs nothing while
    /// logging is off.
    public nonisolated static func log(
        _ level: DebugLogLevel = .info,
        _ category: String,
        _ message: @autoclosure () -> String
    ) {
        guard Flag.value else { return }
        let text = message()
        Task { @MainActor in shared.append(level, category, text) }
    }
}

/// Removes everything that could identify the user from a log line.
///
/// Allowed: what the app did, error codes, hosts of streaming servers, counts, timings.
/// Removed: e-mail addresses, IP addresses, tokens and keys, URL paths and query strings,
/// credentials inside URLs, file system paths.
public enum DebugLogSanitizer {
    public static func clean(_ input: String) -> String {
        var s = input
        // URLs keep scheme and host only: paths and queries carry tokens and media ids.
        s = replace(#"(?i)\b([a-z][a-z0-9+.\-]*)://(?:[^/\s@]+@)?([^/\s?#:]+)(?::\d+)?[^\s"')>\]]*"#, in: s, with: "$1://$2/…")
        s = replace(#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, in: s, with: "<e-mail>")
        s = replace(#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, in: s, with: "<ip>")
        s = replace(#"(?i)\b(?:[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}\b"#, in: s, with: "<ip>")
        s = replace(#"(?i)\b(bearer|basic)\s+[^\s,;]+"#, in: s, with: "$1 <redacted>")
        s = replace(#"(?i)(token|secret|password|passwd|authorization|bearer|apikey|api_key|key|expiry|session)(["']?\s*[:=]\s*["']?)[^\s,;&"']+"#, in: s, with: "$1$2<redacted>")
        s = replace(#"/(?:Users|var/mobile|private/var)/[^\s"')]+"#, in: s, with: "<path>")
        // Long opaque strings are almost always tokens or hashes.
        s = replace(#"\b[A-Za-z0-9_\-]{28,}\b"#, in: s, with: "<redacted>")
        return s
    }

    private static func replace(_ pattern: String, in s: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template
        )
    }
}
