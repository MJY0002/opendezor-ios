import Foundation

// MARK: - Subtitle Cue Model
public struct SubtitleCue: Identifiable, Equatable {
    public let id: Int
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let text: String
    
    public init(id: Int, startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
    
    public func isActive(at time: TimeInterval) -> Bool {
        return time >= startTime && time <= endTime
    }
}

// MARK: - Subtitle Parser
public class SubtitleParser {
    public static let shared = SubtitleParser()
    
    public init() {}
    
    // MARK: - Parse Raw String
    public func parse(content: String, format: String? = nil) -> [SubtitleCue] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Auto-detect format if not explicitly provided
        let isVTT = (format?.lowercased() == "vtt") || trimmed.hasPrefix("WEBVTT") || trimmed.contains("-->") && !trimmed.contains(",")
        
        if isVTT {
            return parseVTT(content: trimmed)
        } else {
            return parseSRT(content: trimmed)
        }
    }
    
    // MARK: - Fetch & Parse from Remote URL
    public func load(from url: URL, format: String? = nil) async throws -> [SubtitleCue] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(MediaHubClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "SubtitleParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to download subtitles"])
        }
        
        // Try UTF-8 first, fallback to Windows-CP1252 / ISO-8859-1
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        
        let fileExt = url.pathExtension.lowercased()
        let resolvedFormat = format ?? (fileExt.isEmpty ? nil : fileExt)
        return parse(content: text, format: resolvedFormat)
    }
    
    // MARK: - SRT Parser
    public func parseSRT(content: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        
        // Normalize line breaks
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        
        let blocks = normalized.components(separatedBy: "\n\n")
        var cueIndex = 1
        
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            guard !lines.isEmpty else { continue }
            
            // Find line containing "-->"
            guard let timeLineIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
                continue
            }
            
            let timeLine = lines[timeLineIndex]
            guard let (start, end) = parseTimeRange(timeLine: timeLine, isVTT: false) else {
                continue
            }
            
            // Collect text lines after the timestamp line
            let textLines = lines[(timeLineIndex + 1)...]
            let rawText = textLines.joined(separator: "\n")
            let cleanedText = cleanSubtitleText(rawText)
            
            if !cleanedText.isEmpty {
                cues.append(SubtitleCue(id: cueIndex, startTime: start, endTime: end, text: cleanedText))
                cueIndex += 1
            }
        }
        
        return cues
    }
    
    // MARK: - WebVTT Parser
    public func parseVTT(content: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        
        let blocks = normalized.components(separatedBy: "\n\n")
        var cueIndex = 1
        
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            // Skip header blocks (WEBVTT, NOTE, STYLE, REGION)
            if let first = lines.first, first.hasPrefix("WEBVTT") || first.hasPrefix("NOTE") || first.hasPrefix("STYLE") || first.hasPrefix("REGION") {
                continue
            }
            
            guard !lines.isEmpty else { continue }
            
            guard let timeLineIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
                continue
            }
            
            let timeLine = lines[timeLineIndex]
            guard let (start, end) = parseTimeRange(timeLine: timeLine, isVTT: true) else {
                continue
            }
            
            let textLines = lines[(timeLineIndex + 1)...]
            let rawText = textLines.joined(separator: "\n")
            let cleanedText = cleanSubtitleText(rawText)
            
            if !cleanedText.isEmpty {
                cues.append(SubtitleCue(id: cueIndex, startTime: start, endTime: end, text: cleanedText))
                cueIndex += 1
            }
        }
        
        return cues
    }
    
    // MARK: - Timestamp Range Parsing
    // e.g. "00:01:20,000 --> 00:01:23,400" (SRT) or "01:20.000 --> 01:23.400" (VTT)
    private func parseTimeRange(timeLine: String, isVTT: Bool) -> (start: TimeInterval, end: TimeInterval)? {
        let parts = timeLine.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        
        let startStr = parts[0].trimmingCharacters(in: .whitespaces)
        // VTT can have positioning settings after end time, e.g. "00:01:23.400 line:0% position:50%"
        let rawEndStr = parts[1].trimmingCharacters(in: .whitespaces)
        let endStr = rawEndStr.components(separatedBy: .whitespaces).first ?? rawEndStr
        
        guard let start = parseTimestamp(startStr), let end = parseTimestamp(endStr) else {
            return nil
        }
        
        return (start, end)
    }
    
    // MARK: - Single Timestamp to Seconds
    // Supports:
    // 00:01:23,456 (SRT: hh:mm:ss,ms)
    // 00:01:23.456 (VTT: hh:mm:ss.ms)
    // 01:23.456    (VTT: mm:ss.ms)
    public func parseTimestamp(_ timestamp: String) -> TimeInterval? {
        let cleaned = timestamp.replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.components(separatedBy: ":")
        
        if parts.count == 3 {
            // hh:mm:ss.ms
            guard let hours = Double(parts[0]),
                  let minutes = Double(parts[1]),
                  let seconds = Double(parts[2]) else {
                return nil
            }
            return (hours * 3600.0) + (minutes * 60.0) + seconds
        } else if parts.count == 2 {
            // mm:ss.ms
            guard let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]) else {
                return nil
            }
            return (minutes * 60.0) + seconds
        }
        
        return nil
    }
    
    // MARK: - Clean HTML / Formatting Tags
    public func cleanSubtitleText(_ text: String) -> String {
        var result = text
        
        // Strip HTML / WebVTT tags like <b>, </i>, <font color="...">, <c.yellow>, <v Speaker>
        result = result.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression,
            range: nil
        )
        
        // Strip SSA/ASS tags like {\an8}
        result = result.replacingOccurrences(
            of: "\\{[^}]+\\}",
            with: "",
            options: .regularExpression,
            range: nil
        )
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Query Active Cue at Time
    public func activeCue(in cues: [SubtitleCue], at time: TimeInterval) -> SubtitleCue? {
        // Linear search for quick match, or binary search if large
        for cue in cues {
            if cue.isActive(at: time) {
                return cue
            }
        }
        return nil
    }
}
