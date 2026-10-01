import SwiftUI

public struct MediaDetailView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var backdropHeight: CGFloat { verticalSizeClass == .compact ? 260 : 380 }

    @StateObject private var viewModel: DetailViewModel
    @ObservedObject var appState: AppState = .shared
    @State private var showSourcePicker: Bool = false
    @State private var selectedEpisodeForSource: SeriesEpisodeItem? = nil
    @State private var isDescriptionExpanded: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    public init(item: MediaItem) {
        _viewModel = StateObject(wrappedValue: DetailViewModel(item: item))
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Hero Backdrop Header
                backdropHeader
                    .stretchyHeader(height: backdropHeight)
                
                // Content Body
                VStack(alignment: .leading, spacing: 20) {
                    // Metadata & Action Buttons
                    metadataSection
                    
                    // Synopsis
                    synopsisSection
                    
                    // Cast & Crew
                    castSection
                    
                    // TV Series Seasons & Episodes
                    if viewModel.item.type == "series" || viewModel.item.episodes != nil {
                        seriesEpisodesSection
                    }
                    
                    Spacer().frame(height: 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, -30) // Pull up into backdrop gradient
            }
        }
        .ignoresSafeArea(edges: .top)
        .glassBackground()
        // The detail sheet stays up while a source is resolved, so the progress has to
        // show here — the app-level banner sits underneath this sheet.
        .overlay(alignment: .bottom) {
            if appState.isPreparingPlayback {
                PreparingPlaybackBanner()
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(AppMotion.standard, value: appState.isPreparingPlayback)
        .task {
            await viewModel.loadDetail()
        }
        .sheet(isPresented: $showSourcePicker) {
            SourcePickerSheetView(viewModel: viewModel, episode: selectedEpisodeForSource)
        }
    }
    
    // MARK: - Hero Backdrop
    private var backdropHeader: some View {
        ZStack(alignment: .topLeading) {
            CachedAsyncImage(url: viewModel.item.backdropUrl ?? viewModel.item.posterUrl, proxySize: .large) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                MediaPlaceholderView(title: viewModel.item.displayName, type: viewModel.item.type)
            }
            // scaledToFill keeps the image's aspect ratio, so without an explicit width
            // cap it reports a width wider than the screen and drags the whole layout
            // sideways. maxWidth pins it to the proposed width before clipping.
            .frame(maxWidth: .infinity, minHeight: backdropHeight, maxHeight: backdropHeight)
            .clipped()

            // Multi-stop gradient overlay
            AppTheme.heroBackdropGradient
                .frame(maxWidth: .infinity, minHeight: backdropHeight, maxHeight: backdropHeight)
            
            // Top Bar Back Button
            HStack {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                
                Spacer()
                
                Button(action: {
                    viewModel.toggleFavorite()
                }) {
                    Image(systemName: viewModel.isFavorite ? "bookmark.fill" : "bookmark")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(viewModel.isFavorite ? AppTheme.cyanAccent : .white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.ultraThinMaterial))
                        .contentTransition(.symbolEffect(.replace))
                }
                // Causality: the tick lands on the same frame the bookmark fills.
                .sensoryFeedback(.selection, trigger: viewModel.isFavorite)
            }
            // Chips float over artwork: dark material in both themes so the glyphs stay legible.
            .environment(\.colorScheme, .dark)
            .buttonStyle(ScaleCardButtonStyle())
            .padding(.horizontal, 16)
            .padding(.top, 54)
        }
        .frame(maxWidth: .infinity, minHeight: backdropHeight, maxHeight: backdropHeight)
        .clipped()
    }
    
    // MARK: - Metadata & Actions
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Badges
            HStack(spacing: 8) {
                if let type = viewModel.item.type {
                    BadgeView(text: MediaItem.localizedTypeName(type), color: type == "series" ? AppTheme.primaryAccent : AppTheme.secondaryAccent)
                }
                
                if let year = viewModel.item.year {
                    BadgeView(text: "\(year)", color: AppTheme.surfaceLight)
                }
                
                if let runtime = viewModel.item.formattedRuntime {
                    BadgeView(text: runtime, color: AppTheme.surfaceLight)
                }
            }
            
            // Title
            Text(viewModel.item.displayName)
                .appFont(size: 26, weight: .heavy)
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(2)
            
            // Genres
            if let genres = viewModel.item.genres, !genres.isEmpty {
                Text(genres.joined(separator: " • "))
                    .appFont(size: 13, weight: .medium)
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            // Primary Action Buttons
            HStack(spacing: 12) {
                // Play Button
                Button(action: {
                    selectedEpisodeForSource = viewModel.selectedEpisode
                    showSourcePicker = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .appFont(size: 16, weight: .bold)
                        Text(L("Jetzt Abspielen"))
                            .appFont(size: 15, weight: .semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accentGradient)
                    .cornerRadius(16)
                    .shadow(color: AppTheme.primaryAccent.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                
                // Sources Button
                Button(action: {
                    selectedEpisodeForSource = viewModel.selectedEpisode
                    showSourcePicker = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "server.rack")
                            .appFont(size: 14)
                        Text(L("Quellen"))
                            .appFont(size: 14, weight: .medium)
                    }
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 18)
                    .glassCard(cornerRadius: 16)
                }
            }
            .buttonStyle(ScaleCardButtonStyle())
            .padding(.top, 6)
        }
    }
    
    // MARK: - Synopsis Section
    private var synopsisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Handlung"))
                .appFont(size: 16, weight: .bold)
                .foregroundColor(AppTheme.textPrimary)
            
            if let desc = viewModel.item.description?.value, !desc.isEmpty {
                Text(desc)
                    .appFont(size: 14)
                    .foregroundColor(AppTheme.textSecondary)
                    .lineSpacing(4)
                    .lineLimit(isDescriptionExpanded ? nil : 3)
                
                Button(action: {
                    withAnimation { isDescriptionExpanded.toggle() }
                }) {
                    Text(isDescriptionExpanded ? L("Weniger anzeigen") : L("Mehr anzeigen"))
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(AppTheme.primaryAccent)
                }
            } else {
                Text(L("Keine Beschreibung für diesen Titel verfügbar."))
                    .appFont(size: 13)
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
    }
    
    // MARK: - Cast Section
    private var castSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cast = viewModel.item.cast, !cast.isEmpty {
                Text(L("Besetzung"))
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(AppTheme.textPrimary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(cast, id: \.name) { person in
                            // The protocol carries a name and a headshot, nothing more —
                            // so tapping hands the name to the browser tab rather than
                            // opening a detail screen that would have nothing to show.
                            Button {
                                AppState.shared.openInBrowser(query: person.name ?? "")
                            } label: {
                                VStack(alignment: .center, spacing: 6) {
                                    CachedAsyncImage(url: person.poster, proxySize: .small) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        MediaPlaceholderView(title: person.name ?? "", type: "person", compact: true)
                                            .clipShape(Circle())
                                    }
                                    .frame(width: 56, height: 56)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                    )

                                    Text(person.name ?? "")
                                        .appFont(size: 11, weight: .semibold)
                                        .foregroundColor(AppTheme.textPrimary)
                                        .lineLimit(1)
                                        .frame(width: 70)

                                    if let role = person.character {
                                        Text(role)
                                            .appFont(size: 10)
                                            .foregroundColor(AppTheme.textTertiary)
                                            .lineLimit(1)
                                            .frame(width: 70)
                                    }
                                }
                            }
                            .buttonStyle(ScaleCardButtonStyle())
                            .disabled((person.name ?? "").isEmpty)
                            .accessibilityLabel("\(person.name ?? "") – \(L("im Browser suchen"))")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Series Episodes Section
    private var seriesEpisodesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("Episoden"))
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                // Season Picker
                if viewModel.availableSeasons.count > 1 {
                    Menu {
                        ForEach(viewModel.availableSeasons, id: \.self) { season in
                            Button("\(L("Staffel")) \(season)") {
                                viewModel.selectedSeason = season
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(L("Staffel")) \(viewModel.selectedSeason)")
                                .appFont(size: 13, weight: .semibold)
                            Image(systemName: "chevron.down")
                                .appFont(size: 10, weight: .bold)
                        }
                        .foregroundColor(AppTheme.cyanAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassCard(cornerRadius: 12)
                    }
                }
            }
            
            // Episode List
            LazyVStack(spacing: 12) {
                ForEach(viewModel.episodesForSelectedSeason) { episode in
                    episodeRow(episode: episode)
                }
            }
        }
    }
    
    @ViewBuilder
    private func episodeRow(episode: SeriesEpisodeItem) -> some View {
        Button(action: {
            selectedEpisodeForSource = episode
            viewModel.selectedEpisode = episode
            showSourcePicker = true
        }) {
            HStack(spacing: 12) {
                // Thumbnail
                ZStack(alignment: .center) {
                    CachedAsyncImage(url: episode.poster ?? viewModel.item.backdropUrl, proxySize: .small) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        MediaPlaceholderView(title: episode.displayName, type: "series", compact: true)
                    }
                    .frame(width: 100, height: 60)
                    .clipped()
                    .cornerRadius(8)
                    
                    Image(systemName: "play.circle.fill")
                        .appFont(size: 24)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                }
                
                // Episode Info
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(L("Episode")) \(episode.episode): \(episode.displayName)")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    
                    if let desc = episode.description?.value, !desc.isEmpty {
                        Text(desc)
                            .appFont(size: 11)
                            .foregroundColor(AppTheme.textTertiary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(10)
            .glassCard(cornerRadius: 12)
        }
    }
}
