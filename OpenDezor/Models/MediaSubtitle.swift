import Foundation

// MARK: - Subtitle
public struct Subtitle: Codable, Identifiable, Equatable, Hashable {
    public var id: String { customId ?? url }
    public let customId: String?
    public let name: String?
    public let language: String?
    public let type: String? // "srt", "vtt", "ttml", "subrip", "webvtt"
    public let url: String
    
    enum CodingKeys: String, CodingKey {
        case customId = "id"
        case name, language, type, url
    }
    
    public init(
        customId: String? = nil,
        name: String? = nil,
        language: String? = nil,
        type: String? = nil,
        url: String
    ) {
        self.customId = customId
        self.name = name
        self.language = language
        self.type = type
        self.url = url
    }
    
    public var displayLanguage: String {
        if let lang = language, !lang.isEmpty {
            return lang.uppercased()
        }
        if let n = name, !n.isEmpty {
            return n
        }
        return L("Untertitel")
    }

    /// Declared format, from the addon's `type` field or the URL suffix. Distinct from
    /// `SubtitleParser`, which sniffs the downloaded *content* in order to parse cues.
    public var format: SubtitleFormat {
        if let t = type?.lowercased() {
            if t.contains("vtt") || t.contains("webvtt") { return .vtt }
            if t.contains("srt") || t.contains("subrip") { return .srt }
            if t.contains("ttml") { return .ttml }
        }
        let lowerUrl = url.lowercased()
        if lowerUrl.hasSuffix(".vtt") { return .vtt }
        if lowerUrl.hasSuffix(".srt") { return .srt }
        if lowerUrl.hasSuffix(".ttml") || lowerUrl.hasSuffix(".xml") { return .ttml }
        return .unknown
    }
}

public enum SubtitleFormat: String, Codable, Equatable, Hashable {
    case srt
    case vtt
    case ttml
    case unknown
}
