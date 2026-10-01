import SwiftUI

@MainActor
public struct TracksSheetView: View {
    @ObservedObject var playerService: PlayerService
    @Environment(\.dismiss) private var dismiss
    
    public init(playerService: PlayerService) {
        self.playerService = playerService
    }
    
    public init() {
        self.init(playerService: .shared)
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                List {
                    // Audio Tracks Section
                    Section {
                        if playerService.availableAudioTracks.isEmpty {
                            Text(L("Keine alternativen Tonspuren verfügbar"))
                                .appFont(size: 13)
                                .foregroundColor(AppTheme.textTertiary)
                        } else {
                            ForEach(playerService.availableAudioTracks) { track in
                                Button(action: {
                                    playerService.selectAudioTrack(track)
                                }) {
                                    HStack {
                                        Text(track.displayName)
                                            .foregroundColor(AppTheme.textPrimary)
                                        Spacer()
                                        if playerService.selectedAudioTrack?.id == track.id {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(AppTheme.cyanAccent)
                                                .appFont(size: 14, weight: .bold)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(L("Tonspuren"))
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .listRowBackground(AppTheme.surface)
                    
                    // Subtitles Section
                    Section {
                        ForEach(playerService.availableSubtitles) { sub in
                            Button(action: {
                                playerService.selectSubtitle(sub)
                            }) {
                                HStack {
                                    Text(sub.displayName)
                                        .foregroundColor(AppTheme.textPrimary)
                                    if sub.isExternal {
                                        BadgeView(text: "EXT", color: AppTheme.secondaryAccent, size: .small)
                                    }
                                    Spacer()
                                    if playerService.selectedSubtitle?.id == sub.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(AppTheme.cyanAccent)
                                            .appFont(size: 14, weight: .bold)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(L("Untertitel"))
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .listRowBackground(AppTheme.surface)
                    
                    // Subtitle Delay / Sync Offset Section (when subtitles are active)
                    if let selected = playerService.selectedSubtitle, selected.id != "off" {
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(L("Zeitversatz (Sync)"))
                                        .appFont(size: 14)
                                        .foregroundColor(AppTheme.textPrimary)
                                    Spacer()
                                    Text(String(format: "%+.2f s", playerService.subtitleOffset))
                                        .appFont(size: 14, weight: .bold, design: .monospaced)
                                        .foregroundColor(playerService.subtitleOffset == 0 ? AppTheme.textSecondary : AppTheme.cyanAccent)
                                }
                                
                                HStack(spacing: 8) {
                                    Button("-1.0s") {
                                        playerService.subtitleOffset -= 1.0
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Button("-0.25s") {
                                        playerService.subtitleOffset -= 0.25
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Button(L("Reset")) {
                                        playerService.subtitleOffset = 0.0
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Button("+0.25s") {
                                        playerService.subtitleOffset += 0.25
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Button("+1.0s") {
                                        playerService.subtitleOffset += 1.0
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .appFont(size: 12, weight: .medium)
                            }
                            .padding(.vertical, 4)
                        } header: {
                            Text(L("Untertitel-Synchronisation"))
                                .appFont(size: 13, weight: .semibold)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .listRowBackground(AppTheme.surface)
                    }
                }
                #if os(iOS)
                .scrollContentBackground(.hidden)
                #endif
            }
            .navigationTitle(L("Audio & Untertitel"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Fertig")) {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.primaryAccent)
                }
            }
        }
    }
}
