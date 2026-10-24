import SwiftUI

// MARK: - Section Header
public struct SectionHeaderView: View {
    public let title: String
    public var subtitle: String? = nil
    public var actionTitle: String? = L("Alle anzeigen")
    public var onAction: (() -> Void)? = nil
    
    public init(
        title: String,
        subtitle: String? = nil,
        actionTitle: String? = L("Alle anzeigen"),
        onAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.onAction = onAction
    }
    
    public var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(AppTheme.textPrimary)
                
                if let sub = subtitle, !sub.isEmpty {
                    Text(sub)
                        .appFont(size: 12)
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            Spacer()
            
            if let onAction = onAction, let actionTitle = actionTitle {
                Button(action: onAction) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                            .appFont(size: 13, weight: .medium)
                        Image(systemName: "chevron.right")
                            .appFont(size: 11, weight: .bold)
                    }
                    .foregroundColor(AppTheme.primaryAccent)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Hero Banner View
public struct HeroBannerView: View {
    /// In landscape on a phone the vertical size class is compact, where a 380pt banner
    /// would eat the whole screen. Shrinking it keeps the rows below reachable.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isCompact: Bool { verticalSizeClass == .compact }
    private var bannerHeight: CGFloat { isCompact ? 240 : 380 }

    public let item: MediaItem
    public var onPlay: () -> Void
    public var onMoreInfo: () -> Void
    
    public init(item: MediaItem, onPlay: @escaping () -> Void, onMoreInfo: @escaping () -> Void) {
        self.item = item
        self.onPlay = onPlay
        self.onMoreInfo = onMoreInfo
    }
    
    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop Image
            // Prefer the addon's own banner/backdrop; a portrait poster only as a last
            // resort, since stretching one across the hero looks like a placeholder.
            CachedAsyncImage(url: item.wideArtworkUrl ?? item.posterUrl, proxySize: .large) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                // No spinner here: an item may have no artwork at all, or a URL that 404s
                // (both are routine for IPTV channels), and a spinner would never stop.
                MediaPlaceholderView(title: item.displayName, type: item.type, compact: true)
            }
            // Same trap as the detail backdrop: scaledToFill without a width cap reports
            // a width wider than the screen and skews the layout around it.
            .frame(maxWidth: .infinity, minHeight: bannerHeight, maxHeight: bannerHeight)
            // The artwork breathes and lags the scroll; the clip keeps both inside the card.
            .kenBurns()
            .parallax(0.25)
            .clipped()
            // Artwork carries no information VoiceOver could use; the title and buttons
            // below say everything.
            .accessibilityHidden(true)

            // Dark Gradient Overlay for readability
            AppTheme.heroBackdropGradient
                .frame(maxWidth: .infinity, minHeight: bannerHeight, maxHeight: bannerHeight)
                .accessibilityHidden(true)
            
            // Content
            VStack(alignment: .leading, spacing: 10) {
                // Badges
                HStack(spacing: 6) {
                    if item.type == "series" {
                        BadgeView(text: L("SERIE"), color: AppTheme.primaryAccent)
                    } else if item.type == "movie" {
                        BadgeView(text: L("FILM"), color: AppTheme.secondaryAccent)
                    } else if item.type == "iptv" || item.type == "channel" {
                        BadgeView(text: L("LIVE TV"), color: AppTheme.destructive)
                    }
                    
                    if let year = item.year {
                        BadgeView(text: "\(year)", color: AppTheme.onArtworkChip)
                    }

                    if let genres = item.genres?.prefix(2) {
                        ForEach(Array(genres), id: \.self) { genre in
                            BadgeView(text: genre, color: AppTheme.onArtworkChip)
                        }
                    }
                }

                // Title. White on purpose in both themes: this sits on the scrim over
                // artwork, not on the page, so it must not follow the text palette —
                // `textPrimary` turned it dark-on-bright-photo in light mode.
                Text(item.displayName)
                    .appFont(size: isCompact ? 22 : 26, weight: .heavy)
                    .foregroundColor(.white)
                    .lineLimit(isCompact ? 1 : 2)
                    .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 2)

                // Synopsis Preview. Landscape is only 240 pt tall: badges, title and buttons
                // already fill it, so the synopsis stays on the detail page there.
                if !isCompact, let desc = item.description?.value, !desc.isEmpty {
                    Text(desc)
                        .appFont(size: 13)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                        .lineSpacing(2)
                        .shadow(color: .black.opacity(0.7), radius: 3, x: 0, y: 1)
                }
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button(action: onPlay) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .appFont(size: 16, weight: .bold)
                            Text(L("Jetzt Abspielen"))
                                .appFont(size: 15, weight: .semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 22)
                        .background(AppTheme.accentGradient)
                        .cornerRadius(24)
                        .shadow(color: AppTheme.primaryAccent.opacity(0.5), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(ScaleCardButtonStyle())
                    
                    Button(action: onMoreInfo) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .appFont(size: 15, weight: .semibold)
                            Text(L("Details"))
                                .appFont(size: 14, weight: .medium)
                        }
                        .foregroundColor(AppTheme.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 18)
                        .glassCard(cornerRadius: 24)
                    }
                    .buttonStyle(ScaleCardButtonStyle())
                }
                .padding(.top, 4)
            }
            .padding(isCompact ? 16 : 20)
            // Badges, title and buttons arrive in sequence, and again for each new hero.
            .appearsStaggered(delay: 0.15)
            .id(item.id)
        }
        // Must track bannerHeight: a hardcoded 380 here silently overrode the shorter
        // landscape layout the image and gradient above were already using.
        .frame(height: bannerHeight)
        .cornerRadius(20)
        .padding(.horizontal, 16)
        .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Toast Notification Banner
public struct ToastNotification: Identifiable, Equatable {
    public let id = UUID()
    public let message: String
    public let icon: String?
    public let isError: Bool
    
    public init(message: String, icon: String? = nil, isError: Bool = false) {
        self.message = message
        self.icon = icon
        self.isError = isError
    }
}

public struct ToastBannerView: View {
    public let toast: ToastNotification
    
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.icon ?? (toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"))
                .foregroundColor(toast.isError ? AppTheme.destructive : AppTheme.success)
                .appFont(size: 18)
            
            Text(toast.message)
                .appFont(size: 14, weight: .medium)
                // The glass card is light in light mode; white text vanished on it.
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(2)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 16, strokeColor: toast.isError ? AppTheme.destructive.opacity(0.4) : AppTheme.success.opacity(0.4))
        .padding(.horizontal, 20)
        .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 5)
    }
}

/// Shown while a stream is being resolved. Hoster pages are fetched through the addon's
/// task round trips, which takes several seconds — without this, "Play" looked dead.
public struct PreparingPlaybackBanner: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(AppTheme.cyanAccent)
            Text(L("Stream wird vorbereitet…"))
                .appFont(size: 14, weight: .medium)
                .foregroundColor(AppTheme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 16)
        .padding(.horizontal, 20)
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Hero Carousel

/// Featured titles, one page at a time, advancing on their own every few seconds.
///
/// Paging snaps like the App Store's Today cards; the page the user touches stays put —
/// the timer restarts from any manual swipe, so the carousel never yanks a page away
/// mid-read. The indicator's active capsule fills over the dwell time, so the next change
/// is predictable rather than a surprise. Reduce Motion stops the automatic advance.
public struct HeroCarouselView: View {
    public let items: [MediaItem]
    public var onPlay: (MediaItem) -> Void
    public var onMoreInfo: (MediaItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var current: String?
    @State private var progress: CGFloat = 0
    @State private var cycle = 0

    private static let dwell: Double = 7

    public init(items: [MediaItem], onPlay: @escaping (MediaItem) -> Void, onMoreInfo: @escaping (MediaItem) -> Void) {
        self.items = items
        self.onPlay = onPlay
        self.onMoreInfo = onMoreInfo
    }

    private var bannerHeight: CGFloat { verticalSizeClass == .compact ? 240 : 380 }
    private var currentIndex: Int { items.firstIndex { $0.id == current } ?? 0 }

    public var body: some View {
        VStack(spacing: 12) {
            // A paging TabView rather than a paged ScrollView: it re-pages itself on rotation
            // and sizes its pages to the safe area. The ScrollView version left the page
            // half off-screen after turning the device, because its pages were measured
            // inside the safe area while the scroll view itself ran edge to edge.
            TabView(selection: selection) {
                ForEach(items) { item in
                    HeroBannerView(
                        item: item,
                        onPlay: { onPlay(item) },
                        onMoreInfo: { onMoreInfo(item) }
                    )
                    .tag(item.id)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
#endif
            .frame(height: bannerHeight + 24)

            pageIndicator
        }
        .onAppear { if current == nil { current = items.first?.id } }
        .onChange(of: current) { _, _ in cycle += 1 }
        // Restarts on every page change, whether the timer or a swipe caused it.
        .task(id: cycle) { await runDwell() }
    }

    private var selection: Binding<String> {
        Binding(
            get: { current ?? items.first?.id ?? "" },
            set: { current = $0 }
        )
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let active = index == currentIndex
                Capsule()
                    .fill(AppTheme.textTertiary.opacity(0.4))
                    .frame(width: active ? 28 : 7, height: 7)
                    .overlay(alignment: .leading) {
                        if active {
                            Capsule()
                                .fill(AppTheme.textPrimary)
                                .frame(width: 28 * (reduceMotion ? 1 : progress))
                        }
                    }
                    .clipShape(Capsule())
                    .onTapGesture { withAnimation(AppMotion.standard) { current = item.id } }
            }
        }
        .animation(AppMotion.standard, value: currentIndex)
        .accessibilityElement()
        .accessibilityLabel("\(currentIndex + 1) / \(items.count)")
    }

    @MainActor
    private func runDwell() async {
        progress = 0
        guard !reduceMotion, items.count > 1 else { return }
        withAnimation(.linear(duration: Self.dwell)) { progress = 1 }
        try? await Task.sleep(nanoseconds: UInt64(Self.dwell * 1_000_000_000))
        guard !Task.isCancelled else { return }
        let next = items[(currentIndex + 1) % items.count].id
        withAnimation(.spring(response: 0.7, dampingFraction: 1)) { current = next }
    }
}
