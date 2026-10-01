import SwiftUI

@MainActor
public struct SettingsView: View {
    @ObservedObject var addonManager: AddonManager = .shared
    @ObservedObject var storage: StorageService = .shared
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var authService: DezorAuthService = .shared
    /// Observed, not read through `.shared` — otherwise the Aktiv/Aus label goes stale.
    @ObservedObject var vpnManager: VPNManager = .shared

    /// Read from the bundle so the displayed version tracks the actual build.
    static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (Build \(build))"
    }

    @State private var newAddonUrl: String = ""
    @State private var isAddingAddon: Bool = false
    @State private var showClearHistoryAlert: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                List {
                    // Dezor Account & Unlimited VPN Section
                    Section {
                        NavigationLink(destination: AccountView()) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(authService.hasUnlimitedVPN ? AppTheme.accentGradient : LinearGradient(colors: [AppTheme.surfaceBorder, AppTheme.surface], startPoint: .top, endPoint: .bottom))
                                        .frame(width: 42, height: 42)
                                    Image(systemName: authService.hasUnlimitedVPN ? "shield.checkered" : "lock.shield")
                                        .appFont(size: 20, weight: .bold)
                                        .foregroundColor(authService.hasUnlimitedVPN ? .white : AppTheme.textSecondary)
                                }
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(authService.isLoggedIn ? (authService.currentUser?.email ?? L("Dezor Account")) : L("Dezor Account & VPN"))
                                            .appFont(size: 15, weight: .bold)
                                            .foregroundColor(AppTheme.textPrimary)
                                        
                                        if authService.hasUnlimitedVPN {
                                            Text(L("PREMIUM"))
                                                .appFont(size: 9, weight: .black)
                                                .foregroundColor(.black)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.green)
                                                .cornerRadius(4)
                                        }
                                    }
                                    
                                    Text(authService.hasUnlimitedVPN ? L("Unbegrenzter VPN & Stream-Zugang aktiv") : L("Anmelden für unbegrenzten VPN-Zugang"))
                                        .appFont(size: 12)
                                        .foregroundColor(authService.hasUnlimitedVPN ? AppTheme.cyanAccent : AppTheme.textTertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text(L("Dezor Mitgliedschaft"))
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .listRowBackground(AppTheme.surface)
                    
                    // Add New Addon Section
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("Neues Addon hinzufügen"))
                                .appFont(size: 14, weight: .semibold)
                                .foregroundColor(AppTheme.textPrimary)
                            
                            HStack(spacing: 8) {
                                TextField(L("Addon-URL (z.B. https://.../mediahubmx.json)"), text: $newAddonUrl)
                                    .appFont(size: 13)
                                    .foregroundColor(AppTheme.textPrimary)
                                    .urlField()
                                
                                if isAddingAddon {
                                    ProgressView()
                                        .tint(AppTheme.cyanAccent)
                                } else {
                                    Button(L("Installieren")) {
                                        installAddon()
                                    }
                                    .appFont(size: 13, weight: .bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(AppTheme.accentGradient)
                                    .cornerRadius(10)
                                    .disabled(newAddonUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text(L("Addon-Installation"))
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .listRowBackground(AppTheme.surface)
                    
                    // Installed Addons Section
                    Section {
                        if storage.savedAddons.isEmpty {
                            Text(L("Noch keine Addons installiert."))
                                .appFont(size: 13)
                                .foregroundColor(AppTheme.textTertiary)
                        } else {
                            ForEach(storage.savedAddons) { addon in
                                addonRow(for: addon)
                            }
                        }
                    } header: {
                        Text("\(L("Installierte Addons")) (\(storage.savedAddons.count))")
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(AppTheme.textSecondary)
                    } footer: {
                        Text(L("Wische nach links, um ein Addon zu deinstallieren."))
                            .appFont(size: 11)
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .listRowBackground(AppTheme.surface)
                    
                    // Appearance & Language Section
                    Section {
                        Picker(selection: Binding(
                            get: { storage.settings.language },
                            set: { lang in storage.update { $0.language = lang } }
                        )) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        } label: {
                            settingsLabel(icon: "globe", title: L("Sprache"))
                        }

                        Picker(selection: Binding(
                            get: { storage.settings.colorScheme },
                            set: { scheme in storage.update { $0.colorScheme = scheme } }
                        )) {
                            ForEach(AppColorScheme.allCases) { scheme in
                                Text(scheme.displayName).tag(scheme)
                            }
                        } label: {
                            settingsLabel(icon: "circle.lefthalf.filled", title: L("Farbschema"))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            settingsLabel(icon: "paintpalette.fill", title: L("Akzentfarbe"))
                            HStack(spacing: 12) {
                                ForEach(AppAccent.allCases) { accent in
                                    let selected = storage.settings.accent == accent
                                    Button(action: { storage.update { $0.accent = accent } }) {
                                        Circle()
                                            .fill(accent.previewGradient)
                                            .frame(width: 34, height: 34)
                                            .overlay(
                                                Circle()
                                                    .stroke(AppTheme.textPrimary, lineWidth: selected ? 2.5 : 0)
                                                    .padding(-3)
                                            )
                                            .overlay(
                                                Image(systemName: "checkmark")
                                                    .appFont(size: 13, weight: .bold)
                                                    .foregroundColor(.white)
                                                    .opacity(selected ? 1 : 0)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(accent.displayName)
                                }
                                Spacer()
                            }
                        }
                        .padding(.vertical, 4)
                        Toggle(isOn: Binding(
                            get: { storage.settings.useImageProxy },
                            set: { v in storage.update { $0.useImageProxy = v } }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                settingsLabel(icon: "photo.stack.fill", title: L("Bilder über Dezor-Cache laden"))
                                Text(L("Kleinere Bilder, schnellerer Aufbau. Bild-Adressen werden dabei an dezor.net gesendet."))
                                    .appFont(size: 11)
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                        }
                    } header: {
                        Text(L("Darstellung"))
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .listRowBackground(AppTheme.surface)

                    // Playback Section
                    Section {
                        Toggle(isOn: Binding(
                            get: { storage.settings.autoPlayNextEpisode },
                            set: { v in storage.update { $0.autoPlayNextEpisode = v } }
                        )) {
                            settingsLabel(icon: "forward.end.fill", title: L("Nächste Episode automatisch abspielen"))
                        }

                        Picker(selection: Binding(
                            get: { storage.settings.defaultQuality },
                            set: { v in storage.update { $0.defaultQuality = v } }
                        )) {
                            ForEach(["2160p", "1080p", "720p", "480p"], id: \.self) { Text($0).tag($0) }
                        } label: {
                            settingsLabel(icon: "dial.high.fill", title: L("Bevorzugte Qualität"))
                        }

                        Picker(selection: Binding(
                            get: { storage.settings.preferredAudioLanguage },
                            set: { v in storage.update { $0.preferredAudioLanguage = v } }
                        )) {
                            Text("Deutsch").tag("de")
                            Text("English").tag("en")
                        } label: {
                            settingsLabel(icon: "speaker.wave.2.fill", title: L("Bevorzugte Tonspur"))
                        }

                        Picker(selection: Binding(
                            get: { storage.settings.preferredSubtitleLanguage },
                            set: { v in storage.update { $0.preferredSubtitleLanguage = v } }
                        )) {
                            Text("Deutsch").tag("de")
                            Text("English").tag("en")
                        } label: {
                            settingsLabel(icon: "captions.bubble.fill", title: L("Bevorzugte Untertitel"))
                        }
                    } header: {
                        Text(L("Wiedergabe"))
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    // VPN & Privacy Section
                    Section {
                        NavigationLink(destination: VPNSettingsSheetView()) {
                            HStack {
                                settingsLabel(icon: "shield.lefthalf.filled", title: L("In-App VPN & Proxy Schutz"))
                                Spacer()
                                HStack(spacing: 5) {
                                    Text(vpnManager.isConnected ? vpnManager.selectedServer.flag : "")
                                    Text(vpnManager.isConnected ? L("Aktiv") : L("Aus"))
                                        .appFont(size: 13, weight: .bold)
                                        .foregroundColor(vpnManager.isConnected ? AppTheme.cyanAccent : AppTheme.textTertiary)
                                }
                            }
                        }
                        Toggle(isOn: Binding(
                            get: { storage.settings.vpnAutoConnect },
                            set: { value in storage.update { $0.vpnAutoConnect = value } }
                        )) {
                            settingsLabel(icon: "bolt.shield", title: L("Beim Start automatisch verbinden"))
                        }
                        .tint(AppTheme.primaryAccent)
                    } header: {
                        Text(L("VPN & Anonymität"))
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(AppTheme.textSecondary)
                    } footer: {
                        Text(L("Filme, Serien und Live-TV laufen nur über das VPN – auch der Videostream selbst. Gilt nur für diese App, nicht systemweit."))
                            .appFont(size: 11)
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .listRowBackground(AppTheme.surface)

                    // Security & Privacy Section
                    Section {
                        Toggle(isOn: Binding(
                            get: { storage.settings.requireBiometrics },
                            set: { v in
                                storage.update { $0.requireBiometrics = v }
                                if v {
                                    appState.authenticateBiometrics()
                                }
                            }
                        )) {
                            settingsLabel(icon: "faceid", title: L("App-Sperre (Face ID / Touch ID)"))
                        }
                    } header: {
                        Text(L("Sicherheit & Privatsphäre"))
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(AppTheme.textSecondary)
                    } footer: {
                        Text(L("Sperrt OpenDezor beim Verlassen der App und erfordert biometrische Authentifizierung."))
                            .appFont(size: 11)
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .listRowBackground(AppTheme.surface)

                    // Data & Privacy Section
                    Section {
                        Button(action: {
                            showClearHistoryAlert = true
                        }) {
                            HStack {
                                Text(L("Verlauf leeren"))
                                    .foregroundColor(AppTheme.destructive)
                                Spacer()
                                Text("\(storage.watchHistory.count) \(L("Einträge"))")
                                    .appFont(size: 12)
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                        }
                        
                        Button(action: {
                            appState.resetOnboarding()
                        }) {
                            HStack {
                                Text(L("Einführung & Onboarding anzeigen"))
                                    .foregroundColor(AppTheme.cyanAccent)
                                Spacer()
                                Image(systemName: "sparkles")
                                    .foregroundColor(AppTheme.cyanAccent)
                            }
                        }
                    } header: {
                        Text(L("Daten & Speicher"))
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .listRowBackground(AppTheme.surface)
                    
                    // App Information Section
                    Section {
                        HStack {
                            Text(L("Version"))
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                            Text(Self.appVersionString)
                                .appFont(size: 13)
                                .foregroundColor(AppTheme.textSecondary)
                        }

                        HStack {
                            Text(L("Protokoll"))
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                            Text("MediaHubMX")
                                .appFont(size: 13)
                                .foregroundColor(AppTheme.cyanAccent)
                        }

                        CreditsView()
                            .listRowInsets(EdgeInsets())
                        
                        HStack {
                            Text("Engine")
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                            Text("SwiftUI + AVFoundation")
                                .appFont(size: 13)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    } header: {
                        Text(L("Über OpenDezor"))
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(AppTheme.textSecondary)
                    } footer: {
                        Text(L("OpenDezor ist ein inoffizielles, unabhängiges Hobbyprojekt und steht in keiner Verbindung zu Dezor. „Dezor“ ist eine Marke ihres Inhabers. Konto, VPN-Server und Dienste gehören Dezor und unterliegen dessen Nutzungsbedingungen. Die App liefert keine Inhalte und keine Addons; für hinzugefügte Quellen und deren Nutzung ist allein der Nutzer verantwortlich."))
                            .appFont(size: 11)
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .listRowBackground(AppTheme.surface)
                }
                #if os(iOS)
                .scrollContentBackground(.hidden)
                #endif
            }
            .navigationTitle(L("Einstellungen"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .alert(L("Verlauf leeren?"), isPresented: $showClearHistoryAlert) {
                Button(L("Abbrechen"), role: .cancel) {}
                Button(L("Leeren"), role: .destructive) {
                    storage.clearHistory()
                    appState.showToast(message: L("Verlauf wurde geleert."))
                }
            } message: {
                Text(L("Möchtest du den gesamten Wiedergabeverlauf wirklich löschen?"))
            }
        }
    }
    
    @ViewBuilder
    private func addonRow(for addon: SavedAddon) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(addon.name)
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(AppTheme.textPrimary)
                Text(addon.url)
                    .appFont(size: 11)
                    .foregroundColor(AppTheme.textTertiary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { addon.isEnabled },
                set: { _ in addonManager.toggleAddon(id: addon.id) }
            ))
            .labelsHidden()
            .tint(AppTheme.cyanAccent)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                addonManager.removeAddon(id: addon.id)
                appState.showToast(message: L("Addon entfernt."))
            } label: {
                Label(L("Löschen"), systemImage: "trash")
            }
        }
    }
    
    private func installAddon() {
        let url = newAddonUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        
        isAddingAddon = true
        Task {
            do {
                let manifest = try await addonManager.addAddon(from: url)
                isAddingAddon = false
                newAddonUrl = ""
                appState.showToast(message: "\(L("Addon")) '\(manifest.name.value)' \(L("installiert!"))", icon: "checkmark.circle.fill")
            } catch {
                isAddingAddon = false
                appState.showToast(message: "Fehler: \(error.localizedDescription)", isError: true)
            }
        }
    }

    // MARK: - Appearance Helpers

    @ViewBuilder
    private func settingsLabel(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .appFont(size: 15)
                .foregroundColor(AppTheme.cyanAccent)
                .frame(width: 22)
            Text(title)
                .appFont(size: 14)
                .foregroundColor(AppTheme.textPrimary)
        }
    }

}
