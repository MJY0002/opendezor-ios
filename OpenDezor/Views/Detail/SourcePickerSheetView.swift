import SwiftUI

public struct SourcePickerSheetView: View {
    @ObservedObject var viewModel: DetailViewModel
    @ObservedObject var appState: AppState = .shared
    public var episode: SeriesEpisodeItem?
    @Environment(\.dismiss) private var dismiss
    
    public init(viewModel: DetailViewModel, episode: SeriesEpisodeItem? = nil) {
        self.viewModel = viewModel
        self.episode = episode
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                VStack {
                    if viewModel.isLoadingSources {
                        VStack(spacing: 16) {
                            ProgressView()
                                .tint(AppTheme.primaryAccent)
                                .scaleEffect(1.3)
                            Text(L("Suche nach Videoquellen..."))
                                .appFont(size: 14)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .frame(maxHeight: .infinity)
                    } else if viewModel.availableSources.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "film.stack")
                                .appFont(size: 40)
                                .foregroundColor(AppTheme.textTertiary)
                            Text(L("Keine Quellen gefunden"))
                                .appFont(size: 16, weight: .bold)
                                .foregroundColor(AppTheme.textPrimary)
                            Text(L("Für diesen Titel konnten keine aktiven Stream-Server gefunden werden."))
                                .appFont(size: 13)
                                .foregroundColor(AppTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        List {
                            Section {
                                ForEach(viewModel.availableSources) { source in
                                    sourceRow(source: source)
                                }
                            } header: {
                                Text("\(L("Verfügbare Streams")) (\(viewModel.availableSources.count))")
                                    .appFont(size: 13, weight: .semibold)
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            .listRowBackground(AppTheme.surface)
                        }
                        #if os(iOS)
                        .scrollContentBackground(.hidden)
                        #endif
                    }
                }
            }
            .navigationTitle(episode.map { "\(viewModel.item.displayName) - \($0.displayName)" } ?? viewModel.item.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Schließen")) {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.primaryAccent)
                }
            }
            .task {
                // Sources are only looked up through the VPN.
                guard await appState.requireVPN() else { dismiss(); return }
                await viewModel.fetchSources(for: episode)
            }
        }
    }
    
    @ViewBuilder
    private func sourceRow(source: MediaSource) -> some View {
        Button(action: {
            Task {
                dismiss()
                // Hand the chosen source plus the rest of the list to AppState: it resumes
                // the saved position, attaches the addon's subtitles and falls through to
                // the next source if this server turns out to be dead.
                let ordered = [source] + viewModel.availableSources.filter { $0.id != source.id }
                let subtitles = await viewModel.fetchSubtitles(for: episode)
                await appState.beginPlayback(
                    item: viewModel.item,
                    episode: episode,
                    sources: ordered,
                    subtitles: subtitles
                )
            }
        }) {
            HStack(spacing: 12) {
                // Provider / Source Icon
                Image(systemName: "play.circle.fill")
                    .appFont(size: 24)
                    .foregroundColor(AppTheme.cyanAccent)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(source.displayName)
                            .appFont(size: 14, weight: .semibold)
                            .foregroundColor(AppTheme.textPrimary)
                        // "Server C1" appears several times; the hoster is what tells
                        // the rows apart and what the user learns to prefer.
                        if let host = URL(string: source.url)?.host {
                            Text(host.replacingOccurrences(of: "www.", with: ""))
                                .appFont(size: 12)
                                .foregroundColor(AppTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    
                    HStack(spacing: 6) {
                        QualityBadge(format: source.format)
                        
                        if let langs = source.languages, !langs.isEmpty {
                            ForEach(langs, id: \.self) { lang in
                                BadgeView(text: lang.uppercased(), color: AppTheme.surfaceLight, size: .small)
                            }
                        }
                        
                        if let subs = source.subtitles, !subs.isEmpty {
                            BadgeView(text: "CC", icon: "captions.bubble", color: AppTheme.surfaceLight, size: .small)
                        }
                    }
                }
                
                Spacer()
                
                if viewModel.isResolvingSource {
                    ProgressView()
                        .tint(AppTheme.cyanAccent)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleCardButtonStyle())
    }
}
