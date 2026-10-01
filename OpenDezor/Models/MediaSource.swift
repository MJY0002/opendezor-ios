import Foundation

// MARK: - Stream Format
public enum StreamFormat: String, Codable, Equatable, Hashable {
    case hls
    case mp4
    case dash
    case webm
    case unknown
    
    public static func detect(from urlString: String, hint: String? = nil) -> StreamFormat {
        if let h = hint?.lowercased() {
            if h.contains("hls") || h.contains("m3u8") { return .hls }
            if h.contains("mp4") { return .mp4 }
            if h.contains("dash") || h.contains("mpd") { return .dash }
            if h.contains("webm") { return .webm }
        }
        let lower = urlString.lowercased()
        if lower.contains(".m3u8") || lower.contains("/hls/") { return .hls }
        if lower.contains(".mp4") { return .mp4 }
        if lower.contains(".mpd") { return .dash }
        if lower.contains(".webm") { return .webm }
        return .unknown
    }
}

// MARK: - Media Source
public struct MediaSource: Codable, Identifiable, Equatable, Hashable {
    public var id: String { customId ?? url }
    public let customId: String?
    public let type: String? // "url", "externalUrl", "resolver"
    public let url: String
    public let name: TranslatedText?
    public let quality: String?
    public let format: String? // "hls", "mp4", etc.
    public let icon: String?
    public let languages: [String]?
    public let subtitles: [Subtitle]?
    public let headers: [String: String]?
    public let resolved: Bool?
    public let priority: Int?
    
    enum CodingKeys: String, CodingKey {
        case customId = "id"
        case type, url, name, quality, format, icon, languages, subtitles, headers, resolved, priority
    }
    
    public init(
        customId: String? = nil,
        type: String? = "url",
        url: String,
        name: TranslatedText? = nil,
        quality: String? = nil,
        format: String? = nil,
        icon: String? = nil,
        languages: [String]? = nil,
        subtitles: [Subtitle]? = nil,
        headers: [String: String]? = nil,
        resolved: Bool? = nil,
        priority: Int? = nil
    ) {
        self.customId = customId
        self.type = type
        self.url = url
        self.name = name
        self.quality = quality
        self.format = format
        self.icon = icon
        self.languages = languages
        self.subtitles = subtitles
        self.headers = headers
        self.resolved = resolved
        self.priority = priority
    }
    
    public var displayName: String {
        if let val = name?.value, !val.isEmpty {
            return val
        }
        if let q = quality, !q.isEmpty {
            return "\(q) - \(format?.uppercased() ?? "Stream")"
        }
        return format?.uppercased() ?? L("Standard Stream")
    }
    
    public var isDirectStream: Bool {
        if resolved == true { return true }
        if type == "resolver" { return false }
        let lower = url.lowercased()
        return lower.contains(".m3u8") || lower.contains(".mp4") || lower.contains(".mpd")
    }
}

// MARK: - Resolved URL Response from Protocol Resolver
public struct ResolvedUrl: Codable, Equatable {
    public let url: String
    public let name: String?
    public let quality: String?
    public let format: String?
    public let headers: [String: String]?
    public let resolveAgain: Bool?
    
    public init(
        url: String,
        name: String? = nil,
        quality: String? = nil,
        format: String? = nil,
        headers: [String: String]? = nil,
        resolveAgain: Bool? = nil
    ) {
        self.url = url
        self.name = name
        self.quality = quality
        self.format = format
        self.headers = headers
        self.resolveAgain = resolveAgain
    }
}

// MARK: - Playable Resolved Stream
public struct ResolvedStream: Equatable {
    public let url: URL
    public let format: StreamFormat
    public let headers: [String: String]
    public let quality: String?
    public let title: String?
    public let subtitles: [Subtitle]
    
    public init(
        url: URL,
        format: StreamFormat = .unknown,
        headers: [String: String] = [:],
        quality: String? = nil,
        title: String? = nil,
        subtitles: [Subtitle] = []
    ) {
        self.url = url
        self.format = format
        self.headers = headers
        self.quality = quality
        self.title = title
        self.subtitles = subtitles
    }
}
