import Foundation

// MARK: - TranslatedText
public enum TranslatedText: Codable, Equatable, Hashable, CustomStringConvertible, ExpressibleByStringLiteral {
    case single(String)
    case localized([String: String])
    
    public init(stringLiteral value: String) {
        self = .single(value)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .single(str)
        } else if let dict = try? container.decode([String: String].self) {
            self = .localized(dict)
        } else {
            self = .single("")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let str):
            try container.encode(str)
        case .localized(let dict):
            try container.encode(dict)
        }
    }
    
    public var value: String {
        switch self {
        case .single(let str):
            return str
        case .localized(let dict):
            let lang = Locale.current.language.languageCode?.identifier ?? "de"
            if let localized = dict[lang], !localized.isEmpty { return localized }
            if let en = dict["en"], !en.isEmpty { return en }
            return dict.values.first(where: { !$0.isEmpty }) ?? ""
        }
    }
    
    public var description: String {
        return value
    }
}

// MARK: - AnyCodableValue
public enum AnyCodableValue: Codable, Equatable, Hashable, CustomStringConvertible {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
        } else if let dblVal = try? container.decode(Double.self) {
            self = .double(dblVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            self = .null
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        }
    }
    
    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .null: return nil
        }
    }
    
    public var description: String {
        return stringValue ?? ""
    }
}

// MARK: - Filter Value
public enum FilterValue: Codable, Equatable, Hashable {
    case string(String)
    case keyObject(key: String, value: TranslatedText)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let dict = try? container.decode(FilterObject.self) {
            self = .keyObject(key: dict.key, value: dict.value)
        } else {
            self = .string("")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str):
            try container.encode(str)
        case .keyObject(let key, let value):
            try container.encode(FilterObject(key: key, value: value))
        }
    }
    
    private struct FilterObject: Codable {
        let key: String
        let value: TranslatedText
    }
    
    public var displayTitle: String {
        switch self {
        case .string(let s): return s
        case .keyObject(_, let val): return val.value
        }
    }
    
    public var keyString: String {
        switch self {
        case .string(let s): return s
        case .keyObject(let k, _): return k
        }
    }
}

// MARK: - Filter & Sort Definitions
public struct CatalogOptions: Codable, Equatable {
    public let shape: String? // "portrait", "landscape", "square", "round"
    public let size: String?  // "small", "normal", "large"
    public let displayName: Bool?
    
    public init(shape: String? = nil, size: String? = nil, displayName: Bool? = nil) {
        self.shape = shape
        self.size = size
        self.displayName = displayName
    }
}

public struct CatalogFeatures: Codable, Equatable {
    public let search: CatalogSearchFeature?
    public let sort: [CatalogFeatureSort]?
    public let filter: [CatalogFeatureFilter]?
    
    public init(
        search: CatalogSearchFeature? = nil,
        sort: [CatalogFeatureSort]? = nil,
        filter: [CatalogFeatureFilter]? = nil
    ) {
        self.search = search
        self.sort = sort
        self.filter = filter
    }
}

public struct CatalogSearchFeature: Codable, Equatable {
    public let enabled: Bool?
    
    public init(enabled: Bool? = true) {
        self.enabled = enabled
    }
}

public struct CatalogFeatureSort: Codable, Identifiable, Equatable, Hashable {
    public let id: String
    public let name: TranslatedText?
    
    public init(id: String, name: TranslatedText? = nil) {
        self.id = id
        self.name = name
    }
}

public struct CatalogFeatureFilter: Codable, Identifiable, Equatable {
    public let id: String
    public let name: TranslatedText?
    public let multiselect: Bool?
    public let values: [FilterValue]?
    public let defaultValue: String?
    
    public init(
        id: String,
        name: TranslatedText? = nil,
        multiselect: Bool? = nil,
        values: [FilterValue]? = nil,
        defaultValue: String? = nil
    ) {
        self.id = id
        self.name = name
        self.multiselect = multiselect
        self.values = values
        self.defaultValue = defaultValue
    }
}
