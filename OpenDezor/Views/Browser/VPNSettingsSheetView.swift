import SwiftUI

public struct VPNSettingsSheetView: View {
    @ObservedObject var vpnManager: VPNManager = .shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab: Int = 0 // 0 = Server, 1 = Custom Proxy
    @State private var customHost: String = ""
    @State private var customPort: String = ""
    @State private var customProtocol: ProxyProtocol = .http
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Big Status Header
                        statusHeaderCard
                        
                        // Segment Picker (Server vs Eigener Proxy)
                        Picker("", selection: $selectedTab) {
                            Text(L("Server-Standorte")).tag(0)
                            Text(L("Eigener Proxy")).tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        
                        if selectedTab == 0 {
                            serverListSection
                        } else {
                            customProxySection
                        }
                        
                        // Explanatory Note
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(AppTheme.cyanAccent)
                                .appFont(size: 14)
                            
                            Text(L("Das VPN schützt den Datenverkehr dieser App: den Browser und alle Filme, Serien und Live-TV-Sender – auch den Videostream selbst. Es ist kein systemweites VPN; andere Apps laufen über deine normale Verbindung."))
                                .appFont(size: 11)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.surfaceLight))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle(L("VPN & Proxy Schutz"))
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
                customHost = vpnManager.selectedServer.isCustom ? vpnManager.selectedServer.host : ""
                customPort = vpnManager.selectedServer.isCustom ? "\(vpnManager.selectedServer.port)" : "8080"
                customProtocol = vpnManager.selectedServer.proto
            }
        }
    }
    
    private var headlineText: String {
        if vpnManager.isConnected { return L("VPN Schutz ist AKTIV") }
        if vpnManager.isConnecting { return L("Verbinde…") }
        if vpnManager.isEnabled { return L("VPN nicht verbunden") }
        return L("VPN ist GETRENNT")
    }

    // MARK: - Status Header Card
    private var statusHeaderCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(vpnManager.isEnabled ? AppTheme.accentGradient : LinearGradient(colors: [AppTheme.surfaceLight, AppTheme.surface], startPoint: .top, endPoint: .bottom))
                    .frame(width: 74, height: 74)
                    .blur(radius: vpnManager.isEnabled ? 10 : 0)
                    .opacity(vpnManager.isEnabled ? 0.6 : 0.2)
                
                Circle()
                    .fill(AppTheme.surface)
                    .frame(width: 66, height: 66)
                    .overlay(
                        Circle().strokeBorder(vpnManager.isEnabled ? AppTheme.cyanAccent : Color.white.opacity(0.15), lineWidth: 1.5)
                    )
                
                Image(systemName: vpnManager.isConnected ? "shield.fill" : "shield.slash.fill")
                    .appFont(size: 30)
                    .foregroundColor(vpnManager.isConnected ? AppTheme.cyanAccent : AppTheme.textTertiary)
            }

            // The headline reports the *verified* tunnel, never just the switch position —
            // claiming protection that is not there is worse than saying it failed.
            VStack(spacing: 4) {
                Text(headlineText)
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(vpnManager.isConnected ? AppTheme.cyanAccent : AppTheme.textPrimary)

                Text(vpnManager.isEnabled
                     ? "\(vpnManager.selectedServer.flag) \(vpnManager.selectedServer.name)"
                     : L("Deine echte IP-Adresse ist für Webseiten sichtbar"))
                    .appFont(size: 12)
                    .foregroundColor(AppTheme.textSecondary)
            }

            // IP Check Badge
            if vpnManager.isEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .appFont(size: 12)
                        .foregroundColor(AppTheme.textTertiary)

                    if vpnManager.isConnecting {
                        ProgressView()
                            .tint(AppTheme.cyanAccent)
                            .scaleEffect(0.7)
                        Text(L("Verbinde…"))
                            .appFont(size: 12)
                            .foregroundColor(AppTheme.textSecondary)
                    } else if let ip = vpnManager.currentPublicIP, vpnManager.isConnected {
                        Text("\(L("Maskierte IP")): \(ip)")
                            .appFont(size: 12, weight: .semibold, design: .monospaced)
                            .foregroundColor(AppTheme.success)
                    } else {
                        Button(action: {
                            Task { await vpnManager.verifyConnection() }
                        }) {
                            Text(L("Erneut versuchen"))
                                .appFont(size: 12, weight: .semibold)
                                .foregroundColor(AppTheme.cyanAccent)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(AppTheme.surfaceLight))

                if !vpnManager.statusMessage.isEmpty && !vpnManager.isConnected {
                    Text(vpnManager.statusMessage)
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(AppTheme.warning)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
            
            // Main Toggle Button
            Button(action: {
                withAnimation(AppMotion.standard) {
                    vpnManager.toggleVPN()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: vpnManager.isEnabled ? "power" : "bolt.shield.fill")
                    Text(vpnManager.isEnabled ? L("VPN Trennen") : L("VPN Verbinden"))
                }
                .appFont(size: 14, weight: .bold)
                .foregroundColor(.white)
                .frame(maxWidth: 220)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(vpnManager.isEnabled ? AppTheme.destructive : AppTheme.cyanAccent)
                )
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(AppTheme.surface))
        .padding(.horizontal, 16)
    }
    
    // MARK: - Server List
    private var serverListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Wähle einen Server-Standort"))
                .appFont(size: 13, weight: .bold)
                .foregroundColor(AppTheme.textSecondary)
                .padding(.horizontal, 16)
            
            VStack(spacing: 8) {
                ForEach(vpnManager.availableServers.filter { !$0.isCustom }) { server in
                    let isSelected = vpnManager.selectedServer.id == server.id
                    
                    Button(action: {
                        vpnManager.selectServer(server)
                    }) {
                        HStack(spacing: 14) {
                            Text(server.flag)
                                .appFont(size: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name)
                                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                                
                                Text(server.city)
                                    .appFont(size: 11)
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            
                            Spacer()
                            
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .appFont(size: 18)
                                    .foregroundColor(AppTheme.cyanAccent)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isSelected ? AppTheme.surfaceLight : AppTheme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(isSelected ? AppTheme.cyanAccent.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Custom Proxy Section
    private var customProxySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Eigenen Proxy konfigurieren"))
                .appFont(size: 13, weight: .bold)
                .foregroundColor(AppTheme.textSecondary)
                .padding(.horizontal, 16)
            
            VStack(spacing: 12) {
                Picker(L("Protokoll"), selection: $customProtocol) {
                    Text("HTTP").tag(ProxyProtocol.http)
                    Text("HTTPS").tag(ProxyProtocol.https)
                    Text("SOCKS5").tag(ProxyProtocol.socks5)
                }
                .pickerStyle(.segmented)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Server Host / IP"))
                        .appFont(size: 11, weight: .semibold)
                        .foregroundColor(AppTheme.textSecondary)
                    
                    TextField("127.0.0.1 oder proxy.example.com", text: $customHost)
                        .appFont(size: 13)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.surfaceLight))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Port"))
                        .appFont(size: 11, weight: .semibold)
                        .foregroundColor(AppTheme.textSecondary)
                    
                    TextField("8080 oder 1080", text: $customPort)
                        .appFont(size: 13)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.surfaceLight))
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                
                Button(action: saveCustomProxy) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text(L("Proxy speichern & aktivieren"))
                    }
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.cyanAccent))
                }
                .padding(.top, 6)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(AppTheme.surface))
            .padding(.horizontal, 16)
        }
    }
    
    private func saveCustomProxy() {
        let host = customHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Int(customPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 8080
        guard !host.isEmpty else { return }
        
        vpnManager.updateCustomProxy(host: host, port: port, proto: customProtocol)
        if let customServer = vpnManager.availableServers.first(where: { $0.id == "custom" }) {
            vpnManager.selectServer(customServer)
            if !vpnManager.isEnabled {
                vpnManager.setEnabled(true)
            }
        }
    }
}
