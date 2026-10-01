import Foundation

/// Fast and robust parser for IPTV playlists in M3U / M3U8 format.
public struct M3UParser {
    
    /// Parses an M3U playlist string into an array of MediaItem channel objects.
    public static func parse(content: String, defaultCategory: String = "Allgemein") -> [MediaItem] {
        var items: [MediaItem] = []
        let lines = content.components(separatedBy: .newlines)
        
        var currentTvgId: String? = nil
        var currentTvgName: String? = nil
        var currentTvgLogo: String? = nil
        var currentGroupTitle: String? = nil
        var currentCountry: String? = nil
        var currentChannelName: String? = nil
        
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            
            if line.hasPrefix("#EXTINF:") {
                // Parse #EXTINF metadata line
                let info = String(line.dropFirst("#EXTINF:".count))
                
                // Extract channel name (after the last comma)
                if let commaIndex = info.range(of: ",", options: .backwards) {
                    let namePart = String(info[commaIndex.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    currentChannelName = namePart.isEmpty ? nil : namePart
                }
                
                // Extract attributes like tvg-id="...", tvg-logo="...", group-title="..."
                currentTvgId = extractAttribute(name: "tvg-id", from: info)
                currentTvgName = extractAttribute(name: "tvg-name", from: info)
                currentTvgLogo = extractAttribute(name: "tvg-logo", from: info)
                currentGroupTitle = extractAttribute(name: "group-title", from: info)
                currentCountry = extractAttribute(name: "tvg-country", from: info)
                
            } else if line.hasPrefix("#") {
                // Ignore other header/comment directives
                continue
            } else {
                // This is the stream URL line
                let urlString = line
                guard let _ = URL(string: urlString) else { continue }
                
                let displayName = currentChannelName ?? currentTvgName ?? L("IPTV Sender")
                let category = currentGroupTitle ?? defaultCategory
                let channelId = currentTvgId ?? "m3u_\(abs(urlString.hashValue))"
                
                let item = MediaItem(
                    customId: channelId,
                    type: "iptv",
                    ids: ["id": channelId],
                    name: .single(displayName),
                    originalName: currentTvgName,
                    images: ItemImages(poster: currentTvgLogo, backdrop: currentTvgLogo, background: nil, logo: currentTvgLogo),
                    url: urlString,
                    logo: currentTvgLogo,
                    category: category,
                    group: category,
                    country: currentCountry
                )
                items.append(item)
                
                // Reset for next entry
                currentTvgId = nil
                currentTvgName = nil
                currentTvgLogo = nil
                currentGroupTitle = nil
                currentCountry = nil
                currentChannelName = nil
            }
        }
        
        return items
    }
    
    /// Fetches a remote M3U playlist and parses it.
    public static func fetchAndParse(from url: URL, session: URLSession = .shared) async throws -> [MediaItem] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(MediaHubClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw MediaHubError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1, message: L("M3U Playlist konnte nicht geladen werden"))
        }
        
        let content = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? ""
        
        return parse(content: content)
    }
    
    // MARK: - Attribute Extraction Helper
    private static func extractAttribute(name: String, from string: String) -> String? {
        let pattern = "\(name)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: string, options: [], range: NSRange(string.startIndex..., in: string)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: string) else {
            return nil
        }
        let val = String(string[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return val.isEmpty ? nil : val
    }
}
