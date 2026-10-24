import SwiftUI

@MainActor
public struct AccountView: View {
    @ObservedObject var authService: DezorAuthService = .shared
    @ObservedObject var appState: AppState = .shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var viewMode: ViewMode = .connect
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var manualToken: String = ""
    @State private var showCopiedAlert: Bool = false
    @State private var confirmLogout: Bool = false
    @State private var showForgotPasswordHelp: Bool = false
    @State private var localErrorMessage: String? = nil
    
    public enum ViewMode {
        case connect
        case email
        case token
    }
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                // Ambient glow
                VStack {
                    HStack {
                        Circle()
                            .fill(AppTheme.primaryAccent.opacity(0.12))
                            .frame(width: 250, height: 250)
                            .blur(radius: 70)
                            .offset(x: -80, y: -60)
                        Spacer()
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
                
                ScrollView {
                    VStack(spacing: 20) {
                        if authService.isLoggedIn, let user = authService.currentUser {
                            loggedInCard(for: user)
                        } else {
                            authCard
                        }
                        // Users should know who they are signing in with: the account is
                        // Dezor's, and this app only passes the credentials through.
                        Text(L("Die Anmeldung erfolgt direkt bei Dezor (dezor.net). OpenDezor ist ein inoffizieller Client und speichert dein Passwort nicht; es gelten Dezors Nutzungsbedingungen und Datenschutzhinweise."))
                            .appFont(size: 11)
                            .foregroundColor(AppTheme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(L("Dezor Account"))
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
            .onAppear {
                if !authService.isLoggedIn {
                    authService.startConnectCodePolling()
                }
            }
            .onDisappear {
                authService.stopConnectCodePolling()
            }
        }
    }
    
    // MARK: - Auth Card Container (Switchable between Connect, Email, Token)
    @ViewBuilder
    private var authCard: some View {
        VStack(spacing: 20) {
            // Mode Header
            HStack {
                if viewMode != .connect {
                    Button(action: {
                        withAnimation(AppMotion.standard) {
                            viewMode = .connect
                            localErrorMessage = nil
                        }
                    }) {
                        Image(systemName: "arrow.left")
                            .appFont(size: 16, weight: .semibold)
                            .foregroundColor(AppTheme.textSecondary)
                            .padding(6)
                    }
                }
                
                Spacer()
                
                Text(headerTitle)
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                if viewMode != .connect {
                    // Balancing spacer for the back button
                    Color.clear.frame(width: 28, height: 28)
                }
            }
            .padding(.bottom, 4)
            
            // Body Content based on mode
            switch viewMode {
            case .connect:
                dezorConnectView
            case .email:
                dezorEmailLoginView
            case .token:
                dezorManualTokenView
            }
        }
        .padding(22)
        .background(AppTheme.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.surfaceBorder, lineWidth: 1)
        )
    }
    
    private var headerTitle: String {
        switch viewMode {
        case .connect: return L("Gerät verknüpfen")
        case .email: return L("Anmelden")
        case .token: return "Token eingeben"
        }
    }
    
    // MARK: - 1. Connect Mode (macOS Dezor Style)
    @ViewBuilder
    private var dezorConnectView: some View {
        VStack(spacing: 18) {
            Text(L("1. Öffne auf deinem Computer oder im Browser:"))
                .appFont(size: 13, weight: .medium)
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            
            // External URL Box
            Button(action: {
                if let url = URL(string: authService.connectUrlString) {
                    #if os(iOS)
                    UIApplication.shared.open(url)
                    #endif
                }
            }) {
                HStack(spacing: 6) {
                    Text("dezor.net/connect")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(AppTheme.textPrimary)
                    Image(systemName: "arrow.up.right")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(AppTheme.cyanAccent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AppTheme.background)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.surfaceBorder, lineWidth: 1)
                )
            }
            
            Text(L("2. Gib den folgenden Code ein:"))
                .appFont(size: 13, weight: .medium)
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            
            // 4-Digit Code Box (Clean, Large, Short)
            Button(action: {
                #if os(iOS)
                UIPasteboard.general.string = authService.connectCode
                #endif
                showCopiedAlert = true
                appState.showToast(message: L("Code kopiert!"), icon: "doc.on.doc.fill")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showCopiedAlert = false
                }
            }) {
                ZStack {
                    Text(authService.connectCode.isEmpty ? "•••••" : authService.connectCode)
                        .appFont(size: 32, weight: .black, design: .monospaced)
                        .foregroundColor(authService.connectCode.isEmpty ? AppTheme.textTertiary : AppTheme.cyanAccent)
                        .kerning(8)
                    
                    HStack {
                        Spacer()
                        Text(showCopiedAlert ? "✓" : L("Kopieren"))
                            .appFont(size: 11, weight: .semibold)
                            .foregroundColor(showCopiedAlert ? Color.green : AppTheme.textTertiary)
                            .padding(.trailing, 14)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppTheme.background)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.cyanAccent.opacity(0.4), lineWidth: 1.5)
                )
            }
            
            // Polling Indicator
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(AppTheme.cyanAccent)
                Text(L("Warte auf Bestätigung auf dezor.net..."))
                    .appFont(size: 12)
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(.top, 2)
            
            Divider().background(AppTheme.surfaceBorder).padding(.vertical, 4)
            
            // Switch to Email Login
            Button(action: {
                withAnimation(AppMotion.standard) {
                    viewMode = .email
                    localErrorMessage = nil
                }
            }) {
                HStack {
                    Image(systemName: "envelope.fill")
                    Text(L("Mit E-Mail anmelden"))
                }
                .appFont(size: 14, weight: .semibold)
                .foregroundColor(AppTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.surfaceLight)
                .cornerRadius(10)
            }
            
            // Switch to Token Login
            Button(action: {
                withAnimation(AppMotion.standard) {
                    viewMode = .token
                    localErrorMessage = nil
                }
            }) {
                Text(L("Token oder Voucher manuell eingeben"))
                    .appFont(size: 12)
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
    }
    
    // MARK: - 2. Email Login Mode (Exact macOS App Reproduction)
    @ViewBuilder
    private var dezorEmailLoginView: some View {
        VStack(spacing: 14) {
            // Email Input Row (matches macOS mail-outline in background3)
            HStack(spacing: 12) {
                Image(systemName: "envelope")
                    .appFont(size: 17)
                    .foregroundColor(AppTheme.textTertiary)
                    .frame(width: 24)
                
                TextField(L("E-Mail-Adresse"), text: $email)
                    .appFont(size: 14)
                    .foregroundColor(AppTheme.textPrimary)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    #endif
                
                if !email.isEmpty {
                    ClearFieldButton { email = "" }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(AppTheme.background)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppTheme.surfaceBorder, lineWidth: 1)
            )
            
            // Password Input Row (matches macOS key-outline in background3)
            HStack(spacing: 12) {
                Image(systemName: "key")
                    .appFont(size: 17)
                    .foregroundColor(AppTheme.textTertiary)
                    .frame(width: 24)
                
                SecureField(L("Passwort"), text: $password)
                    .appFont(size: 14)
                    .foregroundColor(AppTheme.textPrimary)
                
                if !password.isEmpty {
                    ClearFieldButton { password = "" }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(AppTheme.background)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppTheme.surfaceBorder, lineWidth: 1)
            )
            
            // Error Display (as in macOS Dezor)
            if let err = localErrorMessage ?? authService.errorMessage {
                Text(err)
                    .appFont(size: 12, weight: .medium)
                    .foregroundColor(AppTheme.destructive)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }
            
            // Primary Login Button (Full width, rounded 14 as in macOS)
            Button(action: {
                performEmailLogin()
            }) {
                HStack(spacing: 8) {
                    if authService.isAuthenticating {
                        ProgressView().tint(.white)
                    } else {
                        Text(L("Anmelden"))
                            .appFont(size: 15, weight: .bold)
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.accentGradient)
                .cornerRadius(12)
                .shadow(color: AppTheme.primaryAccent.opacity(0.35), radius: 8, x: 0, y: 3)
            }
            .disabled(authService.isAuthenticating)
            
            // Forgot Password Link
            Button(action: {
                withAnimation(AppMotion.standard) {
                    showForgotPasswordHelp.toggle()
                }
            }) {
                Text(L("Passwort vergessen?"))
                    .appFont(size: 13)
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(.top, 4)
            }
            
            if showForgotPasswordHelp {
                VStack(spacing: 6) {
                    Text(L("Falls du dein Passwort vergessen hast, besuche bitte:"))
                        .appFont(size: 12)
                        .foregroundColor(AppTheme.textSecondary)
                    
                    Link("dezor.net/password-reset", destination: URL(string: "https://www.dezor.net")!)
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(AppTheme.cyanAccent)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(AppTheme.background)
                .cornerRadius(8)
                .transition(.opacity)
            }
        }
    }
    
    // MARK: - 3. Manual Token Mode
    @ViewBuilder
    private var dezorManualTokenView: some View {
        VStack(spacing: 14) {
            Text(L("Gib deinen Dezor Authentifizierungs-Token ein:"))
                .appFont(size: 12)
                .foregroundColor(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            TextField("Bearer eyJ...", text: $manualToken)
                .appFont(size: 12, design: .monospaced)
                .foregroundColor(AppTheme.textPrimary)
                .padding(12)
                .background(AppTheme.background)
                .cornerRadius(10)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.surfaceBorder, lineWidth: 1)
                )
            
            Button(action: {
                let entered = manualToken
                Task {
                    do {
                        try await authService.setManualToken(entered)
                        manualToken = ""
                        appState.showToast(message: L("Token verifiziert und aktiviert!"), icon: "checkmark.circle.fill")
                    } catch {
                        appState.showToast(message: error.localizedDescription, isError: true)
                    }
                }
            }) {
                Text(L("Token speichern & Freischalten"))
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accentGradient)
                    .cornerRadius(12)
            }
            .disabled(manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    
    // MARK: - Logged In View
    @ViewBuilder
    private func loggedInCard(for user: DezorUser) -> some View {
        VStack(spacing: 18) {
            // Status Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accentGradient)
                        .frame(width: 50, height: 50)
                    Image(systemName: "shield.checkered")
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("Dezor Premium"))
                            .appFont(size: 18, weight: .bold)
                            .foregroundColor(AppTheme.textPrimary)
                        
                        Text(L("AKTIV"))
                            .appFont(size: 10, weight: .black)
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(6)
                    }
                    
                    Text(L("Unbegrenzter VPN- & Stream-Zugang"))
                        .appFont(size: 13)
                        .foregroundColor(AppTheme.cyanAccent)
                }
                Spacer()
            }
            .padding(.bottom, 8)
            
            Divider().background(AppTheme.surfaceBorder)
            
            // Details
            VStack(spacing: 12) {
                // Only values the backend actually reports. "VPN Bandbreite: Unbegrenzt"
                // and "Token-Status: Aktiv" were fixed strings backed by nothing.
                infoRow(title: L("Account"), value: user.email ?? L("Angemeldet"))
                infoRow(title: L("Gültig bis"), value: user.formattedExpiryDate)
                infoRow(title: L("Verbleibende Wiedergabezeit"), value: user.formattedRemainingPlayTime)
            }
            
            Divider().background(AppTheme.surfaceBorder)
            
            // Logout Button
            Button(action: { confirmLogout = true }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text(L("Abmelden"))
                }
                .appFont(size: 14, weight: .semibold)
                .foregroundColor(AppTheme.destructive)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.surface)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.destructive.opacity(0.4), lineWidth: 1)
                )
            }
            .confirmationDialog(L("Wirklich abmelden?"), isPresented: $confirmLogout, titleVisibility: .visible) {
                Button(L("Abmelden"), role: .destructive) {
                    Task { await authService.logout() }
                    appState.showToast(message: L("Abgemeldet."))
                }
                Button(L("Abbrechen"), role: .cancel) {}
            }
        }
        .padding(20)
        .background(AppTheme.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.cyanAccent.opacity(0.3), lineWidth: 1.5)
        )
    }
    
    // MARK: - Validation & Login Execution (macOS Dezor Logic)
    /// `DezorAuthService.login` trims and validates both fields itself and throws a
    /// localized message, so this only has to surface whatever comes back.
    private func performEmailLogin() {
        localErrorMessage = nil
        Task {
            do {
                try await authService.login(email: email, password: password)
                appState.showToast(message: L("Erfolgreich angemeldet!"), icon: "checkmark.circle.fill")
                dismiss()
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }
    
    @ViewBuilder
    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .appFont(size: 13)
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .appFont(size: 13, weight: .medium)
                .foregroundColor(AppTheme.textPrimary)
        }
    }
}
