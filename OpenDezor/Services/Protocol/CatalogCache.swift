import Foundation

/// Short-lived in-memory cache for catalog responses.
///
/// Without it every tab switch and every cold start refetches all dashboards over the
/// network, which is what made the app show empty rows for a second on launch. Entries
/// are deliberately short-lived: addon catalogs are live data, and a stale "Trending"
/// row is worse than a brief load.
public final class CatalogCache {
    public static let shared = CatalogCache()

    /// How long an entry stays usable. Long enough to cover tab switching and a quick
    /// relaunch, short enough that a refreshed catalog shows up in the same session.
    public static let lifetime: TimeInterval = 5 * 60

    private struct Entry {
        let items: [MediaItem]
        let nextCursor: AnyCodableValue?
        let storedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let queue = DispatchQueue(label: "org.opendezor.catalogcache", attributes: .concurrent)

    public init() {}

    private func key(endpoint: String, catalogId: String, id: String?, cursor: String?, search: String?) -> String {
        [endpoint, catalogId, id ?? "", cursor ?? "", search ?? ""].joined(separator: "|")
    }

    public func value(
        endpoint: String,
        catalogId: String,
        id: String? = nil,
        cursor: String? = nil,
        search: String? = nil
    ) -> (items: [MediaItem], nextCursor: AnyCodableValue?)? {
        let k = key(endpoint: endpoint, catalogId: catalogId, id: id, cursor: cursor, search: search)
        return queue.sync {
            guard let entry = entries[k],
                  Date().timeIntervalSince(entry.storedAt) < Self.lifetime else { return nil }
            return (entry.items, entry.nextCursor)
        }
    }

    public func store(
        items: [MediaItem],
        nextCursor: AnyCodableValue?,
        endpoint: String,
        catalogId: String,
        id: String? = nil,
        cursor: String? = nil,
        search: String? = nil
    ) {
        // An empty result is usually a transient failure; caching it would hide the
        // catalog for the whole lifetime.
        guard !items.isEmpty else { return }
        let k = key(endpoint: endpoint, catalogId: catalogId, id: id, cursor: cursor, search: search)
        queue.async(flags: .barrier) {
            self.entries[k] = Entry(items: items, nextCursor: nextCursor, storedAt: Date())
        }
    }

    public func clear() {
        queue.async(flags: .barrier) {
            self.entries.removeAll()
        }
    }
}
