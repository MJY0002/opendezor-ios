import SwiftUI

/// Stand-in for artwork that is missing or failed to load.
///
/// This is not a rare edge case: IPTV addons often ship no logo for most channels,
/// and the ones it does ship point at a host that answers 404. A grid of identical grey
/// boxes reads as "broken", so each item gets a colour derived from its own title —
/// stable across launches, different from its neighbours — plus the title itself, which
/// for a TV channel is the only information there is anyway.
public struct MediaPlaceholderView: View {
    private let title: String
    private let type: String?
    private let compact: Bool

    /// - Parameter compact: drops the caption for small frames (cast circles, episode
    ///   thumbnails) where text would only be noise.
    public init(title: String, type: String? = nil, compact: Bool = false) {
        self.title = title
        self.type = type
        self.compact = compact
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: Self.tint(for: title),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Faint diagonal sheen so large tiles do not read as flat colour.
            LinearGradient(
                colors: [Color.white.opacity(0.10), .clear, Color.black.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if compact {
                Image(systemName: Self.symbol(for: type))
                    .appFont(size: 20, weight: .semibold)
                    .foregroundColor(Color.white.opacity(0.55))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: Self.symbol(for: type))
                        .appFont(size: 26, weight: .semibold)
                        .foregroundColor(Color.white.opacity(0.65))

                    Text(caption)
                        .appFont(size: 12, weight: .bold, design: .rounded)
                        .foregroundColor(Color.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 10)
                }
                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
            }
        }
        .accessibilityHidden(true)
    }

    private var caption: String {
        MediaItem.stripDecoration(title)
    }

    private static func symbol(for type: String?) -> String {
        switch type?.lowercased() {
        case "series": return "tv"
        case "iptv", "channel": return "antenna.radiowaves.left.and.right"
        case "person": return "person.fill"
        case "directory": return "square.grid.2x2"
        default: return "film"
        }
    }

    /// Deterministic two-tone gradient. The same title always yields the same colours, so
    /// a tile does not change hue between launches, while neighbouring tiles differ.
    static func tint(for title: String) -> [Color] {
        var hash: UInt64 = 5381
        for byte in title.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        // djb2 alone leaves its low bits poorly distributed, so channels sharing a prefix
        // ("13TH STREET .c", "13TH STREET HD") all landed on the same green. The murmur3
        // finalizer spreads them across the wheel.
        hash ^= hash >> 33
        hash = hash &* 0xff51_afd7_ed55_8ccd
        hash ^= hash >> 33
        hash = hash &* 0xc4ce_b9fe_1a85_ec53
        hash ^= hash >> 33

        let hue = Double(hash % 360) / 360.0
        // Vary saturation and brightness a little as well, so neighbouring hues still read
        // as distinct tiles. Kept muted enough for white text in both colour schemes.
        let saturationJitter = Double((hash >> 8) % 12) / 100.0
        let brightnessJitter = Double((hash >> 16) % 10) / 100.0
        return [
            Color(hue: hue, saturation: 0.46 + saturationJitter, brightness: 0.44 + brightnessJitter),
            Color(hue: (hue + 0.07).truncatingRemainder(dividingBy: 1.0),
                  saturation: 0.58 + saturationJitter, brightness: 0.26 + brightnessJitter)
        ]
    }
}
