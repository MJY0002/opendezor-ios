import SwiftUI

public struct MediaCardView: View {
    public let item: MediaItem
    public var shape: CardShape = .portrait
    public var progress: Double? = nil
    public var subtitleText: String? = nil
    public var onSelect: () -> Void
    
    public enum CardShape {
        case portrait   // 2:3 (movies / series)
        case landscape  // 16:9 (episodes / backdrops / live streams)
        case square     // 1:1 (music / addons / channels)
        case wideBanner // Hero-like
        
        var aspectRatio: CGFloat {
            switch self {
            case .portrait: return 2.0 / 3.0
            case .landscape: return 16.0 / 9.0
            case .square: return 1.0
            case .wideBanner: return 21.0 / 9.0
            }
        }
        
        var width: CGFloat {
            switch self {
            case .portrait: return 145
            case .landscape: return 220
            case .square: return 130
            case .wideBanner: return 320
            }
        }
    }
    
    public init(
        item: MediaItem,
        shape: CardShape = .portrait,
        progress: Double? = nil,
        subtitleText: String? = nil,
        onSelect: @escaping () -> Void
    ) {
        self.item = item
        self.shape = shape
        self.progress = progress
        self.subtitleText = subtitleText
        self.onSelect = onSelect
    }
    
    /// VoiceOver reads the whole card as one element: title, kind and year, with the
    /// watch progress as the value. Without this it announces just "Button".
    private var accessibilityDescription: String {
        var parts: [String] = [item.cleanDisplayName]
        if let type = item.type {
            parts.append(MediaItem.localizedTypeName(type).capitalized)
        }
        if let year = item.year { parts.append(String(year)) }
        return parts.joined(separator: ", ")
    }

    /// Watch progress announced as the element's value, empty when nothing was watched.
    private var accessibilityProgress: String {
        guard let progress, progress > 0 else { return "" }
        return "\(L("Fortschritt")) \(Int(progress * 100)) %"
    }

    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                // Poster / Thumbnail Container
                ZStack(alignment: .bottomLeading) {
                    posterImage
                        .frame(width: shape.width, height: shape.width / shape.aspectRatio)
                        // The detail page grows out of this poster and returns into it.
                        .zoomSource(id: item.id)
                        .clipped()
                        .background(AppTheme.surfaceLight)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                    
                    // Gradient overlay on card bottom for text contrast
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.65)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .cornerRadius(12)
                    
                    // Top badges (Type / 4K / Live)
                    VStack {
                        HStack {
                            if item.type == "iptv" || item.type == "channel" {
                                LiveBadge()
                            } else if let year = item.year {
                                BadgeView(text: "\(year)", color: AppTheme.surface.opacity(0.8), size: .small)
                            }
                            
                            Spacer()
                            
                            if let type = item.type, type == "series" {
                                BadgeView(text: L("SERIE"), color: AppTheme.primaryAccent, size: .small)
                            }
                        }
                        .padding(6)
                        Spacer()
                    }
                    
                    // Bottom Progress Bar if resuming
                    if let progress = progress, progress > 0 {
                        VStack(spacing: 0) {
                            Spacer()
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: 3)
                                    Rectangle()
                                        .fill(AppTheme.accentGradient)
                                        .frame(width: geo.size.width * CGFloat(progress), height: 3)
                                }
                            }
                            .frame(height: 3)
                            .cornerRadius(1.5)
                        }
                    }
                }
                .frame(width: shape.width, height: shape.width / shape.aspectRatio)
                
                // Titles & Subtitles
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.cleanDisplayName)
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    
                    if let sub = subtitleText ?? item.genres?.joined(separator: " • ") {
                        Text(sub)
                            .appFont(size: 11)
                            .foregroundColor(AppTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(width: shape.width, alignment: .leading)
            }
        }
        .buttonStyle(ScaleCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue(accessibilityProgress)
        .accessibilityAddTraits(.isButton)
    }
    
    @ViewBuilder
    private var posterImage: some View {
        let url = (shape == .landscape || shape == .wideBanner) ? (item.backdropUrl ?? item.posterUrl) : item.posterUrl
        
        CachedAsyncImage(url: url) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            MediaPlaceholderView(title: item.displayName, type: item.type)
        }
    }
}

// MARK: - Scale Card Button Style for interactive feedback
/// Press feedback that reacts on touch-*down*, not on release.
///
/// `isPressed` flips the moment the finger lands, which is the point: waiting for the tap
/// to complete before showing anything reads as lag. The release is critically damped —
/// nothing was thrown, so nothing should bounce. A slight opacity drop rides along so the
/// feedback is still visible when Reduce Motion suppresses the scale.
public struct ScaleCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.96 : 1.0))
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .animation(AppMotion.press, value: configuration.isPressed)
    }
}
