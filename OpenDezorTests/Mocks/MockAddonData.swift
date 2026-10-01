import Foundation
@testable import OpenDezor

// MARK: - Mock URL Protocol for Intercepting Network Requests
public class MockURLProtocol: URLProtocol {
    public static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    public static var lastRequest: URLRequest?
    public static var recordedRequests: [URLRequest] = []
    
    public static func reset() {
        requestHandler = nil
        lastRequest = nil
        recordedRequests.removeAll()
    }
    
    public override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    public override func startLoading() {
        MockURLProtocol.lastRequest = request
        MockURLProtocol.recordedRequests.append(request)
        
        guard let handler = MockURLProtocol.requestHandler else {
            let error = NSError(domain: "MockURLProtocol", code: -1, userInfo: [NSLocalizedDescriptionKey: "No handler configured"])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    public override func stopLoading() {}
}

// MARK: - URLRequest Body Extractor Helper
extension URLRequest {
    public var extractedBodyData: Data? {
        if let body = httpBody { return body }
        if let stream = httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }
            return data.isEmpty ? nil : data
        }
        return nil
    }
}

// MARK: - Mock Session Helper
public enum MockSessionFactory {
    public static func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

// MARK: - Realistic MediaHub JSON Fixtures
public enum MockAddonData {
    public static let sampleManifestJSON = """
    {
        "id": "demo-addon.example",
        "name": {
            "en": "Demo Hub",
            "de": "Demo Medienzentrum"
        },
        "version": "1.4.2",
        "icon": "https://demo-addon.example/icon.png",
        "description": {
            "en": "Movies, Series and Live TV",
            "de": "Filme, Serien und Live-TV Mediathek"
        },
        "adult": false,
        "author": "Dezor Team",
        "endpoints": ["https://demo-addon.example/api"],
        "actions": ["catalog", "item", "source", "subtitle", "resolve"],
        "catalogs": [
            {
                "id": "movies_popular",
                "name": {
                    "de": "Beliebte Filme",
                    "en": "Popular Movies"
                },
                "kind": "vod",
                "options": {
                    "shape": "portrait",
                    "size": "normal",
                    "displayName": true
                },
                "features": {
                    "search": { "enabled": true },
                    "sort": [
                        { "id": "trending", "name": "Trending" },
                        { "id": "rating", "name": "Beste Bewertung" }
                    ],
                    "filter": [
                        {
                            "id": "genre",
                            "name": "Genre",
                            "multiselect": false,
                            "values": [
                                { "key": "action", "value": "Action" },
                                { "key": "scifi", "value": "Science Fiction" },
                                "Drama"
                            ],
                            "defaultValue": "action"
                        }
                    ]
                }
            },
            {
                "id": "series_trending",
                "name": "Trending Serien",
                "kind": "vod",
                "options": {
                    "shape": "portrait",
                    "size": "normal"
                }
            },
            {
                "id": "iptv_germany",
                "name": "Deutsches Live-TV",
                "kind": "iptv",
                "options": {
                    "shape": "landscape",
                    "size": "small"
                }
            }
        ],
        "pages": [
            {
                "id": "home",
                "name": "Startseite",
                "dashboards": [
                    {
                        "id": "dash_movies",
                        "type": "movie",
                        "catalogId": "movies_popular",
                        "name": "Top Filme"
                    }
                ]
            }
        ]
    }
    """
    
    public static let sampleCatalogMoviesResponseJSON = """
    {
        "items": [
            {
                "id": "movie_101",
                "type": "movie",
                "ids": {
                    "tmdb_id": "550",
                    "imdb_id": "tt0137523"
                },
                "name": {
                    "de": "Fight Club",
                    "en": "Fight Club"
                },
                "originalName": "Fight Club",
                "description": "Ein unzufriedener Angestellter gründet einen geheimen Boxclub.",
                "releaseDate": "1999-10-15",
                "year": 1999,
                "runtime": 139,
                "rating": 8.8,
                "images": {
                    "poster": "https://image.tmdb.org/t/p/w500/fight_club.jpg",
                    "backdrop": "https://image.tmdb.org/t/p/w1280/fight_club_bg.jpg"
                },
                "genres": ["Drama", "Thriller"],
                "cast": [
                    { "name": "Edward Norton", "character": "The Narrator" },
                    { "name": "Brad Pitt", "character": "Tyler Durden" }
                ],
                "director": [
                    { "name": "David Fincher", "role": "Director" }
                ]
            },
            {
                "id": "movie_102",
                "type": "movie",
                "name": "Inception",
                "year": 2010,
                "runtime": 148,
                "images": {
                    "poster": "https://image.tmdb.org/t/p/w500/inception.jpg"
                }
            }
        ],
        "nextCursor": "page_2_cursor_token"
    }
    """
    
    public static let sampleItemDetailSeriesResponseJSON = """
    {
        "id": "series_201",
        "type": "series",
        "ids": {
            "tmdb_id": "1396",
            "imdb_id": "tt0903747"
        },
        "name": {
            "de": "Breaking Bad",
            "en": "Breaking Bad"
        },
        "originalName": "Breaking Bad",
        "description": "Ein Chemielehrer erfährt von seiner tödlichen Krankheit und beginnt Meth herzustellen.",
        "year": 2008,
        "images": {
            "poster": "https://image.tmdb.org/t/p/w500/breaking_bad.jpg",
            "backdrop": "https://image.tmdb.org/t/p/w1280/bb_backdrop.jpg"
        },
        "genres": ["Crime", "Drama", "Thriller"],
        "episodes": [
            {
                "id": "s1_e1",
                "ids": { "id": "bb_s1e1" },
                "name": { "de": "Pilot", "en": "Pilot" },
                "season": 1,
                "episode": 1,
                "releaseDate": "2008-01-20",
                "poster": "https://image.tmdb.org/t/p/w500/pilot.jpg"
            },
            {
                "id": "s1_e2",
                "name": "Die Katze ist im Sack",
                "season": 1,
                "episode": 2
            }
        ]
    }
    """
    
    public static let sampleSourcesResponseJSON = """
    [
        {
            "id": "src_1080p",
            "type": "url",
            "url": "https://cdn.example.com/streams/master.m3u8",
            "name": "1080p Full HD (HLS)",
            "quality": "1080p",
            "format": "hls",
            "languages": ["de", "en"],
            "headers": {
                "User-Agent": "DezorPlayer/1.0",
                "Referer": "https://demo-addon.example"
            },
            "subtitles": [
                {
                    "id": "sub_de",
                    "name": "Deutsch",
                    "language": "de",
                    "type": "vtt",
                    "url": "https://cdn.example.com/subs/german.vtt"
                },
                {
                    "id": "sub_en",
                    "name": "English",
                    "language": "en",
                    "type": "srt",
                    "url": "https://cdn.example.com/subs/english.srt"
                }
            ]
        },
        {
            "id": "src_gateway",
            "type": "resolver",
            "url": "https://gateway.example.com/resolve?id=xyz789",
            "name": "Fast Gateway Stream",
            "quality": "720p",
            "format": "mp4"
        }
    ]
    """
    
    public static let sampleResolvedUrlJSON = """
    {
        "url": "https://stream.resolved-host.com/live/index.m3u8",
        "name": "Resolved Fast HLS",
        "quality": "1080p",
        "format": "hls",
        "headers": {
            "Authorization": "Bearer sample_token_123",
            "Referer": "https://gateway.example.com"
        },
        "resolveAgain": false
    }
    """
    
    public static let sampleRecursiveResolvedUrlJSON = """
    {
        "url": "https://stream.step2-host.com/resolve_final",
        "name": "Intermediate Gateway",
        "format": "hls",
        "resolveAgain": true
    }
    """
}
