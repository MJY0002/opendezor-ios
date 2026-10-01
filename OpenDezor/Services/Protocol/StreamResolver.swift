import Foundation

// MARK: - Stream Resolver Implementation
public class StreamResolver {
    public static let shared = StreamResolver()
    
    private let client: MediaHubClient
    public var maxResolveDepth: Int = 5
    
    public init(client: MediaHubClient = .shared) {
        self.client = client
    }
    
    public func resolve(
        source: MediaSource,
        addonEndpoint: String? = nil,
        addonManifest: AddonManifest? = nil
    ) async throws -> ResolvedStream {
        // 1. Check if source is already marked resolved or is a direct media stream
        if source.isDirectStream {
            guard let validUrl = URL(string: source.url) else {
                throw MediaHubError.invalidUrl(source.url)
            }
            
            var mergedHeaders = source.headers ?? [:]
            if mergedHeaders["User-Agent"] == nil {
                mergedHeaders["User-Agent"] = client.customUserAgent
            }
            
            let format = StreamFormat.detect(from: source.url, hint: source.format)
            return ResolvedStream(
                url: validUrl,
                format: format,
                headers: mergedHeaders,
                quality: source.quality,
                title: source.displayName,
                subtitles: source.subtitles ?? []
            )
        }
        
        // 2. Resolve via Addon action="resolve"
        let endpointToUse = addonEndpoint ?? extractEndpoint(from: source.url)
        guard !endpointToUse.isEmpty else {
            // If no endpoint available, fallback to direct URL parse
            guard let url = URL(string: source.url) else {
                throw MediaHubError.invalidUrl(source.url)
            }
            let format = StreamFormat.detect(from: source.url, hint: source.format)
            return ResolvedStream(
                url: url,
                format: format,
                headers: source.headers ?? ["User-Agent": client.customUserAgent],
                quality: source.quality,
                title: source.displayName,
                subtitles: source.subtitles ?? []
            )
        }
        
        var currentUrl = source.url
        var currentHeaders = source.headers ?? [:]
        var currentQuality = source.quality
        var currentFormatHint = source.format
        var currentTitle = source.displayName
        var resolveCount = 0
        
        while resolveCount < maxResolveDepth {
            resolveCount += 1
            
            let resolved = try await client.resolveSource(
                endpoint: endpointToUse,
                sourceUrl: currentUrl,
                headers: currentHeaders
            )
            
            currentUrl = resolved.url
            if let h = resolved.headers {
                for (k, v) in h {
                    currentHeaders[k] = v
                }
            }
            if let q = resolved.quality {
                currentQuality = q
            }
            if let f = resolved.format {
                currentFormatHint = f
            }
            if let n = resolved.name {
                currentTitle = n
            }
            
            if resolved.resolveAgain != true {
                break
            }
        }
        
        if currentHeaders["User-Agent"] == nil {
            currentHeaders["User-Agent"] = client.customUserAgent
        }
        
        guard let finalUrl = URL(string: currentUrl) else {
            throw MediaHubError.resolveFailed("\(L("Ungültige aufgelöste Stream-URL")): \(currentUrl)")
        }
        
        let format = StreamFormat.detect(from: currentUrl, hint: currentFormatHint)
        return ResolvedStream(
            url: finalUrl,
            format: format,
            headers: currentHeaders,
            quality: currentQuality,
            title: currentTitle,
            subtitles: source.subtitles ?? []
        )
    }
    
    private func extractEndpoint(from urlString: String) -> String {
        guard let url = URL(string: urlString), let scheme = url.scheme, let host = url.host else {
            return ""
        }
        let portStr = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(portStr)"
    }
}
