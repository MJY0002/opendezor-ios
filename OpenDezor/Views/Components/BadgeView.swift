import SwiftUI

// MARK: - Badge & Pill Views
public struct BadgeView: View {
    public let text: String
    public var icon: String? = nil
    public var color: Color = AppTheme.primaryAccent
    public var size: BadgeSize = .regular
    
    public enum BadgeSize {
        case small, regular, large
        
        var font: Font {
            switch self {
            case .small: return .system(size: 9, weight: .bold)
            case .regular: return .system(size: 11, weight: .bold)
            case .large: return .system(size: 13, weight: .bold)
            }
        }
        
        var paddingVertical: CGFloat {
            switch self {
            case .small: return 2
            case .regular: return 4
            case .large: return 6
            }
        }
        
        var paddingHorizontal: CGFloat {
            switch self {
            case .small: return 6
            case .regular: return 8
            case .large: return 12
            }
        }
    }
    
    public init(text: String, icon: String? = nil, color: Color = AppTheme.primaryAccent, size: BadgeSize = .regular) {
        self.text = text
        self.icon = icon
        self.color = color
        self.size = size
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(size.font)
            }
            Text(text)
                .font(size.font)
                .lineLimit(1)
        }
        // Neutral chips (language tags) sit on `surfaceLight`, which is near-white in light
        // mode — white text vanished on them.
        .foregroundColor(color == AppTheme.surfaceLight ? AppTheme.textPrimary : .white)
        .padding(.vertical, size.paddingVertical)
        .padding(.horizontal, size.paddingHorizontal)
        .background(
            Capsule()
                .fill(color.opacity(0.85))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Quality Badge
public struct QualityBadge: View {
    public let format: String?
    
    public init(format: String?) {
        self.format = format
    }
    
    public var body: some View {
        if let fmt = format?.uppercased(), !fmt.isEmpty {
            let color: Color = {
                if fmt.contains("4K") || fmt.contains("UHD") { return AppTheme.warning }
                if fmt.contains("1080") || fmt.contains("FHD") { return AppTheme.cyanAccent }
                if fmt.contains("HLS") || fmt.contains(L("LIVE")) { return AppTheme.secondaryAccent }
                return AppTheme.primaryAccent
            }()
            
            BadgeView(text: fmt, color: color, size: .small)
        }
    }
}

// MARK: - Live Badge

/// "LIVE" with a beating dot — the one piece of the UI that should look alive.
public struct LiveBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = false

    public init() {}

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.white)
                .frame(width: 5, height: 5)
                .background(
                    Circle()
                        .fill(.white.opacity(0.6))
                        .scaleEffect(beat ? 2.4 : 1)
                        .opacity(beat ? 0 : 1)
                )
            Text(L("LIVE"))
                .font(.system(size: 10, weight: .heavy))
        }
        .foregroundColor(.white)
        .padding(.vertical, 3)
        .padding(.horizontal, 7)
        .background(Capsule().fill(AppTheme.destructive))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { beat = true }
        }
        .accessibilityLabel(L("LIVE"))
    }
}
