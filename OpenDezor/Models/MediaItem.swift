import Foundation

// MARK: - Media Item
public struct MediaItem: Codable, Identifiable, Equatable, Hashable {
    public var id: String {
        if let custom = customId, !custom.isEmpty { return custom }
        if let idKey = ids?["id"], !idKey.isEmpty { return idKey }
        if let tmdb = ids?["tmdb_id"], !tmdb.isEmpty { return "tmdb_\(tmdb)" }
        if let imdb = ids?["imdb_id"], !imdb.isEmpty { return "imdb_\(imdb)" }
        if let title = name?.value, !title.isEmpty { return title }
        return fallbackId
    }
    
    private let fallbackId: String
    public let customId: String?
    public let type: String? // "movie", "series", "channel", "iptv", "directory", "clip", "unknown"
    public let ids: [String: String]?
    public let name: TranslatedText?
    public let originalName: String?
    public let description: TranslatedText?
    public let releaseDate: String?
    public let year: Int?
    public let runtime: Int?
    public let images: ItemImages?
    public let genres: [String]?
    public let cast: [Person]?
    public let director: [Person]?
    public let score: Double?
    public let sources: [MediaSource]?
    public let episodes: [SeriesEpisodeItem]?
    
    // IPTV specific
    public let url: String?
    public let logo: String?
    public let category: String?
    public let group: String?
    public let country: String?
    
    // Directory specific
    public let catalogId: String?
    public let addonId: String?
    
    enum CodingKeys: String, CodingKey {
        case customId = "id"
        case type, ids, name, originalName, description, releaseDate, year, runtime, images, genres, cast, director
        case score = "rating"
        case sources, episodes
        case url, logo, category, group, country
        case catalogId, addonId
    }
    
    public init(
        customId: String? = nil,
        type: String? = "movie",
        ids: [String: String]? = nil,
        name: TranslatedText? = nil,
        originalName: String? = nil,
        description: TranslatedText? = nil,
        releaseDate: String? = nil,
        year: Int? = nil,
        runtime: Int? = nil,
        images: ItemImages? = nil,
        genres: [String]? = nil,
        cast: [Person]? = nil,
        director: [Person]? = nil,
        score: Double? = nil,
        sources: [MediaSource]? = nil,
        episodes: [SeriesEpisodeItem]? = nil,
        url: String? = nil,
        logo: String? = nil,
        category: String? = nil,
        group: String? = nil,
        country: String? = nil,
        catalogId: String? = nil,
        addonId: String? = nil
    ) {
        self.fallbackId = UUID().uuidString
        self.customId = customId
        self.type = type
        self.ids = ids
        self.name = name
        self.originalName = originalName
        self.description = description
        self.releaseDate = releaseDate
        self.year = year
        self.runtime = runtime
        self.images = images
        self.genres = genres
        self.cast = cast
        self.director = director
        self.score = score
        self.sources = sources
        self.episodes = episodes
        self.url = url
        self.logo = logo
        self.category = category
        self.group = group
        self.country = country
        self.catalogId = catalogId
        self.addonId = addonId
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fallbackId = UUID().uuidString
        self.customId = try container.decodeIfPresent(String.self, forKey: .customId)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.ids = try container.decodeIfPresent([String: String].self, forKey: .ids)
        self.name = try container.decodeIfPresent(TranslatedText.self, forKey: .name)
        self.originalName = try container.decodeIfPresent(String.self, forKey: .originalName)
        self.description = try container.decodeIfPresent(TranslatedText.self, forKey: .description)
        self.releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
        self.year = try container.decodeIfPresent(Int.self, forKey: .year)
        self.runtime = try container.decodeIfPresent(Int.self, forKey: .runtime)
        self.images = try container.decodeIfPresent(ItemImages.self, forKey: .images)
        self.genres = try container.decodeIfPresent([String].self, forKey: .genres)
        self.cast = try container.decodeIfPresent([Person].self, forKey: .cast)
        self.director = try container.decodeIfPresent([Person].self, forKey: .director)
        self.score = try container.decodeIfPresent(Double.self, forKey: .score)
        self.sources = try container.decodeIfPresent([MediaSource].self, forKey: .sources)
        self.episodes = try container.decodeIfPresent([SeriesEpisodeItem].self, forKey: .episodes)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.logo = try container.decodeIfPresent(String.self, forKey: .logo)
        self.category = try container.decodeIfPresent(String.self, forKey: .category)
        self.group = try container.decodeIfPresent(String.self, forKey: .group)
        self.country = try container.decodeIfPresent(String.self, forKey: .country)
        self.catalogId = try container.decodeIfPresent(String.self, forKey: .catalogId)
        self.addonId = try container.decodeIfPresent(String.self, forKey: .addonId)
    }
    
    /// Addons routinely send `""` instead of omitting an image field (many addons do this
    /// for most IPTV channels), so empty strings are treated as "no image" — otherwise
    /// the UI keeps a loading spinner up for a URL that can never resolve.
    private static func firstUsable(_ candidates: String?...) -> String? {
        for case let value? in candidates where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return nil
    }

    public var posterUrl: String? {
        Self.firstUsable(images?.poster, logo, images?.backdrop, images?.background)
    }

    public var backdropUrl: String? {
        Self.firstUsable(images?.backdrop, images?.background, images?.poster, logo)
    }

    /// Genuinely wide artwork, for hero banners.
    ///
    /// Unlike `backdropUrl` this never falls back to the portrait poster, so a caller can
    /// tell whether real landscape art exists instead of stretching a poster across the
    /// screen. `banner` is preferred because addons ship it sized for exactly this use.
    public var wideArtworkUrl: String? {
        Self.firstUsable(images?.banner, images?.backdrop, images?.background)
    }

    /// Title treatment supplied by the addon, shown instead of rendering the name as text.
    public var logoUrl: String? {
        Self.firstUsable(images?.logo, logo)
    }

    /// Runtime as `2 Std. 19 Min.`, or nil when the addon sent nothing usable.
    ///
    /// Addons disagree about the unit. Most send minutes (139 for a feature film), but some
    /// send seconds and some milliseconds — printing the raw value produced "800000 Min".
    /// Magnitude is the only signal available, so it is interpreted before formatting:
    /// no real runtime is 1000+ minutes, and nothing plausible is 100000+ seconds.
    public var formattedRuntime: String? {
        guard let runtime, runtime > 0 else { return nil }

        let minutes: Int
        switch runtime {
        case ..<1_000: minutes = runtime            // already minutes
        case ..<100_000: minutes = runtime / 60     // seconds
        default: minutes = runtime / 60_000         // milliseconds
        }

        guard minutes > 0 else { return nil }
        if minutes >= 60 {
            let remaining = minutes % 60
            return remaining == 0
                ? "\(minutes / 60) \(L("Std."))"
                : "\(minutes / 60) \(L("Std.")) \(remaining) \(L("Min."))"
        }
        return "\(minutes) \(L("Min."))"
    }
    
    public var displayName: String {
        if let val = name?.value, !val.isEmpty {
            return val
        }
        return originalName ?? L("Unbekannter Titel")
    }
    
    /// Display name with the decoration addons wrap around channel names removed —
    /// "[[[ TELEKOM SPORT ]]]" or "✦ ✦ NETFLIX STORE" are common in IPTV lists and make
    /// tiles unreadable. Falls back to the raw name if stripping leaves nothing.
    public var cleanDisplayName: String {
        Self.stripDecoration(displayName)
    }

    static func stripDecoration(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "[^\\p{L}\\p{N} .&+:/-]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? raw : cleaned
    }

    /// German display name for a protocol item type. The protocol's type strings are
    /// English identifiers; everything the user sees in this app is German.
    public static func localizedTypeName(_ type: String) -> String {
        switch type.lowercased() {
        case "series": return L("SERIE")
        case "movie": return L("FILM")
        case "iptv", "channel": return L("SENDER")
        case "directory": return L("KATALOG")
        case "person": return "PERSON"
        default: return type.uppercased()
        }
    }

    public var isSeries: Bool {
        type == "series" || (episodes != nil && !(episodes?.isEmpty ?? true))
    }
    
    public var isIPTV: Bool {
        type == "iptv" || type == "channel" || url != nil
    }
    
    public var isDirectory: Bool {
        type == "directory" || catalogId != nil
    }

    /// The `item` response layered over the catalog entry it was requested for. Addons
    /// answer with only what they add — Some addons' IPTV `item` echoes type/ids/name and
    /// nothing else — so replacing the catalog entry outright dropped its stream `url`,
    /// logo and artwork ("No sources found", blank banner). Detail fields win when present.
    public func filled(from catalog: MediaItem) -> MediaItem {
        func pick(_ detail: String?, _ fallback: String?) -> String? {
            guard let detail, !detail.trimmingCharacters(in: .whitespaces).isEmpty else { return fallback }
            return detail
        }
        let mergedImages: ItemImages? = {
            guard let detail = images else { return catalog.images }
            guard let base = catalog.images else { return detail }
            return ItemImages(
                poster: pick(detail.poster, base.poster),
                backdrop: pick(detail.backdrop, base.backdrop),
                background: pick(detail.background, base.background),
                logo: pick(detail.logo, base.logo),
                banner: pick(detail.banner, base.banner)
            )
        }()
        return MediaItem(
            // Keep the catalog's identity: favourites, history and resume keys hang off it.
            customId: catalog.id,
            type: type ?? catalog.type,
            ids: (catalog.ids ?? [:]).merging(ids ?? [:]) { _, new in new },
            name: name ?? catalog.name,
            originalName: originalName ?? catalog.originalName,
            description: description ?? catalog.description,
            releaseDate: releaseDate ?? catalog.releaseDate,
            year: year ?? catalog.year,
            runtime: runtime ?? catalog.runtime,
            images: mergedImages,
            genres: genres ?? catalog.genres,
            cast: cast ?? catalog.cast,
            director: director ?? catalog.director,
            score: score ?? catalog.score,
            sources: sources ?? catalog.sources,
            episodes: episodes ?? catalog.episodes,
            url: pick(url, catalog.url),
            logo: pick(logo, catalog.logo),
            category: category ?? catalog.category,
            group: group ?? catalog.group,
            country: country ?? catalog.country,
            catalogId: catalogId ?? catalog.catalogId,
            addonId: addonId ?? catalog.addonId
        )
    }
}

// MARK: - Item Images
public struct ItemImages: Codable, Equatable, Hashable {
    public let poster: String?
    public let backdrop: String?
    public let background: String?
    public let logo: String?
    public let banner: String?
    
    public init(
        poster: String? = nil,
        backdrop: String? = nil,
        background: String? = nil,
        logo: String? = nil,
        banner: String? = nil
    ) {
        self.poster = poster
        self.backdrop = backdrop
        self.background = background
        self.logo = logo
        self.banner = banner
    }
}

// MARK: - Person
public struct Person: Codable, Equatable, Hashable {
    public let name: String?
    public let character: String?
    public let role: String?
    public let poster: String?
    
    public init(name: String? = nil, character: String? = nil, role: String? = nil, poster: String? = nil) {
        self.name = name
        self.character = character
        self.role = role
        self.poster = poster
    }
}

// MARK: - Series Episode
public struct SeriesEpisodeItem: Codable, Identifiable, Equatable, Hashable {
    public var id: String {
        if let epId = ids?["id"], !epId.isEmpty { return epId }
        return "s\(season)_e\(episode)"
    }
    public let ids: [String: String]?
    public let name: TranslatedText?
    public let originalName: String?
    public let description: TranslatedText?
    public let releaseDate: String?
    public let poster: String?
    public let season: Int
    public let episode: Int
    public let sources: [MediaSource]?
    
    public init(
        ids: [String: String]? = nil,
        name: TranslatedText? = nil,
        originalName: String? = nil,
        description: TranslatedText? = nil,
        releaseDate: String? = nil,
        poster: String? = nil,
        season: Int,
        episode: Int,
        sources: [MediaSource]? = nil
    ) {
        self.ids = ids
        self.name = name
        self.originalName = originalName
        self.description = description
        self.releaseDate = releaseDate
        self.poster = poster
        self.season = season
        self.episode = episode
        self.sources = sources
    }
    
    public var displayName: String {
        if let val = name?.value, !val.isEmpty {
            return val
        }
        return "Episode \(episode)"
    }
}
