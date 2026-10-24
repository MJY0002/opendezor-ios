import SwiftUI

/// The VPN screen shown on launch and whenever a film is started without a tunnel.
///
/// Everything plays through the VPN (`AppState.playNextAvailableSource`), so connecting is
/// the first thing the app offers. "Später" lets the user browse without it; playback
/// brings this screen back.
public struct VPNGateView: View {
    @ObservedObject private var vpn: VPNManager = .shared
    @ObservedObject private var appState: AppState = .shared
    @ObservedObject private var storage: StorageService = .shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var pulse = false
    @State private var spin = false
    @State private var glow = false
    @State private var burst = false
    @State private var attempted = false

    public init() {}

    private var dezorServers: [VPNServerLocation] {
        vpn.availableServers.filter { !$0.isCustom }
    }

    public var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            RadialGradient(
                colors: [(vpn.isConnected ? AppTheme.success : AppTheme.primaryAccent).opacity(0.28), .clear],
                center: .top, startRadius: 20, endRadius: 520
            )
            .ignoresSafeArea()
            .animation(AppMotion.standard, value: vpn.isConnected)

            ScrollView(showsIndicators: false) {
                if verticalSizeClass == .compact {
                    // Landscape is too short for one column: the connect button would sit
                    // below the fold. Intro on the left, actions on the right.
                    HStack(alignment: .center, spacing: 32) {
                        VStack(spacing: 16) {
                            shield.appearsStaggered(delay: 0.05)
                            heading.appearsStaggered(delay: 0.15)
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 14) {
                            serverPicker.appearsStaggered(delay: 0.25)
                            connectButton.appearsStaggered(delay: 0.32)
                            autoConnectToggle.appearsStaggered(delay: 0.39)
                            laterButton.appearsStaggered(delay: 0.46)
                        }
                        .frame(maxWidth: 380)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 28) {
                        Spacer(minLength: 60)
                        shield.appearsStaggered(delay: 0.05)
                        heading.appearsStaggered(delay: 0.15)
                        serverPicker.appearsStaggered(delay: 0.25)
                        connectButton.appearsStaggered(delay: 0.32)
                        autoConnectToggle.appearsStaggered(delay: 0.39)
                        laterButton.appearsStaggered(delay: 0.46)
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { pulse = !reduceMotion }
        // Completion feedback on the frame the shield turns green.
        .sensoryFeedback(.success, trigger: vpn.isConnected) { _, connected in connected }
        .onChange(of: vpn.isConnected) { _, connected in
            // Connected through this screen: step aside on our own.
            guard connected, attempted else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                dismiss()
                appState.resumePendingPlaybackAfterVPN()
            }
        }
    }

    // MARK: Pieces

    private var shieldTint: Color { vpn.isConnected ? AppTheme.success : AppTheme.primaryAccent }

    private var shield: some View {
        ZStack {
            // Shock wave: two rings leave the shield on the frame the tunnel is proven.
            ForEach(0..<2, id: \.self) { ring in
                Circle()
                    .stroke(AppTheme.success, lineWidth: 2)
                    .frame(width: 118, height: 118)
                    .scaleEffect(burst ? 2.1 + CGFloat(ring) * 0.35 : 1)
                    .opacity(burst ? 0 : 0.8)
                    .opacity(vpn.isConnected ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 1.1).delay(Double(ring) * 0.18), value: burst)
            }

            // Soft glow in the state colour, breathing slowly.
            Circle()
                .fill(shieldTint.opacity(0.35))
                .frame(width: 170, height: 170)
                .blur(radius: 40)
                .scaleEffect(glow ? 1.08 : 0.92)
                .animation(reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: glow)

            // Orbit: a lit arc chases around the shield while connecting, so the wait
            // has visible progress instead of a frozen screen.
            Circle()
                .trim(from: 0, to: vpn.isConnected ? 1 : 0.28)
                .stroke(
                    AngularGradient(colors: [shieldTint.opacity(0), shieldTint], center: .center),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 150, height: 150)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .opacity(vpn.isConnecting || vpn.isConnected ? 1 : 0.25)
                .animation(AppMotion.standard, value: vpn.isConnected)

            Circle()
                .fill(AppTheme.surface)
                .frame(width: 118, height: 118)
                .overlay(Circle().strokeBorder(shieldTint.opacity(0.35), lineWidth: 1))
                .shadow(color: shieldTint.opacity(0.4), radius: 18)

            Image(systemName: vpn.isConnected ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                .appFont(size: 50, weight: .semibold)
                .foregroundStyle(shieldTint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: vpn.isConnected)
                .symbolEffect(.pulse, isActive: vpn.isConnecting && !reduceMotion)
        }
        .frame(width: 220, height: 220)
        .onAppear {
            guard !reduceMotion else { return }
            glow = true
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { spin = true }
        }
        .onChange(of: vpn.isConnected) { _, connected in
            guard connected, !reduceMotion else { return }
            burst = false
            DispatchQueue.main.async { burst = true }
        }
        .accessibilityHidden(true)
    }

    private var heading: some View {
        VStack(spacing: 10) {
            Text(vpn.isConnected ? L("Du bist geschützt") : L("Sicher streamen"))
                .appFont(size: 30, weight: .bold)
                .foregroundColor(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text(L("Filme, Serien und Live-TV laufen in OpenDezor ausschließlich über das VPN. Deine echte IP-Adresse bleibt für Hoster verborgen."))
                .appFont(size: 15)
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let ip = vpn.currentPublicIP, vpn.isConnected {
                Label("\(vpn.selectedServer.city) · \(ip)", systemImage: "globe")
                    .appFont(size: 13, weight: .semibold, design: .monospaced)
                    .foregroundColor(AppTheme.success)
                    .padding(.top, 2)
            } else if !vpn.statusMessage.isEmpty, attempted, !vpn.isConnecting {
                Text(vpn.statusMessage)
                    .appFont(size: 13, weight: .medium)
                    .foregroundColor(AppTheme.warning)
            }
        }
    }

    private var serverPicker: some View {
        Menu {
            ForEach(dezorServers) { server in
                Button {
                    vpn.selectServer(server)
                } label: {
                    Text("\(server.flag)  \(server.id == "auto" ? L("Automatisch") : "\(server.country) · \(server.city)")")
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text(vpn.selectedServer.flag).appFont(size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Server"))
                        .appFont(size: 11, weight: .semibold)
                        .foregroundColor(AppTheme.textTertiary)
                    Text(vpn.selectedServer.id == "auto"
                         ? "\(L("Automatisch"))\(vpn.selectedServer.city.isEmpty ? "" : " · \(vpn.selectedServer.city)")"
                         : "\(vpn.selectedServer.country) · \(vpn.selectedServer.city)")
                        .appFont(size: 15, weight: .semibold)
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AppTheme.surfaceBorder))
        }
        .disabled(dezorServers.isEmpty)
    }

    private var connectButton: some View {
        Button {
            if vpn.isConnected {
                dismiss()
            } else {
                attempted = true
                Task { await vpn.ensureConnected() }
            }
        } label: {
            HStack(spacing: 10) {
                if vpn.isConnecting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: vpn.isConnected ? "arrow.right" : "power")
                        .appFont(size: 16, weight: .bold)
                }
                Text(vpn.isConnecting ? L("Verbinde…") : (vpn.isConnected ? L("Weiter") : L("VPN verbinden")))
                    .appFont(size: 17, weight: .bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(vpn.isConnected ? AppTheme.success : AppTheme.primaryAccent)
            )
        }
        .buttonStyle(ScaleCardButtonStyle())
        .disabled(vpn.isConnecting)
    }

    private var autoConnectToggle: some View {
        Toggle(isOn: Binding(
            get: { storage.settings.vpnAutoConnect },
            set: { value in storage.update { $0.vpnAutoConnect = value } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Beim Start automatisch verbinden"))
                    .appFont(size: 15, weight: .semibold)
                    .foregroundColor(AppTheme.textPrimary)
                Text(L("Dieser Bildschirm wird dann übersprungen."))
                    .appFont(size: 12)
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .tint(AppTheme.primaryAccent)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.surface))
    }

    private var laterButton: some View {
        Button(L("Später – nur stöbern")) {
            appState.discardPendingPlaybackAfterVPN()
            dismiss()
        }
            .appFont(size: 14, weight: .medium)
            .foregroundColor(AppTheme.textSecondary)
            .padding(.vertical, 6)
            .opacity(vpn.isConnected ? 0 : 1)
    }

    private func dismiss() {
        withAnimation(AppMotion.standard) { appState.isVPNGatePresented = false }
    }
}

/// Compact VPN state for the top of the dashboard; opens the VPN screen.
public struct VPNStatusPill: View {
    @ObservedObject private var vpn: VPNManager = .shared
    @ObservedObject private var appState: AppState = .shared

    public init() {}

    public var body: some View {
        Button {
            withAnimation(AppMotion.standard) { appState.isVPNGatePresented = true }
        } label: {
            HStack(spacing: 6) {
                if vpn.isConnecting {
                    ProgressView().controlSize(.mini).tint(AppTheme.textSecondary)
                } else {
                    Circle()
                        .fill(vpn.isConnected ? AppTheme.success : AppTheme.textTertiary)
                        .frame(width: 8, height: 8)
                }
                Text("VPN")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(vpn.isConnected ? AppTheme.success : AppTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Capsule().fill(AppTheme.surface))
            .overlay(Capsule().strokeBorder(vpn.isConnected ? AppTheme.success.opacity(0.5) : AppTheme.surfaceBorder))
        }
        .buttonStyle(ScaleCardButtonStyle())
        .accessibilityLabel(vpn.isConnected ? L("VPN verbunden") : L("VPN getrennt"))
    }
}
