import SwiftUI

public struct LiveTVGuideView: View {
    @StateObject private var viewModel = LiveTVViewModel()
    @ObservedObject var appState: AppState = .shared
    @State private var showImportSheet = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                VStack(spacing: 12) {
                    // Search & Categories
                    searchAndCategoryHeader
                    
                    // Channel List & EPG
                    if viewModel.isLoading {
                        VStack(spacing: 16) {
                            Spacer()
                            ProgressView()
                                .tint(AppTheme.cyanAccent)
                                .scaleEffect(1.3)
                            Text(L("Lade Live-TV Sender..."))
                                .appFont(size: 14)
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                        }
                    } else if viewModel.filteredChannels.isEmpty {
                        emptyState
                    } else {
                        channelList
                    }
                }
            }
            .navigationTitle(L("Live TV & EPG"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showImportSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .appFont(size: 18)
                            .foregroundColor(AppTheme.cyanAccent)
                    }
                    .accessibilityLabel(L("M3U Playlist importieren"))
                }
            }
            .sheet(isPresented: $showImportSheet) {
                ImportM3USheetView(viewModel: viewModel)
            }
            .task {
                if viewModel.channels.isEmpty {
                    await viewModel.loadChannels()
                }
            }
            .refreshable {
                await viewModel.loadChannels()
            }
        }
    }
    
    // MARK: - Search & Categories Header
    private var searchAndCategoryHeader: some View {
        VStack(spacing: 10) {
            // Search Input
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.textTertiary)
                    .appFont(size: 14)
                
                TextField(L("Sender suchen..."), text: $viewModel.searchQuery)
                    .appFont(size: 13)
                    .foregroundColor(AppTheme.textPrimary)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                
                if !viewModel.searchQuery.isEmpty {
                    ClearFieldButton {
                        viewModel.searchQuery = ""
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.surface)
            )
            .padding(.horizontal, 16)
            
            // Category Filter Pills
            if viewModel.categories.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.categories, id: \.self) { cat in
                            let isSelected = viewModel.selectedCategory == cat
                            Button(action: {
                                viewModel.selectedCategory = cat
                            }) {
                                Text(cat == "Alle" ? L("Alle") : cat)
                                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? AppTheme.cyanAccent : AppTheme.surfaceLight)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Channel List
    private var channelList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.filteredChannels) { channel in
                    channelRow(channel: channel).revealOnScroll()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 80)
        }
    }
    
    @ViewBuilder
    private func channelRow(channel: MediaItem) -> some View {
        Button(action: {
            playChannel(channel)
        }) {
            HStack(spacing: 14) {
                // Channel Logo / Icon
                ZStack {
                    // Most channels ship no usable logo, so the tinted initial stands in
                    // for one rather than a row of identical grey squares.
                    MediaPlaceholderView(title: channel.displayName, type: "iptv", compact: true)

                    if let logoUrl = channel.logo ?? channel.posterUrl {
                        CachedAsyncImage(url: logoUrl, proxySize: .small) { img in
                            img
                                .resizable()
                                .scaledToFit()
                        } placeholder: {
                            Color.clear
                        }
                    }
                }
                .frame(width: 54, height: 54)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
                
                // Channel Info & EPG
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(channel.displayName)
                            .appFont(size: 14, weight: .bold)
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        LiveBadge()
                    }
                    
                    // No EPG source is available for these channels, so nothing is
                    // claimed about what is currently airing. Inventing a schedule
                    // looked richer but told the user things that were not true.
                    if let group = channel.group, !group.isEmpty {
                        Text(group)
                            .appFont(size: 12)
                            .foregroundColor(AppTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                
                // Quick Play Action
                Image(systemName: "play.circle.fill")
                    .appFont(size: 26)
                    .foregroundColor(AppTheme.cyanAccent)
            }
            .padding(12)
            .glassCard(cornerRadius: 14)
            .contextMenu {
                if channel.id.hasPrefix("m3u_") {
                    Button(role: .destructive, action: {
                        viewModel.deleteCustomChannel(id: channel.id)
                    }) {
                        Label(L("Sender entfernen"), systemImage: "trash")
                    }
                }
            }
        }
    }
    
    private func playChannel(_ channel: MediaItem) {
        // Channel URLs usually still need the addon's resolve action, and a dead channel
        // should fall through to any alternative the item carries — both live in AppState.
        var sources: [MediaSource] = []
        if let directUrlStr = channel.url, !directUrlStr.isEmpty {
            sources.append(MediaSource(url: directUrlStr, name: .single(channel.displayName)))
        }
        sources.append(contentsOf: channel.sources ?? [])
        guard !sources.isEmpty else { return }

        Task {
            await appState.beginPlayback(item: channel, sources: sources)
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .appFont(size: 44)
                .foregroundColor(AppTheme.textTertiary)
            
            Text(L("Keine Live-Sender verfügbar"))
                .appFont(size: 16, weight: .bold)
                .foregroundColor(AppTheme.textPrimary)
            
            Text(L("Installiere ein IPTV-fähiges MediaHub-Addon in den Einstellungen oder importiere eine eigene M3U-Wiedergabeliste."))
                .appFont(size: 13)
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button(action: { showImportSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text(L("M3U Playlist importieren"))
                }
                .appFont(size: 14, weight: .semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(AppTheme.cyanAccent)
                )
            }
            .padding(.top, 8)
            
            Spacer()
        }
    }
}

// MARK: - M3U Import Sheet
public struct ImportM3USheetView: View {
    @ObservedObject var viewModel: LiveTVViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var mode: Int = 0 // 0 = URL, 1 = Raw Text
    @State private var urlText: String = ""
    @State private var m3uContent: String = ""
    @State private var isProcessing: Bool = false
    @State private var statusMessage: String? = nil
    @State private var isSuccess: Bool = false
    
    public init(viewModel: LiveTVViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        Picker(L("Quelle"), selection: $mode) {
                            Text(L("URL-Link")).tag(0)
                            Text(L("M3U Text")).tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        
                        if mode == 0 {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L("M3U / M3U8 Wiedergabeliste URL"))
                                    .appFont(size: 13, weight: .semibold)
                                    .foregroundColor(AppTheme.textSecondary)
                                
                                HStack {
                                    Image(systemName: "link")
                                        .foregroundColor(AppTheme.textTertiary)
                                    TextField("https://example.com/playlist.m3u", text: $urlText)
                                        .appFont(size: 14)
                                        .foregroundColor(AppTheme.textPrimary)
                                        .urlField()
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.surface))
                            }
                            .padding(.horizontal, 16)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L("M3U Inhalt einfügen"))
                                    .appFont(size: 13, weight: .semibold)
                                    .foregroundColor(AppTheme.textSecondary)
                                
                                TextEditor(text: $m3uContent)
                                    .frame(minHeight: 180)
                                    .appFont(size: 13, design: .monospaced)
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.surface))
                            }
                            .padding(.horizontal, 16)
                        }
                        
                        if let status = statusMessage {
                            HStack(spacing: 8) {
                                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(isSuccess ? AppTheme.success : AppTheme.destructive)
                                Text(status)
                                    .appFont(size: 13, weight: .medium)
                                    .foregroundColor(isSuccess ? AppTheme.success : AppTheme.destructive)
                            }
                            .padding(.horizontal, 16)
                        }
                        
                        Button(action: handleImport) {
                            HStack {
                                if isProcessing {
                                    ProgressView()
                                        .tint(.white)
                                        .padding(.trailing, 4)
                                }
                                Text(L("Wiedergabeliste importieren"))
                                    .appFont(size: 15, weight: .bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(isButtonDisabled ? AppTheme.surfaceLight : AppTheme.cyanAccent)
                            )
                            .foregroundColor(isButtonDisabled ? AppTheme.textTertiary : .white)
                        }
                        .disabled(isButtonDisabled || isProcessing)
                        .padding(.horizontal, 16)
                        
                        if !StorageService.shared.customIPTVChannels.isEmpty {
                            Divider()
                                .padding(.vertical, 8)
                            
                            Button(role: .destructive, action: {
                                viewModel.clearAllCustomChannels()
                                statusMessage = L("Alle benutzerdefinierten Sender wurden entfernt.")
                                isSuccess = true
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                    // Only the static half is the lookup key; the count is
                                    // appended, so there is one entry per message rather
                                    // than one per possible number.
                                    Text("\(L("Alle importierten Sender löschen")) (\(StorageService.shared.customIPTVChannels.count))")
                                }
                                .appFont(size: 13, weight: .medium)
                                .foregroundColor(AppTheme.destructive)
                            }
                        }
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle(L("M3U Wiedergabeliste"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Schließen")) {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
    }
    
    private var isButtonDisabled: Bool {
        if mode == 0 {
            return urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            return m3uContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    private func handleImport() {
        isProcessing = true
        statusMessage = nil
        
        let input = mode == 0 ? urlText : m3uContent
        
        Task {
            do {
                let count = try await viewModel.importM3U(from: input)
                isSuccess = true
                statusMessage = "\(count) \(L("Sender erfolgreich importiert!"))"
                if count > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        dismiss()
                    }
                }
            } catch {
                isSuccess = false
                statusMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }
}

