import SwiftUI

public struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var omnibox = OmniboxViewModel()
    @ObservedObject var appState: AppState = .shared
    @ObservedObject private var addonManager: AddonManager = .shared
    
    public var onSelectMediaItem: (MediaItem) -> Void
    public var onOpenCatalog: (DashboardSection) -> Void
    
    public init(
        onSelectMediaItem: @escaping (MediaItem) -> Void,
        onOpenCatalog: @escaping (DashboardSection) -> Void
    ) {
        self.onSelectMediaItem = onSelectMediaItem
        self.onOpenCatalog = onOpenCatalog
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                
                // Hero: a rotating carousel once several titles have wide artwork,
                // otherwise the single banner.
                if viewModel.heroItems.count > 1 {
                    HeroCarouselView(
                        items: viewModel.heroItems,
                        onPlay: { item in
                            Task { await appState.startPlaybackResolvingSource(item: item) }
                        },
                        onMoreInfo: onSelectMediaItem
                    )
                } else if let hero = viewModel.heroItem {
                    HeroBannerView(item: hero, onPlay: {
                        // The hero item comes straight from a catalog and has no stream
                        // attached yet, so resolve one before opening the player.
                        Task { await appState.startPlaybackResolvingSource(item: hero) }
                    }, onMoreInfo: {
                        onSelectMediaItem(hero)
                    })
                }
                
                // Continue Watching (Weiterschauen)
                if !viewModel.continueWatching.isEmpty {
                    continueWatchingSection.revealOnScroll()
                }
                
                // Favorites (Meine Liste)
                if !viewModel.favorites.isEmpty {
                    favoritesSection.revealOnScroll()
                }
                
                // Dynamic Addon Sections
                if viewModel.sections.isEmpty && !viewModel.isLoading {
                    emptyAddonsBanner
                } else {
                    ForEach(viewModel.sections) { section in
                        dashboardSectionView(section: section).revealOnScroll()
                    }
                }
                
                Spacer().frame(height: 80) // Bottom tab padding
            }
        }
        // Search and VPN state stay reachable while the page scrolls underneath a
        // translucent bar — chrome as a material layer, not a strip that scrolls away.
        // Everything plays through the VPN, so its state belongs where playback starts.
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                OmniboxView(viewModel: omnibox)
                // Opens the full search page without typing first, to pick Filme/Serien/… up front.
                Button { omnibox.openSearchPage() } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .appFont(size: 22)
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(L("Suchseite öffnen"))
                VPNStatusPill()
                    .padding(.trailing, 16)
            }
            .padding(.top, 4)
            .padding(.bottom, 10)
            .background(.bar)
        }
        .glassBackground()
        .navigationDestination(isPresented: $omnibox.isSearchPagePresented) {
            SearchView(initialQuery: omnibox.searchPageQuery, onSelectItem: onSelectMediaItem)
        }
        .refreshable {
            await viewModel.loadDashboard()
        }
        // Installing an addon from the omnibox or a mhub:// link changes activeAddons
        // while this view is already on screen, so reload instead of showing the
        // empty-state until the next cold start.
        .onChange(of: addonManager.activeAddons.count) {
            Task { await viewModel.loadDashboard() }
        }
        .task {
            await viewModel.loadDashboard()
        }
    }
    
    // MARK: - Continue Watching Section
    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeaderView(title: L("Weiterschauen"), actionTitle: nil)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(viewModel.continueWatching) { item in
                        let media = item.asMediaItem

                        MediaCardView(
                            item: media,
                            shape: .landscape,
                            progress: item.progressRatio,
                            subtitleText: item.episodeKey != nil ? "\(L("Staffel")) \(item.season ?? 1), \(L("Folge")) \(item.episode ?? 1)" : nil
                        ) {
                            onSelectMediaItem(media)
                        }
                        .carouselDepth()
                    }
                }
                .scrollTargetLayout()
            }
            .carouselSnapping()
        }
    }
    
    // MARK: - Favorites Section
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeaderView(title: L("Meine Liste / Favoriten"), actionTitle: nil)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(viewModel.favorites) { item in
                        let media = item.asMediaItem

                        MediaCardView(item: media, shape: .portrait) {
                            onSelectMediaItem(media)
                        }
                        .carouselDepth()
                    }
                }
                .scrollTargetLayout()
            }
            .carouselSnapping()
        }
    }
    
    // MARK: - Dynamic Addon Section View
    @ViewBuilder
    private func dashboardSectionView(section: DashboardSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeaderView(
                title: section.dashboard.name?.value ?? section.dashboard.id,
                actionTitle: L("Alle anzeigen")
            ) {
                onOpenCatalog(section)
            }
            
            if section.isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(0..<5, id: \.self) { _ in
                            CardSkeletonView(width: 145, height: 210)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            } else if section.items.isEmpty {
                Text(L("Keine Einträge in diesem Katalog gefunden."))
                    .appFont(size: 13)
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(section.items) { item in
                            let shape: MediaCardView.CardShape = {
                                if let s = section.dashboard.options?.shape {
                                    if s == "landscape" { return .landscape }
                                    if s == "square" { return .square }
                                }
                                return .portrait
                            }()
                            
                            MediaCardView(item: item, shape: shape) {
                                onSelectMediaItem(item)
                            }
                            .carouselDepth()
                        }
                    }
                    .scrollTargetLayout()
                }
                .carouselSnapping()
            }
        }
    }
    
    // MARK: - Empty Addons Banner
    private var emptyAddonsBanner: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.tv")
                .appFont(size: 48)
                .foregroundColor(AppTheme.primaryAccent)
            
            Text(L("Willkommen bei OpenDezor"))
                .appFont(size: 20, weight: .bold)
                .foregroundColor(AppTheme.textPrimary)
            
            Text(L("Installiere ein MediaHub-Addon über die Adressleiste oben oder durchsuche Kataloge."))
                .appFont(size: 14)
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
        .glassCard(cornerRadius: 20)
        .padding(.horizontal, 16)
    }
}
