import Foundation

// MARK: - Catalog Definition
public struct Catalog: Codable, Identifiable, Equatable {
    public var id: String
    public let name: TranslatedText?
    public let options: CatalogOptions?
    public let features: CatalogFeatures?
    public let kind: String? // "vod" or "iptv" or "directory"
    public let adult: Bool?
    
    public init(
        id: String,
        name: TranslatedText? = nil,
        options: CatalogOptions? = nil,
        features: CatalogFeatures? = nil,
        kind: String? = nil,
        adult: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.options = options
        self.features = features
        self.kind = kind
        self.adult = adult
    }
    
    public var displayName: String {
        name?.value ?? id
    }
}

// MARK: - Catalog Initial Data (in Manifest or Dashboards)
public struct CatalogInitialData: Codable, Equatable {
    public let items: [MediaItem]?
    public let nextCursor: AnyCodableValue?
    
    public init(items: [MediaItem]? = nil, nextCursor: AnyCodableValue? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

// MARK: - Catalog Action Response
public struct CatalogResponse: Codable, Equatable {
    public let items: [MediaItem]
    public let nextCursor: AnyCodableValue?
    
    public init(items: [MediaItem] = [], nextCursor: AnyCodableValue? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}
