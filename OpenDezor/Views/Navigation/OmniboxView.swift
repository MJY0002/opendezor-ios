import SwiftUI

public struct OmniboxView: View {
    @ObservedObject var viewModel: OmniboxViewModel
    @ObservedObject var appState: AppState = .shared
    @FocusState private var isFieldFocused: Bool
    
    public init(viewModel: OmniboxViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Omnibar Address Input
            HStack(spacing: 10) {
                Image(systemName: viewModel.isInputUrl(viewModel.inputQuery) ? "globe" : "magnifyingglass")
                    .foregroundColor(AppTheme.textSecondary)
                    .appFont(size: 16)
                
                TextField(L("Addon-URL oder suchen"), text: $viewModel.inputQuery)
                    .appFont(size: 14)
                    .foregroundColor(AppTheme.textPrimary)
                    .urlField()
                    .submitLabel(.go)
                    .focused($isFieldFocused)
                    .onSubmit {
                        Task {
                            await viewModel.handleInputSubmit()
                        }
                    }
                
                if !viewModel.inputQuery.isEmpty {
                    ClearFieldButton(size: 16) {
                        viewModel.clear()
                    }
                }
                
                if viewModel.isCheckingAddon {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(AppTheme.cyanAccent)
                } else if !viewModel.inputQuery.isEmpty {
                    Button(action: {
                        isFieldFocused = false
                        Task {
                            await viewModel.handleInputSubmit()
                        }
                    }) {
                        Text(viewModel.isInputUrl(viewModel.inputQuery) ? L("Öffnen") : L("Suchen"))
                            .appFont(size: 13, weight: .bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppTheme.accentGradient)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassCard(cornerRadius: 18, fillColor: AppTheme.surface.opacity(0.85))
            // The bare TextField only takes focus on a hit inside its own glyph bounds,
            // which in this row is a thin strip. Make the whole bar the tap target.
            .contentShape(Rectangle())
            .onTapGesture {
                isFieldFocused = true
            }
            
            // Addon Installation Prompt Card
            if let manifest = viewModel.detectedAddonManifest {
                addonPromptView(manifest: manifest)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Not an addon, but a valid address: offer the browser instead of dead-ending.
            if let pending = viewModel.pendingBrowserUrl {
                Button(action: {
                    appState.pendingBrowserUrl = pending
                    appState.selectedTab = .browser
                    viewModel.clear()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "globe")
                            .foregroundColor(AppTheme.cyanAccent)
                        Text(L("Im Browser öffnen"))
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .padding(12)
                    .background(AppTheme.surface)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            // Error Message
            if let err = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(AppTheme.destructive)
                    Text(err)
                        .appFont(size: 12)
                        .foregroundColor(AppTheme.destructive)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassCard(cornerRadius: 12, strokeColor: AppTheme.destructive.opacity(0.3))
            }
            
            // Recent Searches Chips (when query is empty and focused)
            if viewModel.inputQuery.isEmpty && !viewModel.recentSearches.isEmpty && isFieldFocused {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Letzte Suchen"))
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(AppTheme.textTertiary)
                        .padding(.horizontal, 4)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.recentSearches, id: \.self) { search in
                                Button(action: {
                                    viewModel.openSearchPage(query: search)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .appFont(size: 11)
                                        Text(search)
                                            .appFont(size: 12)
                                    }
                                    .foregroundColor(AppTheme.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(AppTheme.surfaceLight))
                                }
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Addon Detected Banner View
    @ViewBuilder
    private func addonPromptView(manifest: AddonManifest) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill")
                .appFont(size: 24)
                .foregroundColor(AppTheme.cyanAccent)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(L("MediaHub Addon gefunden"))
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(AppTheme.cyanAccent)
                
                Text(manifest.name.value.isEmpty ? manifest.id : manifest.name.value)
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(AppTheme.textPrimary)
                
                if let desc = manifest.description?.value, !desc.isEmpty {
                    Text(desc)
                        .appFont(size: 11)
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button(action: {
                Task {
                    let success = await viewModel.installDetectedAddon()
                    if success {
                        appState.showToast(message: L("Addon erfolgreich installiert!"), icon: "checkmark.circle.fill")
                    }
                }
            }) {
                Text(L("Installieren"))
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppTheme.cyanGradient)
                    .cornerRadius(12)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16, strokeColor: AppTheme.cyanAccent.opacity(0.4), fillColor: AppTheme.surface.opacity(0.95))
    }
}
