import Foundation

// MARK: - Saved Addon
public struct SavedAddon: Codable, Identifiable, Equatable {
    public let id: String
    public let url: String
    public var name: String
    public var isEnabled: Bool
    public let addedAt: Date
    public var iconUrl: String?
    public var description: String?
    
    public init(
        id: String,
        url: String,
        name: String,
        isEnabled: Bool = true,
        addedAt: Date = Date(),
        iconUrl: String? = nil,
        description: String? = nil
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.isEnabled = isEnabled
        self.addedAt = addedAt
        self.iconUrl = iconUrl
        self.description = description
    }
}

// MARK: - Watch History Item
public struct WatchHistoryItem: Codable, Identifiable, Equatable {
    public var id: String { mediaItemId + (episodeKey ?? "") }
    public let mediaItemId: String
    public let title: String
    public let posterUrl: String?
    public let itemType: String
    public let season: Int?
    public let episode: Int?
    public var lastPositionSeconds: Double
    public var durationSeconds: Double
    public var updatedAt: Date
    public var isCompleted: Bool
    /// The full catalog entry the row was created from. Without it the row can only be
    /// rebuilt as `ids: ["id": mediaItemId]`, which addons do not recognise — so
    /// "Weiterschauen" found no sources and an IPTV channel lost its stream URL.
    public var item: MediaItem?
    
    public init(
        mediaItemId: String,
        title: String,
        posterUrl: String? = nil,
        itemType: String = "movie",
        season: Int? = nil,
        episode: Int? = nil,
        lastPositionSeconds: Double = 0,
        durationSeconds: Double = 0,
        updatedAt: Date = Date(),
        isCompleted: Bool = false,
        item: MediaItem? = nil
    ) {
        self.mediaItemId = mediaItemId
        self.title = title
        self.posterUrl = posterUrl
        self.itemType = itemType
        self.season = season
        self.episode = episode
        self.lastPositionSeconds = lastPositionSeconds
        self.durationSeconds = durationSeconds
        self.updatedAt = updatedAt
        self.isCompleted = isCompleted || (durationSeconds > 0 && (lastPositionSeconds / durationSeconds) >= 0.90)
        self.item = item
    }
    
    /// Suffix that separates episodes of the same series in the history table.
    /// Readers must build it exactly the same way or resuming never matches — hence the
    /// single shared implementation.
    public static func episodeKey(season: Int?, episode: Int?) -> String? {
        guard let season, let episode else { return nil }
        return "_s\(season)e\(episode)"
    }

    public var episodeKey: String? {
        Self.episodeKey(season: season, episode: episode)
    }
    
    public var progressRatio: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(lastPositionSeconds / durationSeconds, 0), 1)
    }

    /// A stored row rendered back as a catalog item: the saved entry when there is one
    /// (rows written before it was stored have none), keyed to this row's id.
    public var asMediaItem: MediaItem {
        Self.restore(item, id: mediaItemId, title: title, posterUrl: posterUrl, type: itemType)
    }

    static func restore(_ item: MediaItem?, id: String, title: String, posterUrl: String?, type: String) -> MediaItem {
        let stub = MediaItem(
            customId: id,
            type: type,
            ids: ["id": id],
            name: .single(title),
            images: ItemImages(poster: posterUrl, backdrop: posterUrl)
        )
        return item?.filled(from: stub) ?? stub
    }
}

// MARK: - Favorite Item
public struct FavoriteItem: Codable, Identifiable, Equatable {
    public var id: String { mediaItemId }
    public let mediaItemId: String
    public let title: String
    public let posterUrl: String?
    public let itemType: String
    public let addedAt: Date
    /// See `WatchHistoryItem.item`.
    public var item: MediaItem?
    
    public init(
        mediaItemId: String,
        title: String,
        posterUrl: String? = nil,
        itemType: String = "movie",
        addedAt: Date = Date(),
        item: MediaItem? = nil
    ) {
        self.mediaItemId = mediaItemId
        self.title = title
        self.posterUrl = posterUrl
        self.itemType = itemType
        self.addedAt = addedAt
        self.item = item
    }

    /// See `WatchHistoryItem.asMediaItem`.
    public var asMediaItem: MediaItem {
        WatchHistoryItem.restore(item, id: mediaItemId, title: title, posterUrl: posterUrl, type: itemType)
    }
}

// MARK: - App Settings
// MARK: - Appearance & Language Preferences

/// Language for both the interface and the `language`/`region` fields sent to addons.
public enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case german = "de"
    case english = "en"

    public var id: String { rawValue }

    /// Two-letter code actually sent to addons and to dezor.net.
    public var protocolCode: String {
        switch self {
        case .system:
            let code = Locale.current.language.languageCode?.identifier ?? "de"
            return AppLanguage(rawValue: code) != nil ? code : "en"
        case .german: return "de"
        case .english: return "en"
        }
    }

    /// Region sent alongside the language. Addons use it for geo-specific catalogs.
    public var regionCode: String {
        switch self {
        case .system: return Locale.current.region?.identifier ?? "DE"
        case .german: return "DE"
        case .english: return "US"
        }
    }

    /// Which translation table the interface uses. `system` follows the device.
    public var interfaceCode: String {
        protocolCode == "de" ? "de" : "en"
    }

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .german: return "Deutsch"
        case .english: return "English"
        }
    }

    public var flag: String {
        switch self {
        case .system: return "globe"
        case .german: return "🇩🇪"
        case .english: return "🇺🇸"
        }
    }
}

public enum AppColorScheme: String, Codable, CaseIterable, Identifiable {
    case system, dark, light
    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .dark: return L("Dunkel")
        case .light: return L("Hell")
        }
    }
}

/// Named accent pairs. Stored by name so the choice survives encoding.
public enum AppAccent: String, Codable, CaseIterable, Identifiable {
    case indigo, crimson, emerald, amber, violet
    public var id: String { rawValue }
}

/// Every default lives on its property declaration and nowhere else. The memberwise init
/// is synthesised from them, and `init(from:)` — which lives in the extension below so the
/// synthesis is not suppressed — starts from those same defaults.
public struct AppSettings: Codable, Equatable {
    public var autoPlayNextEpisode: Bool = true
    public var defaultQuality: String = "1080p"
    public var preferredAudioLanguage: String = "de"
    public var preferredSubtitleLanguage: String = "de"
    public var searchHistoryLimit: Int = 20
    public var maxCacheSizeMB: Int = 500
    /// Route artwork through Dezor's image cache (smaller images, but every image URL
    /// is sent to dezor.net). Off keeps requests
    /// between the device and the addon's own host.
    public var useImageProxy: Bool = true
    public var language: AppLanguage = .system
    public var colorScheme: AppColorScheme = .dark
    public var accent: AppAccent = .indigo
    public var requireBiometrics: Bool = false
    public var vpnEnabled: Bool = false
    /// Connect the VPN on every cold start. Films and series only play through the VPN,
    /// so this spares the tap on the start screen.
    public var vpnAutoConnect: Bool = false
    public var selectedVpnServerId: String = "auto"
    public var customProxyHost: String = ""
    public var customProxyPort: Int = 8080
    public var customProxyType: String = "http"
}

public extension AppSettings {
    // Settings persisted before any of these fields existed still decode: `self.init()`
    // seeds every property with its declared default, and each key only overwrites it
    // when the stored blob actually carries one.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoPlayNextEpisode = try c.decodeIfPresent(Bool.self, forKey: .autoPlayNextEpisode) ?? autoPlayNextEpisode
        defaultQuality = try c.decodeIfPresent(String.self, forKey: .defaultQuality) ?? defaultQuality
        preferredAudioLanguage = try c.decodeIfPresent(String.self, forKey: .preferredAudioLanguage) ?? preferredAudioLanguage
        preferredSubtitleLanguage = try c.decodeIfPresent(String.self, forKey: .preferredSubtitleLanguage) ?? preferredSubtitleLanguage
        searchHistoryLimit = try c.decodeIfPresent(Int.self, forKey: .searchHistoryLimit) ?? searchHistoryLimit
        maxCacheSizeMB = try c.decodeIfPresent(Int.self, forKey: .maxCacheSizeMB) ?? maxCacheSizeMB
        useImageProxy = try c.decodeIfPresent(Bool.self, forKey: .useImageProxy) ?? useImageProxy
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? language
        colorScheme = try c.decodeIfPresent(AppColorScheme.self, forKey: .colorScheme) ?? colorScheme
        accent = try c.decodeIfPresent(AppAccent.self, forKey: .accent) ?? accent
        requireBiometrics = try c.decodeIfPresent(Bool.self, forKey: .requireBiometrics) ?? requireBiometrics
        vpnEnabled = try c.decodeIfPresent(Bool.self, forKey: .vpnEnabled) ?? vpnEnabled
        vpnAutoConnect = try c.decodeIfPresent(Bool.self, forKey: .vpnAutoConnect) ?? vpnAutoConnect
        selectedVpnServerId = try c.decodeIfPresent(String.self, forKey: .selectedVpnServerId) ?? selectedVpnServerId
        customProxyHost = try c.decodeIfPresent(String.self, forKey: .customProxyHost) ?? customProxyHost
        customProxyPort = try c.decodeIfPresent(Int.self, forKey: .customProxyPort) ?? customProxyPort
        customProxyType = try c.decodeIfPresent(String.self, forKey: .customProxyType) ?? customProxyType
    }
}
