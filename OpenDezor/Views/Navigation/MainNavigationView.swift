import SwiftUI

public struct MainNavigationView: View {
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
            if appState.isVPNGatePresented, !appState.isLaunching,
               appState.hasCompletedOnboarding {
                VPNGateView()
                    // In from the bottom, out the same way; a cross-fade with Reduce Motion.
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .zIndex(120)
            }
        }
        .overlay {
            if appState.isLaunching {
                LaunchAnimationView {
                    withAnimation(.easeOut(duration: 0.3)) {
                        appState.isLaunching = false
                        // Offer the VPN first thing, unless it connects on its own.
                        if !StorageService.shared.settings.vpnAutoConnect, !VPNManager.shared.isConnected {
                            appState.isVPNGatePresented = true
                        }
                    }
                }
                .transition(.opacity)
                .zIndex(200)
            }
        }
    }
}
