import SwiftUI

public struct LibraryView: View {
    @ObservedObject var storage: StorageService = .shared
    @ObservedObject var addonManager: AddonManager = .shared
    @ObservedObject var appState: AppState = .shared
    
    @State private var selectedSegment: Int = 0
    @State private var installingAddonId: String? = nil
    @State private var customAddonUrl: String = ""
    public var onSelectMediaItem: (MediaItem) -> Void
    
    public init(onSelectMediaItem: @escaping (MediaItem) -> Void) {
        self.onSelectMediaItem = onSelectMediaItem
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 145, maximum: 190), spacing: 14)
    ]
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Segmented Picker
                    Picker("Kategorie", selection: $selectedSegment) {
                        Text("\(L("Favoriten")) (\(storage.favorites.count))").tag(0)
                        Text("\(L("Verlauf")) (\(storage.watchHistory.count))").tag(1)
                        Text(L("Addon-Katalog")).tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // Content Grid
                    if selectedSegment == 0 {
                        favoritesGrid
                    } else if selectedSegment == 1 {
                        historyGrid
                    } else {
                        communityCatalogGrid
                    }
                    
                    Spacer().frame(height: 80)
                }
            }
            .navigationTitle(L("Bibliothek"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
    
    // MARK: - Favorites Grid
    private var favoritesGrid: some View {
        ScrollView(.vertical, showsIndicators: true) {
            if storage.favorites.isEmpty {
                emptyState(title: L("Keine Favoriten gespeichert"), subtitle: L("Füge Filme und Serien über die Detailansicht zu deinen Favoriten hinzu."), icon: "bookmark")
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(storage.favorites) { fav in
                        let item = fav.asMediaItem

                        MediaCardView(item: item, shape: .portrait) {
                            onSelectMediaItem(item)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    // MARK: - History Grid
    private var historyGrid: some View {
        ScrollView(.vertical, showsIndicators: true) {
            if storage.watchHistory.isEmpty {
                emptyState(title: L("Kein Wiedergabeverlauf"), subtitle: "Hier erscheinen Titel, die du zuletzt angesehen hast.", icon: "clock.arrow.circlepath")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 14)], spacing: 16) {
                    ForEach(storage.watchHistory) { hist in
                        let item = hist.asMediaItem

                        MediaCardView(
                            item: item,
                            shape: .landscape,
                            progress: hist.progressRatio,
                            subtitleText: hist.episodeKey != nil ? "\(L("Staffel")) \(hist.season ?? 1), \(L("Folge")) \(hist.episode ?? 1)" : nil
                        ) {
                            onSelectMediaItem(item)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    @ViewBuilder
    private func emptyState(title: String, subtitle: String, icon: String) -> some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 60)
            Image(systemName: icon)
                .appFont(size: 40)
                .foregroundColor(AppTheme.textTertiary)
            
            Text(title)
                .appFont(size: 16, weight: .bold)
                .foregroundColor(AppTheme.textPrimary)
            
            Text(subtitle)
                .appFont(size: 13)
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Addon management
    //
    // No addon is suggested, bundled or preinstalled. Which sources exist — and whether
    // they may be used — is the user's call; this tab only manages what they added and
    // offers a field to add another.

    private var communityCatalogGrid: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Addon hinzufügen"))
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(AppTheme.textPrimary)

                    Text(L("Trage die Adresse einer MediaHub-Quelle ein. Im Browser-Tab erkennt die App passende Quellen automatisch, während du surfst."))
                        .appFont(size: 13)
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                addAddonField
                    .padding(.horizontal, 16)

                if !storage.savedAddons.isEmpty {
                    Text(L("Installierte Addons"))
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    VStack(spacing: 12) {
                        ForEach(storage.savedAddons) { addon in
                            installedAddonCard(addon: addon)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var addAddonField: some View {
        HStack(spacing: 8) {
            TextField("https://.../mediahubmx.json", text: $customAddonUrl)
                .appFont(size: 13)
                .foregroundColor(AppTheme.textPrimary)
                .urlField()
                .padding(10)
                .background(AppTheme.background)
                .cornerRadius(8)

            if installingAddonId == "manual" {
                ProgressView().tint(AppTheme.cyanAccent)
            } else {
                Button(L("Hinzufügen")) {
                    addAddonFromUrl()
                }
                .appFont(size: 12, weight: .bold)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(AppTheme.accentGradient))
                .disabled(customAddonUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 14)
    }
    
    @ViewBuilder
    private func installedAddonCard(addon: SavedAddon) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // The manifest ships an icon; show it rather than a generic symbol.
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.surfaceLight)
                    .frame(width: 44, height: 44)

                if let iconUrl = addon.iconUrl, !iconUrl.isEmpty {
                    CachedAsyncImage(url: iconUrl, proxySize: .small) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "puzzlepiece.extension.fill")
                            .appFont(size: 20, weight: .semibold)
                            .foregroundColor(AppTheme.cyanAccent)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .appFont(size: 20, weight: .semibold)
                        .foregroundColor(AppTheme.cyanAccent)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(addon.name)
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(AppTheme.textPrimary)

                Text(addon.url)
                    .appFont(size: 11, design: .monospaced)
                    .foregroundColor(AppTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(role: .destructive) {
                addonManager.removeAddon(id: addon.id)
            } label: {
                Image(systemName: "trash")
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(AppTheme.destructive)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
    }

    private func addAddonFromUrl() {
        let clean = customAddonUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        installingAddonId = "manual"
        Task {
            do {
                let manifest = try await addonManager.addAddon(from: clean)
                customAddonUrl = ""
                appState.showToast(
                    message: "\(manifest.displayName) \(L("erfolgreich installiert!"))",
                    icon: "checkmark.seal.fill"
                )
            } catch {
                appState.showToast(
                    message: "\(L("Fehler beim Installieren")): \(error.localizedDescription)",
                    isError: true
                )
            }
            installingAddonId = nil
        }
    }
}
