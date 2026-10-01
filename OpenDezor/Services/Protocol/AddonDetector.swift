import Foundation

// MARK: - Addon Detector Implementation
public class AddonDetector {
    public static let shared = AddonDetector()
    
    private let client: MediaHubClient
    
    public init(client: MediaHubClient = .shared) {
        self.client = client
    }
    
    // MARK: - String URL Entrypoint
    public func detect(from inputUrl: String) async throws -> (manifest: AddonManifest, endpoint: String) {
        var cleanUrl = inputUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Normalize custom schemes
        if cleanUrl.lowercased().hasPrefix("mhub://") {
            cleanUrl = "https://" + cleanUrl.dropFirst("mhub://".count)
        } else if cleanUrl.lowercased().hasPrefix("mediaurl://") {
            cleanUrl = "https://" + cleanUrl.dropFirst("mediaurl://".count)
        } else if cleanUrl.lowercased().hasPrefix("dezor://") {
            cleanUrl = "https://" + cleanUrl.dropFirst("dezor://".count)
        } else if !cleanUrl.lowercased().hasPrefix("http://") && !cleanUrl.lowercased().hasPrefix("https://") {
            cleanUrl = "https://" + cleanUrl
        }
        
        guard let url = URL(string: cleanUrl) else {
            throw MediaHubError.invalidUrl(inputUrl)
        }
        
        return try await detect(url: url)
    }
    
    // MARK: - URL Object Entrypoint
    public func detect(url: URL) async throws -> (manifest: AddonManifest, endpoint: String) {
        let scheme = url.scheme ?? "https"
        let host = url.host ?? ""
        let portStr = url.port.map { ":\($0)" } ?? ""
        let origin = "\(scheme)://\(host)\(portStr)"
        
        var rawPath = url.path
        if rawPath.hasSuffix("/") {
            rawPath = String(rawPath.dropLast())
        }
        let basePath = rawPath
        
        // 1. Direct manifest check if URL points directly to a .json file
        if url.path.lowercased().hasSuffix(".json") {
            do {
                let (manifest, finalUrl) = try await client.fetchManifestResolvingRedirects(from: url.absoluteString)
                return (manifest, resolveEndpoint(for: manifest, fallback: finalUrl, origin: origin))
            } catch {
                // If direct JSON fetch fails, continue to probe fallbacks
            }
        }
        
        // 2. Build prioritized candidate list for probing
        var candidates: [String] = []
        if !basePath.isEmpty && basePath != "/" {
            candidates.append("\(origin)\(basePath)/mediahubmx.json")
            candidates.append("\(origin)\(basePath)/mediaurl.json")
        }
        candidates.append("\(origin)/mediahubmx.json")
        candidates.append("\(origin)/mediaurl.json")
        
        // Probe candidate manifest URLs sequentially. The endpoint keeps its manifest
        // filename on purpose — MediaHubClient reads the protocol engine (mediahubmx vs
        // mediaurl) out of it and derives every action URL from there. Redirects are
        // resolved so a moved addon (an old host redirecting to a new one) ends up on the host that
        // actually answers.
        for candidate in candidates {
            if let (manifest, finalUrl) = try? await client.fetchManifestResolvingRedirects(from: candidate) {
                return (manifest, resolveEndpoint(for: manifest, fallback: finalUrl, origin: origin))
            }
        }
        
        // 3. Fallback: Query the endpoint directly via action="addon"
        let targetEndpoint = "\(origin)\(basePath)"
        if let manifest = try? await client.fetchAddonInfo(endpoint: targetEndpoint) {
            let endpoint = resolveEndpoint(for: manifest, fallback: targetEndpoint, origin: origin)
            return (manifest, endpoint)
        }
        
        throw MediaHubError.discoveryFailed("\(L("Unter")) \(url.absoluteString) \(L("wurde kein MediaHub/MediaURL-Addon gefunden."))")
    }
    
    // MARK: - Helper to resolve custom endpoints defined in Manifest
    private func resolveEndpoint(for manifest: AddonManifest, fallback: String, origin: String) -> String {
        guard let customEndpoints = manifest.endpoints, let first = customEndpoints.first, !first.isEmpty else {
            return fallback
        }
        if first.lowercased().hasPrefix("http://") || first.lowercased().hasPrefix("https://") {
            return first
        }
        if first.hasPrefix("/") {
            return "\(origin)\(first)"
        }
        // A relative endpoint hangs off the addon's base URL, so strip the manifest
        // filename before appending it.
        let base = MediaHubClient.splitEndpoint(fallback).base
        return "\(base)/\(first)"
    }
}
