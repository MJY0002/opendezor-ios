import SwiftUI

public struct MainNavigationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var appState: AppState = .shared
    @ObservedObject private var theme: ThemeController = .shared
    @ObservedObject private var localization: LocalizationController = .shared
    @State private var selectedCatalogSection: DashboardSection? = nil
    @Namespace private var mediaZoom
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            if !appState.hasCompletedOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                TabView(selection: $appState.selectedTab) {
                // Tab 1: Dashboard
                NavigationStack {
                    DashboardView(
                        onSelectMediaItem: { item in
                            appState.selectedMediaDetail = item
                        },
                        onOpenCatalog: { section in
                            selectedCatalogSection = section
                        }
                    )
                    .navigationDestination(isPresented: Binding(
                        get: { selectedCatalogSection != nil },
                        set: { if !$0 { selectedCatalogSection = nil } }
                    )) {
                        if let sec = selectedCatalogSection {
                            CatalogGridView(
                                addonEndpoint: sec.addonEndpoint,
                                catalogId: sec.dashboard.catalogId ?? sec.dashboard.id,
                                catalogName: sec.dashboard.name?.value ?? sec.dashboard.id,
                                features: sec.dashboard.features
                            ) { item in
                                appState.selectedMediaDetail = item
                            }
                        }
                    }
                }
                .tabItem {
                    Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.iconName)
                }
                .tag(AppTab.dashboard)
                
                // Tab 2: Browser — finding addons on the open web is what it is for
                BrowserView()
                    .tabItem {
                        Label(AppTab.browser.title, systemImage: AppTab.browser.iconName)
                    }
                    .tag(AppTab.browser)

                // Tab 3: Live TV
                LiveTVGuideView()
                    .tabItem {
                        Label(AppTab.liveTV.title, systemImage: AppTab.liveTV.iconName)
                    }
                    .tag(AppTab.liveTV)
                
                // Tab 3: Library
                LibraryView { item in
                    appState.selectedMediaDetail = item
                }
                // The addon URL field otherwise keeps the keyboard over the tab bar.
                .scrollDismissesKeyboard(.interactively)
                .tabItem {
                    Label(AppTab.library.title, systemImage: AppTab.library.iconName)
                }
                .tag(AppTab.library)
                
                // Tab 4: Settings
                SettingsView()
                    .tabItem {
                        Label(AppTab.settings.title, systemImage: AppTab.settings.iconName)
                    }
                    .tag(AppTab.settings)
                }
                .tint(AppTheme.cyanAccent)
            }
            
            if appState.isPreparingPlayback, appState.selectedMediaDetail == nil, appState.activeToast == nil {
                PreparingPlaybackBanner()
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(99)
            }

            // Toast Notification Overlay
            if let toast = appState.activeToast {
                ToastBannerView(toast: toast)
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        // Media Detail Sheet
        .environment(\.mediaZoomNamespace, mediaZoom)
        .sheet(item: $appState.selectedMediaDetail) { item in
            MediaDetailView(item: item)
                .zoomDestination(id: item.id, in: mediaZoom)
        }
        // Fullscreen Native Video Player Cover
        #if os(iOS)
        .fullScreenCover(isPresented: $appState.isPlayerPresented) {
            CustomPlayerView {
                appState.dismissPlayer()
            }
        }
        #elseif os(macOS)
        .sheet(isPresented: $appState.isPlayerPresented) {
            CustomPlayerView {
                appState.dismissPlayer()
            }
            .frame(minWidth: 800, minHeight: 500)
        }
        #endif
        // Rebuilding on language or palette change is the reliable way to refresh every
        // `L(...)` call and every AppTheme colour deep in the tree; it only happens when
        // the user actually changes a preference.
        .id("\(localization.code)-\(theme.colorScheme.rawValue)-\(theme.accent.rawValue)")
        .preferredColorScheme(theme.preferredColorScheme)
        // Type follows the user's text-size setting (see `appFont`), but the card, badge
        // and poster geometry is fixed, so past this point labels start truncating and
        // buttons wrap out of their pills. Capping keeps every size up to here fully
        // usable instead of letting the largest ones render a broken layout.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        // Errors and confirmations are felt as well as seen, on the frame the toast appears.
        .sensoryFeedback(trigger: appState.activeToast) { _, toast in
            toast.map { $0.isError ? .error : .success }
        }
        .syncsSystemAppearance()
        .overlay {
            if appState.isVPNGatePresented, !appState.isAppLocked, !appState.isLaunching,
               appState.hasCompletedOnboarding {
                VPNGateView()
                    // In from the bottom, out the same way; a cross-fade with Reduce Motion.
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .zIndex(120)
            }
        }
        .overlay {
            if appState.isAppLocked {
                BiometricLockOverlayView(appState: appState)
                    .transition(.opacity)
                    .zIndex(150)
            } else if appState.isLaunching {
                LaunchAnimationView {
                    withAnimation(.easeOut(duration: 0.3)) {
                        appState.isLaunching = false
                        // Offer the VPN first thing, unless it connects on its own.
                        if !StorageService.shared.settings.vpnAutoConnect, !VPNManager.shared.isConnected {
                            appState.isVPNGatePresented = true
                        }
                        if StorageService.shared.settings.requireBiometrics {
                            appState.authenticateBiometrics()
                        }
                    }
                }
                .transition(.opacity)
                .zIndex(200)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                appState.lockApp()
            } else if newPhase == .active {
                if StorageService.shared.settings.requireBiometrics && appState.isAppLocked {
                    appState.authenticateBiometrics()
                }
            }
        }
    }
}

public struct BiometricLockOverlayView: View {
    @ObservedObject var appState: AppState
    
    public var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(AppTheme.accentGradient)
                        .frame(width: 88, height: 88)
                        .blur(radius: 12)
                        .opacity(0.6)
                    
                    Circle()
                        .fill(AppTheme.surface)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        )
                    
                    Image(systemName: "lock.shield.fill")
                        .appFont(size: 38)
                        .foregroundColor(AppTheme.cyanAccent)
                }
                
                VStack(spacing: 8) {
                    Text(L("OpenDezor ist gesperrt"))
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Text(L("Verwende Face ID, Touch ID oder deinen Geräte-Code, um fortzufahren."))
                        .appFont(size: 14)
                        .foregroundColor(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                VStack(spacing: 12) {
                    Button(action: {
                        appState.authenticateBiometrics()
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "faceid")
                                .appFont(size: 18)
                            Text(L("Mit Face ID entsperren"))
                                .appFont(size: 15, weight: .bold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().fill(AppTheme.cyanAccent)
                        )
                    }
                    
                    // Escape hatches exist only where biometrics cannot work at all.
                    // On a real device they would make the lock meaningless: anyone
                    // holding the phone could tap straight past it.
                    #if targetEnvironment(simulator)
                    Button(action: {
                        appState.unlockDirectly()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .appFont(size: 13)
                            Text(L("Ohne Face ID entsperren (nur Simulator)"))
                                .appFont(size: 13, weight: .medium)
                        }
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.vertical, 8)
                    }

                    Button(action: {
                        appState.disableBiometricLock()
                    }) {
                        Text(L("Sperre ausschalten & deaktivieren"))
                            .appFont(size: 12)
                            .foregroundColor(AppTheme.destructive)
                    }
                    .padding(.top, 4)
                    #endif
                }
                .padding(.top, 12)
                
                Spacer()
            }
        }
        .onAppear {
            appState.authenticateBiometrics()
        }
    }
}
