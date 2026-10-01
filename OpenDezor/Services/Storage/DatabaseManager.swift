import Foundation
import SQLite3

public class DatabaseManager {
    public static let shared = DatabaseManager()
    
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "org.opendezor.database", qos: .userInitiated)
    
    public init(inMemory: Bool = false) {
        if inMemory {
            openDatabase(path: ":memory:")
        } else {
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            let documentsDirectory = paths.first ?? FileManager.default.temporaryDirectory
            let dbUrl = documentsDirectory.appendingPathComponent("opendezor.sqlite3")
            openDatabase(path: dbUrl.path)
        }
        createTables()
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    private func openDatabase(path: String) {
        if sqlite3_open(path, &db) != SQLITE_OK {
            print("Error opening database at \(path)")
            return
        }
        // WAL lets the periodic history writes during playback proceed without blocking
        // reads from the UI. NORMAL is the matching durability level for WAL: a crash can
        // cost the last write, which for a playback position is acceptable.
        // In-memory databases do not support WAL, so this is best-effort.
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
    }
    
    private func createTables() {
        let createAddons = """
        CREATE TABLE IF NOT EXISTS addons (
            id TEXT PRIMARY KEY,
            url TEXT NOT NULL,
            name TEXT NOT NULL,
            isEnabled INTEGER NOT NULL,
            addedAt REAL NOT NULL,
            iconUrl TEXT,
            description TEXT
        );
        """
        
        let createHistory = """
        CREATE TABLE IF NOT EXISTS history (
            id TEXT PRIMARY KEY,
            mediaItemId TEXT NOT NULL,
            title TEXT NOT NULL,
            posterUrl TEXT,
            itemType TEXT NOT NULL,
            season INTEGER,
            episode INTEGER,
            lastPositionSeconds REAL NOT NULL,
            durationSeconds REAL NOT NULL,
            updatedAt REAL NOT NULL,
            isCompleted INTEGER NOT NULL
        );
        """
        
        let createFavorites = """
        CREATE TABLE IF NOT EXISTS favorites (
            id TEXT PRIMARY KEY,
            mediaItemId TEXT NOT NULL,
            title TEXT NOT NULL,
            posterUrl TEXT,
            itemType TEXT NOT NULL,
            addedAt REAL NOT NULL
        );
        """
        
        let createSearch = """
        CREATE TABLE IF NOT EXISTS search_history (
            query TEXT PRIMARY KEY,
            searchedAt REAL NOT NULL
        );
        """
        
        let createCustomIPTV = """
        CREATE TABLE IF NOT EXISTS custom_iptv (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            url TEXT NOT NULL,
            logo TEXT,
            category TEXT,
            groupTitle TEXT,
            country TEXT
        );
        """

        // Lookups run on these columns for every history read and every favourite check;
        // without indexes SQLite scans the whole table each time.
        let createIndexes = """
        CREATE INDEX IF NOT EXISTS idx_history_mediaItemId ON history(mediaItemId);
        CREATE INDEX IF NOT EXISTS idx_history_updatedAt ON history(updatedAt DESC);
        CREATE INDEX IF NOT EXISTS idx_favorites_mediaItemId ON favorites(mediaItemId);
        CREATE INDEX IF NOT EXISTS idx_search_searchedAt ON search_history(searchedAt DESC);
        """
        
        run(createAddons)
        run(createHistory)
        run(createFavorites)
        run(createSearch)
        run(createCustomIPTV)
        executeScript(sql: createIndexes)
        // Added after the first release; existing installs get the column here.
        addColumnIfMissing(table: "history", column: "itemJSON", type: "TEXT")
        addColumnIfMissing(table: "favorites", column: "itemJSON", type: "TEXT")
    }

    private func addColumnIfMissing(table: String, column: String, type: String) {
        let existing = query("PRAGMA table_info(\(table));") { Self.text($0, 1) }
        guard !existing.contains(column) else { return }
        run("ALTER TABLE \(table) ADD COLUMN \(column) \(type);")
    }

    private static func encodeItem(_ item: MediaItem?) -> String? {
        guard let item, let data = try? JSONEncoder().encode(item) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeItem(_ stmt: OpaquePointer?, _ i: Int32) -> MediaItem? {
        guard let json = optionalText(stmt, i) else { return nil }
        return try? JSONDecoder().decode(MediaItem.self, from: Data(json.utf8))
    }
    
    /// Runs a script that may contain several statements. `run` prepares a single
    /// statement and would silently drop everything after the first semicolon.
    private func executeScript(sql: String) {
        queue.sync {
            var errorPointer: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &errorPointer) != SQLITE_OK, let errorPointer {
                print("Error executing SQL script: \(String(cString: errorPointer))")
                sqlite3_free(errorPointer)
            }
        }
    }

    // MARK: - Statement plumbing
    //
    // Every CRUD method below is prepare → bind → step → finalize on the serial queue.
    // That skeleton lived inline in each of them, with a five-line if/else per nullable
    // column; it is written once here instead.

    /// SQLite needs to know whether it may keep the bytes we hand it. The old code passed
    /// `nil` (SQLITE_STATIC), promising they outlive the step — which `(x as NSString)
    /// .utf8String` does *not*: that temporary can be released before `sqlite3_step` runs.
    /// TRANSIENT tells SQLite to take its own copy.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        guard let value else { sqlite3_bind_null(stmt, index); return }
        sqlite3_bind_text(stmt, index, value, -1, Self.transient)
    }

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        guard let value else { sqlite3_bind_null(stmt, index); return }
        sqlite3_bind_int(stmt, index, Int32(value))
    }

    /// One writing statement.
    private func run(_ sql: String, _ bindValues: (OpaquePointer?) -> Void = { _ in }) {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("Error preparing SQL: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            defer { sqlite3_finalize(stmt) }
            bindValues(stmt)
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("Error executing SQL: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    /// One statement stepped once per element, so an import does not re-prepare per row.
    private func runEach<T>(_ sql: String, _ items: [T], _ bindValues: (OpaquePointer?, T) -> Void) {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            for item in items {
                sqlite3_reset(stmt)
                bindValues(stmt, item)
                sqlite3_step(stmt)
            }
        }
    }

    /// One reading statement; `row` decodes a single row.
    private func query<T>(_ sql: String, _ row: (OpaquePointer?) -> T) -> [T] {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            var result: [T] = []
            while sqlite3_step(stmt) == SQLITE_ROW { result.append(row(stmt)) }
            return result
        }
    }

    private static func text(_ stmt: OpaquePointer?, _ i: Int32) -> String {
        sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
    }
    private static func optionalText(_ stmt: OpaquePointer?, _ i: Int32) -> String? {
        sqlite3_column_text(stmt, i).map { String(cString: $0) }
    }
    private static func optionalInt(_ stmt: OpaquePointer?, _ i: Int32) -> Int? {
        sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, i))
    }
    private static func date(_ stmt: OpaquePointer?, _ i: Int32) -> Date {
        Date(timeIntervalSince1970: sqlite3_column_double(stmt, i))
    }

    // MARK: - Addons CRUD
    public func getAllAddons() -> [SavedAddon] {
        query("SELECT id, url, name, isEnabled, addedAt, iconUrl, description FROM addons ORDER BY addedAt DESC;") { stmt in
            SavedAddon(
                id: Self.text(stmt, 0),
                url: Self.text(stmt, 1),
                name: Self.text(stmt, 2),
                isEnabled: sqlite3_column_int(stmt, 3) != 0,
                addedAt: Self.date(stmt, 4),
                iconUrl: Self.optionalText(stmt, 5),
                description: Self.optionalText(stmt, 6)
            )
        }
    }

    public func saveAddon(_ addon: SavedAddon) {
        run("INSERT OR REPLACE INTO addons (id, url, name, isEnabled, addedAt, iconUrl, description) VALUES (?, ?, ?, ?, ?, ?, ?);") { stmt in
            bind(stmt, 1, addon.id)
            bind(stmt, 2, addon.url)
            bind(stmt, 3, addon.name)
            sqlite3_bind_int(stmt, 4, addon.isEnabled ? 1 : 0)
            sqlite3_bind_double(stmt, 5, addon.addedAt.timeIntervalSince1970)
            bind(stmt, 6, addon.iconUrl)
            bind(stmt, 7, addon.description)
        }
    }

    public func deleteAddon(id: String) {
        run("DELETE FROM addons WHERE id = ?;") { bind($0, 1, id) }
    }

    // MARK: - Watch History CRUD
    public func getWatchHistory() -> [WatchHistoryItem] {
        query("SELECT id, mediaItemId, title, posterUrl, itemType, season, episode, lastPositionSeconds, durationSeconds, updatedAt, isCompleted, itemJSON FROM history ORDER BY updatedAt DESC LIMIT 100;") { stmt in
            WatchHistoryItem(
                mediaItemId: Self.text(stmt, 1),
                title: Self.text(stmt, 2),
                posterUrl: Self.optionalText(stmt, 3),
                itemType: Self.text(stmt, 4),
                season: Self.optionalInt(stmt, 5),
                episode: Self.optionalInt(stmt, 6),
                lastPositionSeconds: sqlite3_column_double(stmt, 7),
                durationSeconds: sqlite3_column_double(stmt, 8),
                updatedAt: Self.date(stmt, 9),
                isCompleted: sqlite3_column_int(stmt, 10) != 0,
                item: Self.decodeItem(stmt, 11)
            )
        }
    }

    public func saveHistoryItem(_ item: WatchHistoryItem) {
        run("INSERT OR REPLACE INTO history (id, mediaItemId, title, posterUrl, itemType, season, episode, lastPositionSeconds, durationSeconds, updatedAt, isCompleted, itemJSON) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);") { stmt in
            bind(stmt, 1, item.id)
            bind(stmt, 2, item.mediaItemId)
            bind(stmt, 3, item.title)
            bind(stmt, 4, item.posterUrl)
            bind(stmt, 5, item.itemType)
            bind(stmt, 6, item.season)
            bind(stmt, 7, item.episode)
            sqlite3_bind_double(stmt, 8, item.lastPositionSeconds)
            sqlite3_bind_double(stmt, 9, item.durationSeconds)
            sqlite3_bind_double(stmt, 10, item.updatedAt.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 11, item.isCompleted ? 1 : 0)
            bind(stmt, 12, Self.encodeItem(item.item))
        }
    }

    public func deleteHistoryItem(id: String) {
        run("DELETE FROM history WHERE id = ?;") { bind($0, 1, id) }
    }

    public func clearAllHistory() {
        run("DELETE FROM history;")
    }

    // MARK: - Favorites CRUD
    public func getAllFavorites() -> [FavoriteItem] {
        query("SELECT id, mediaItemId, title, posterUrl, itemType, addedAt, itemJSON FROM favorites ORDER BY addedAt DESC;") { stmt in
            FavoriteItem(
                mediaItemId: Self.text(stmt, 1),
                title: Self.text(stmt, 2),
                posterUrl: Self.optionalText(stmt, 3),
                itemType: Self.text(stmt, 4),
                addedAt: Self.date(stmt, 5),
                item: Self.decodeItem(stmt, 6)
            )
        }
    }

    public func saveFavorite(_ fav: FavoriteItem) {
        run("INSERT OR REPLACE INTO favorites (id, mediaItemId, title, posterUrl, itemType, addedAt, itemJSON) VALUES (?, ?, ?, ?, ?, ?, ?);") { stmt in
            bind(stmt, 1, fav.id)
            bind(stmt, 2, fav.mediaItemId)
            bind(stmt, 3, fav.title)
            bind(stmt, 4, fav.posterUrl)
            bind(stmt, 5, fav.itemType)
            sqlite3_bind_double(stmt, 6, fav.addedAt.timeIntervalSince1970)
            bind(stmt, 7, Self.encodeItem(fav.item))
        }
    }

    public func deleteFavorite(mediaItemId: String) {
        run("DELETE FROM favorites WHERE mediaItemId = ?;") { bind($0, 1, mediaItemId) }
    }

    // MARK: - Search History CRUD
    public func getSearchHistory() -> [String] {
        query("SELECT query FROM search_history ORDER BY searchedAt DESC LIMIT 20;") { Self.text($0, 0) }
    }

    public func addSearchQuery(_ query: String) {
        run("INSERT OR REPLACE INTO search_history (query, searchedAt) VALUES (?, ?);") { stmt in
            bind(stmt, 1, query)
            sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        }
    }

    public func clearSearchHistory() {
        run("DELETE FROM search_history;")
    }

    // MARK: - Custom IPTV Playlist Channels
    public func getAllCustomIPTV() -> [MediaItem] {
        query("SELECT id, name, url, logo, category, groupTitle, country FROM custom_iptv;") { stmt in
            let id = Self.text(stmt, 0)
            let logo = Self.optionalText(stmt, 3)
            return MediaItem(
                customId: id,
                type: "iptv",
                ids: ["id": id],
                name: .single(Self.text(stmt, 1)),
                images: ItemImages(poster: logo, backdrop: logo, background: nil, logo: logo),
                url: Self.text(stmt, 2),
                logo: logo,
                category: Self.optionalText(stmt, 4),
                group: Self.optionalText(stmt, 5),
                country: Self.optionalText(stmt, 6)
            )
        }
    }

    public func saveCustomIPTV(_ items: [MediaItem]) {
        // A channel with no stream URL is unplayable, so it is never stored.
        let playable = items.filter { !($0.url ?? "").isEmpty }
        runEach("INSERT OR REPLACE INTO custom_iptv (id, name, url, logo, category, groupTitle, country) VALUES (?, ?, ?, ?, ?, ?, ?);", playable) { stmt, item in
            bind(stmt, 1, item.id)
            bind(stmt, 2, item.displayName)
            bind(stmt, 3, item.url)
            bind(stmt, 4, item.logo)
            bind(stmt, 5, item.category)
            bind(stmt, 6, item.group)
            bind(stmt, 7, item.country)
        }
    }

    public func deleteCustomIPTV(id: String) {
        run("DELETE FROM custom_iptv WHERE id = ?;") { bind($0, 1, id) }
    }

    public func clearAllCustomIPTV() {
        run("DELETE FROM custom_iptv;")
    }
}
