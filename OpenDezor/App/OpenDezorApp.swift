import SwiftUI

@main
public struct OpenDezorApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var addonManager = AddonManager.shared
    @StateObject private var storage = StorageService.shared
    @StateObject private var playerService = PlayerService.shared
    
    @Environment(\.scenePhase) private var scenePhase

    public init() {}
    
    public var body: some Scene {
        WindowGroup {
            MainNavigationView()
                .onChange(of: scenePhase) { _, phase in
                    DebugLog.log(.info, "App", "Szene: \(phase)")
                }
                .onOpenURL { url in
                    appState.openURL(url)
                }
                .task {
                    // Provisions the anonymous device token the addon and stream requests
                    // need, and refreshes account state on every cold start.
                    await DezorAuthService.shared.refresh(reason: "appStart")
                }
        }
    }
}
