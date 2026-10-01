import Foundation

// MARK: - Image Definition
public typealias MediaImage = String

// MARK: - Addon Manifest
public struct AddonManifest: Codable, Identifiable, Equatable {
    public let id: String
    public let name: TranslatedText
    public let version: String?
    public let icon: MediaImage?
    public let description: TranslatedText?
    public let adult: Bool?
    public let author: String?
    public let email: String?
    public let homepage: String?
    public let endpoints: [String]?
    public let actions: [String]?
    public let catalogs: [Catalog]?
    public let pages: [MediaPage]?
    public let urlPatterns: [String]?
    public let types: [String]?
    public let flags: [String: AnyCodableValue]?
    
    public init(
        id: String,
        name: TranslatedText,
        version: String? = nil,
        icon: MediaImage? = nil,
        description: TranslatedText? = nil,
        adult: Bool? = nil,
        author: String? = nil,
        email: String? = nil,
        homepage: String? = nil,
        endpoints: [String]? = nil,
        actions: [String]? = nil,
        catalogs: [Catalog]? = nil,
        pages: [MediaPage]? = nil,
        urlPatterns: [String]? = nil,
        types: [String]? = nil,
        flags: [String: AnyCodableValue]? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.icon = icon
        self.description = description
        self.adult = adult
        self.author = author
        self.email = email
        self.homepage = homepage
        self.endpoints = endpoints
        self.actions = actions
        self.catalogs = catalogs
        self.pages = pages
        self.urlPatterns = urlPatterns
        self.types = types
        self.flags = flags
    }
    
    public var displayName: String {
        name.value.isEmpty ? id : name.value
    }
}

// MARK: - Page & Dashboard
public struct MediaPage: Codable, Identifiable, Equatable {
    /// Real-world manifests ship pages without an `id`, so it is
    /// optional here and synthesized from the name or position when missing.
    public var id: String {
        customId ?? name?.value ?? "page-\(dashboards?.first?.id ?? "0")"
    }
    public let customId: String?
    public let name: TranslatedText?
    public let dashboards: [DashboardItem]?

    enum CodingKeys: String, CodingKey {
        case customId = "id"
        case name, dashboards
    }

    public init(id: String? = nil, name: TranslatedText? = nil, dashboards: [DashboardItem]? = nil) {
        self.customId = id
        self.name = name
        self.dashboards = dashboards
    }
}

public struct DashboardItem: Codable, Identifiable, Equatable {
    public var id: String {
        customId ?? catalogId ?? name?.value ?? UUID().uuidString
    }
    public let customId: String?
    public let type: String? // "directory", "movie", "series", "channel", "iptv"
    public let catalogId: String?
    public let addonId: String?
    public let name: TranslatedText?
    public let options: CatalogOptions?
    public let features: CatalogFeatures?
    public let initialData: CatalogInitialData?
    
    enum CodingKeys: String, CodingKey {
        case customId = "id"
        case type, catalogId, addonId, name, options, features, initialData
    }
    
    public init(
        customId: String? = nil,
        type: String? = nil,
        catalogId: String? = nil,
        addonId: String? = nil,
        name: TranslatedText? = nil,
        options: CatalogOptions? = nil,
        features: CatalogFeatures? = nil,
        initialData: CatalogInitialData? = nil
    ) {
        self.customId = customId
        self.type = type
        self.catalogId = catalogId
        self.addonId = addonId
        self.name = name
        self.options = options
        self.features = features
        self.initialData = initialData
    }
}
