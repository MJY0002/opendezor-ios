import SwiftUI

@MainActor
public struct OnboardingView: View {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var addonManager: AddonManager = .shared
    @ObservedObject var authService: DezorAuthService = .shared
    @ObservedObject var storage: StorageService = .shared
    @ObservedObject private var theme: ThemeController = .shared
    /// Compact height means phone landscape: the pages switch to a side-by-side layout
    /// and drop their vertical breathing room so the action bar stays on screen.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isCompactHeight: Bool { verticalSizeClass == .compact }
    
    @State private var customAddonUrl: String = ""
    @State private var isInstallingCustom: Bool = false
    @State private var showAccountSheet: Bool = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            
            // Background ambient glow
            ambientGlow
            
            VStack(spacing: 0) {
                // Top Skip Button
                HStack {
                    Spacer()
                    Button(L("Überspringen")) {
                        appState.completeOnboarding()
                    }
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
                
                // Page Content
                TabView(selection: $appState.onboardingStep) {
                    welcomeStepView.tag(0)
                    languageStepView.tag(1)
                    appearanceStepView.tag(2)
                    addonStepView.tag(3)
                    vpnStepView.tag(4)
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .always))
                #endif
                
                // Bottom Controls
                bottomActionBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, isCompactHeight ? 8 : 24)
            }
        }
        // The connect code is issued by the backend while polling, so only ask for one
        // once the user actually reaches the account step.
        .onChange(of: appState.onboardingStep) { _, step in
            if step == Self.lastStep && !authService.isLoggedIn {
                authService.startConnectCodePolling()
            } else {
                authService.stopConnectCodePolling()
            }
        }
        .onDisappear {
            authService.stopConnectCodePolling()
        }
    }
    
    /// Index of the final page; the action bar switches to "start" here.
    private static let lastStep = 4

    // MARK: - Step 2: Language

    private var languageStepView: some View {
        stepScaffold(
            icon: "globe",
            title: L("Wähle deine Sprache"),
            subtitle: L("Gilt für die Oberfläche und für Titel, Beschreibungen und Streams der Addons.")
        ) {
            VStack(spacing: 10) {
                ForEach(AppLanguage.allCases) { language in
                    selectableRow(
                        isSelected: storage.settings.language == language,
                        action: { storage.update { $0.language = language } }
                    ) {
                        HStack(spacing: 12) {
                            Group {
                                if language == .system {
                                    Image(systemName: "globe")
                                        .appFont(size: 20)
                                        .foregroundColor(AppTheme.cyanAccent)
                                } else {
                                    Text(language.flag).appFont(size: 22)
                                }
                            }
                            .frame(width: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(language.displayName)
                                    .appFont(size: 15, weight: .semibold)
                                    .foregroundColor(AppTheme.textPrimary)
                                Text(language == .system
                                     ? "\(language.protocolCode.uppercased()) · \(language.regionCode)"
                                     : language.regionCode)
                                    .appFont(size: 12)
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Step 3: Appearance

    private var appearanceStepView: some View {
        stepScaffold(
            icon: "paintbrush.fill",
            title: L("Wähle dein Aussehen"),
            subtitle: L("Farbschema und Akzentfarbe lassen sich jederzeit in den Einstellungen ändern.")
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Farbschema"))
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(AppTheme.textSecondary)

                    HStack(spacing: 10) {
                        ForEach(AppColorScheme.allCases) { scheme in
                            let selected = storage.settings.colorScheme == scheme
                            Button(action: { storage.update { $0.colorScheme = scheme } }) {
                                VStack(spacing: 6) {
                                    Image(systemName: scheme.iconName)
                                        .appFont(size: 20)
                                    Text(scheme.displayName)
                                        .appFont(size: 12, weight: .medium)
                                }
                                .foregroundColor(selected ? .white : AppTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(selected ? AnyShapeStyle(AppTheme.accentGradient)
                                                       : AnyShapeStyle(AppTheme.surface))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(selected ? Color.clear : AppTheme.surfaceBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Akzentfarbe"))
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(AppTheme.textSecondary)

                    HStack(spacing: 12) {
                        ForEach(AppAccent.allCases) { accent in
                            let selected = storage.settings.accent == accent
                            Button(action: { storage.update { $0.accent = accent } }) {
                                Circle()
                                    .fill(accent.previewGradient)
                                    .frame(width: 42, height: 42)
                                    .overlay(
                                        Circle()
                                            .stroke(AppTheme.textPrimary, lineWidth: selected ? 3 : 0)
                                            .padding(-4)
                                    )
                                    .overlay(
                                        Image(systemName: "checkmark")
                                            .appFont(size: 15, weight: .bold)
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

                // Live preview so the choice is visible before leaving the step
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Vorschau"))
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(AppTheme.textSecondary)
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.accentGradient)
                            .frame(width: 54, height: 76)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("OpenDezor")
                                .appFont(size: 15, weight: .bold)
                                .foregroundColor(AppTheme.textPrimary)
                            Text(L("Weiterschauen"))
                                .appFont(size: 12)
                                .foregroundColor(AppTheme.textSecondary)
                            Capsule()
                                .fill(AppTheme.accentGradient)
                                .frame(width: 96, height: 22)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(AppTheme.surface)
                    .cornerRadius(12)
                }
            }
        }
    }

    @ViewBuilder
    private func selectableRow<Content: View>(
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            HStack {
                content()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .appFont(size: 20)
                    .foregroundColor(isSelected ? AppTheme.cyanAccent : AppTheme.textTertiary.opacity(0.5))
            }
            .padding(14)
            .background(AppTheme.surface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? AppTheme.cyanAccent.opacity(0.6) : AppTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Shared frame for the two new steps so they match the existing pages.
    @ViewBuilder
    private func stepScaffold<Content: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        CenteredScroll {
            if isCompactHeight {
                HStack(alignment: .center, spacing: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: icon)
                            .appFont(size: 34)
                            .foregroundStyle(AppTheme.accentGradient)
                        Text(title)
                            .appFont(size: 20, weight: .bold)
                            .foregroundColor(AppTheme.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .appFont(size: 12)
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    content()
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            } else {
                // Staggered so the page assembles itself — icon, then heading, then the
                // controls — rather than appearing all at once.
                VStack(spacing: 22) {
                    Image(systemName: icon)
                        .appFont(size: 46)
                        .foregroundStyle(AppTheme.accentGradient)
                        .padding(.top, 12)
                        .appearsStaggered()

                    VStack(spacing: 8) {
                        Text(title)
                            .appFont(size: 24, weight: .bold)
                            .foregroundColor(AppTheme.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .appFont(size: 13)
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .appearsStaggered(delay: 0.08)

                    content()
                        .padding(.horizontal, 24)
                        .appearsStaggered(delay: 0.16)

                    Spacer(minLength: 20)
                }
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Ambient Background Glow
    private var ambientGlow: some View {
        VStack {
            HStack {
                Circle()
                    .fill(AppTheme.primaryAccent.opacity(0.18))
                    .frame(width: 300, height: 300)
                    .blur(radius: 80)
                    .offset(x: -100, y: -80)
                Spacer()
            }
            Spacer()
            HStack {
                Spacer()
                Circle()
                    .fill(AppTheme.cyanAccent.opacity(0.15))
                    .frame(width: 280, height: 280)
                    .blur(radius: 70)
                    .offset(x: 80, y: 50)
            }
        }
        .allowsHitTesting(false)
    }
    
    // MARK: - Step 1: Welcome
    private var welcomeStepView: some View {
        Group {
            if isCompactHeight {
                CenteredScroll {
                    HStack(alignment: .center, spacing: 28) {
                        VStack(spacing: 14) {
                            welcomeLogo
                            welcomeHeadline
                        }
                        .frame(maxWidth: .infinity)

                        welcomeFeatures
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
            } else {
                welcomePortrait
            }
        }
    }

    /// Scrolls when the content is taller than the screen, centres it when it is not.
    /// Landscape on a phone leaves so little height that plain top alignment clips the
    /// logo while wasting the lower half.
    private struct CenteredScroll<Content: View>: View {
        @ViewBuilder var content: Content

        var body: some View {
            GeometryReader { geo in
                ScrollView {
                    content
                        .frame(minHeight: geo.size.height)
                }
            }
        }
    }

    private var welcomePortrait: some View {
        VStack(spacing: 24) {
            Spacer()

            welcomeLogo
                .padding(.bottom, 8)

            welcomeHeadline

            welcomeFeatures
                .padding(.horizontal, 24)
                .padding(.top, 12)

            Spacer()
        }
    }

    private var welcomeLogo: some View {
        ZStack {
            Circle()
                .fill(AppTheme.accentGradient)
                .frame(width: 100, height: 100)
                .shadow(color: AppTheme.primaryAccent.opacity(0.6), radius: 24, x: 0, y: 8)

            Image(systemName: "play.tv.fill")
                .appFont(size: 46, weight: .bold)
                .foregroundColor(.white)
        }
    }

    private var welcomeHeadline: some View {
        VStack(spacing: 8) {
            Text(L("Willkommen bei"))
                .appFont(size: 16, weight: .medium)
                .foregroundColor(AppTheme.textSecondary)

            Text("OpenDezor")
                .appFont(size: 36, weight: .black)
                .foregroundStyle(AppTheme.cyanGradient)

            Text(L("Dein nativer MediaHub & Streaming Client für iOS"))
                .appFont(size: 14)
                .foregroundColor(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var welcomeFeatures: some View {
        VStack(spacing: 16) {
            featureRow(icon: "bolt.fill", title: L("Nativer AVPlayer"), desc: L("Hardware-beschleunigtes HLS/MP4 Streaming mit PiP & AirPlay"))
            featureRow(icon: "puzzlepiece.extension.fill", title: L("MediaHub-Addons"), desc: L("Universelle Integration aller MediaHub / Dezor Quellen"))
            featureRow(icon: "shield.checkered", title: L("VPN & Proxy"), desc: L("Unbegrenzter Stream-Zugang mit Dezor Account"))
        }
    }
    
    // MARK: - Step 2: Addons Setup
    //
    // Wrapped in CenteredScroll like the scaffolded steps: in landscape the available
    // height is roughly 390pt and a plain VStack simply clips, putting the URL field out
    // of reach with no way to scroll to it.
    private var addonStepView: some View {
        CenteredScroll {
        VStack(spacing: 20) {
            Spacer()
            
            VStack(spacing: 6) {
                Image(systemName: "square.grid.3x3.fill")
                    .appFont(size: 38)
                    .foregroundColor(AppTheme.cyanAccent)
                    .padding(.bottom, 4)
                
                Text(L("Addon einrichten"))
                    .appFont(size: 24, weight: .bold)
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(L("Füge eine MediaHub-Quelle hinzu, um Filme, Serien und Live-TV freizuschalten."))
                    .appFont(size: 13)
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            VStack(spacing: 14) {
                // No addon is suggested or preinstalled. Which sources exist, and whether
                // they may be used, is the user's decision — the app only provides the
                // means to add one.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .appFont(size: 13)
                            .foregroundColor(AppTheme.cyanAccent)
                        Text(L("Addons werden nicht mitgeliefert"))
                            .appFont(size: 13, weight: .bold)
                            .foregroundColor(AppTheme.textPrimary)
                    }
                    Text(L("Trage die Adresse einer MediaHub-Quelle ein, die du selbst gefunden hast. Im Browser-Tab erkennt die App passende Quellen automatisch und bietet sie zur Installation an."))
                        .appFont(size: 12)
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppTheme.surfaceBorder, lineWidth: 1)
                )

                // Custom Addon URL
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Addon-URL eingeben:"))
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(AppTheme.textTertiary)

                    HStack(spacing: 8) {
                        TextField("https://.../mediahubmx.json", text: $customAddonUrl)
                            .appFont(size: 13)
                            .foregroundColor(AppTheme.textPrimary)
                            .urlField()
                            .padding(10)
                            .background(AppTheme.background)
                            .cornerRadius(8)
                        
                        if isInstallingCustom {
                            ProgressView().tint(AppTheme.cyanAccent)
                        } else {
                            Button(L("Hinzufügen")) {
                                installAddon(url: customAddonUrl)
                            }
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(AppTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(AppTheme.surfaceLight)
                            .cornerRadius(8)
                            .disabled(customAddonUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .padding(14)
                .background(AppTheme.surface)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppTheme.surfaceBorder, lineWidth: 1)
                )
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        }
    }

    // MARK: - Step 3: Dezor Account / VPN
    private var vpnStepView: some View {
        CenteredScroll {
        VStack(spacing: 20) {
            Spacer()
            
            VStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .appFont(size: 40)
                    .foregroundColor(AppTheme.primaryAccent)
                    .padding(.bottom, 4)
                
                Text(L("Dezor VPN & Premium"))
                    .appFont(size: 24, weight: .bold)
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(L("Hast du einen bezahlten Dezor Account? Du kannst ihn jetzt verknüpfen, um ohne Zeitlimit unbegrenzt zu streamen."))
                    .appFont(size: 13)
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            if authService.isLoggedIn {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(Color.green)
                        Text("Verbunden als \(authService.currentUser?.email ?? "Premium User")")
                            .appFont(size: 14, weight: .semibold)
                            .foregroundColor(AppTheme.textPrimary)
                    }
                    Text(L("Unbegrenzter VPN-Zugang ist aktiv."))
                        .appFont(size: 12)
                        .foregroundColor(AppTheme.cyanAccent)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(AppTheme.surface)
                .cornerRadius(12)
                .padding(.horizontal, 24)
            } else {
                VStack(spacing: 12) {
                    // Connect Code Box
                    VStack(spacing: 6) {
                        Text(L("Connect-Code auf dezor.net:"))
                            .appFont(size: 12, weight: .medium)
                            .foregroundColor(AppTheme.textTertiary)
                        
                        Button(action: {
                            #if os(iOS)
                            UIPasteboard.general.string = authService.connectCode
                            #endif
                            appState.showToast(message: L("Code kopiert!"), icon: "doc.on.doc.fill")
                        }) {
                            HStack(spacing: 10) {
                                Text(authService.connectCode.isEmpty ? "•••••" : authService.connectCode)
                                    .appFont(size: 24, weight: .black, design: .monospaced)
                                    .foregroundColor(authService.connectCode.isEmpty ? AppTheme.textTertiary : AppTheme.cyanAccent)
                                    .kerning(4)
                                
                                Image(systemName: "doc.on.doc")
                                    .appFont(size: 13)
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(AppTheme.background)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(AppTheme.cyanAccent.opacity(0.4), lineWidth: 1)
                            )
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.surface)
                    .cornerRadius(12)
                    
                    // Or Button for Email Login Sheet
                    Button(action: {
                        showAccountSheet = true
                    }) {
                        HStack {
                            Image(systemName: "envelope.fill")
                            Text(L("Mit E-Mail & Passwort anmelden"))
                        }
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.surfaceLight)
                        .cornerRadius(10)
                    }
                    
                    Text(L("Du kannst die Anmeldung auch jederzeit später in den Einstellungen durchführen."))
                        .appFont(size: 11)
                        .foregroundColor(AppTheme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            // Last thing the user sees before entering the app. The bottom inset clears
            // the TabView's page indicator, which is drawn over this page.
            CreditsView()
                .padding(.bottom, 34)
        }
        }
        .sheet(isPresented: $showAccountSheet) {
            AccountView()
        }
    }
    
    // MARK: - Bottom Action Bar
    private var bottomActionBar: some View {
        HStack {
            if appState.onboardingStep > 0 {
                Button(action: {
                    withAnimation { appState.onboardingStep -= 1 }
                }) {
                    Text(L("Zurück"))
                        .appFont(size: 15, weight: .medium)
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
            
            Spacer()
            
            Button(action: {
                if appState.onboardingStep < Self.lastStep {
                    withAnimation { appState.onboardingStep += 1 }
                } else {
                    appState.completeOnboarding()
                }
            }) {
                HStack(spacing: 6) {
                    Text(appState.onboardingStep == Self.lastStep ? L("Jetzt starten") : L("Weiter"))
                        .appFont(size: 15, weight: .bold)
                    Image(systemName: appState.onboardingStep == Self.lastStep ? "sparkles" : "arrow.right")
                        .appFont(size: 13, weight: .bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(AppTheme.accentGradient)
                .cornerRadius(14)
                .shadow(color: AppTheme.primaryAccent.opacity(0.4), radius: 10, x: 0, y: 4)
            }
        }
    }
    
    // MARK: - Helper Views & Methods
    @ViewBuilder
    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.surface)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .appFont(size: 18)
                    .foregroundColor(AppTheme.cyanAccent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(AppTheme.textPrimary)
                Text(desc)
                    .appFont(size: 12)
                    .foregroundColor(AppTheme.textSecondary)
            }
            Spacer()
        }
    }
    
    private func installAddon(url: String) {
        let clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        isInstallingCustom = true

        Task {
            do {
                _ = try await addonManager.addAddon(from: clean)
                customAddonUrl = ""
                appState.showToast(message: L("Addon erfolgreich installiert!"), icon: "checkmark.seal.fill")
            } catch {
                appState.showToast(message: "\(L("Fehler")): \(error.localizedDescription)", isError: true)
            }
            isInstallingCustom = false
        }
    }
    
}
