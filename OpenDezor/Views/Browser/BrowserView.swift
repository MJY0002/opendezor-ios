import SwiftUI
#if canImport(WebKit)
import WebKit
#endif

/// In-app browser.
///
/// Its purpose in this app is finding addons: most MediaHub sources are advertised on a
/// normal web page, and the manifest usually sits on the same host. So every navigation
/// is quietly run through `AddonDetector`, and a hit surfaces an install banner. Browsing
/// itself is deliberately plain — no tabs, no bookmarks.
public struct BrowserView: View {
    @StateObject private var viewModel = BrowserViewModel()
    @ObservedObject private var appState: AppState = .shared
    @ObservedObject private var vpnManager: VPNManager = .shared
    @FocusState private var addressFocused: Bool
    @State private var addressText: String = ""
    @State private var showVPNSettingsSheet = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            addressBar

            if let manifest = viewModel.detectedManifest {
                addonBanner(manifest: manifest)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if viewModel.isLoading {
                ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)
                    .tint(AppTheme.primaryAccent)
                    .frame(height: 2)
                    .accessibilityHidden(true)
            }

            #if canImport(WebKit) && os(iOS)
            WebViewContainer(viewModel: viewModel, vpnRevision: vpnManager.proxyRevision)
                .overlay {
                    // A failed navigation used to leave a blank or stale page with no
                    // explanation at all.
                    if let message = viewModel.errorMessage {
                        errorPage(message: message)
                    }
                }
            #else
            Spacer()
            Text(L("Browser"))
                .foregroundColor(AppTheme.textTertiary)
            Spacer()
            #endif

            navigationBar
        }
        .glassBackground()
        // Without this the bottom bar rides up with the keyboard and squeezes the page.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showVPNSettingsSheet) {
            VPNSettingsSheetView()
        }
        .animation(AppMotion.standard, value: viewModel.detectedManifest)
        .onAppear {
            addressText = viewModel.displayedAddress
            consumePendingAddress()
        }
        .onChange(of: appState.pendingBrowserUrl) {
            consumePendingAddress()
        }
        .onChange(of: viewModel.displayedAddress) { _, newValue in
            // Do not fight the user while they are typing an address.
            if !addressFocused { addressText = newValue }
        }
    }

    /// Picks up an address the omnibox handed over and clears it, so switching tabs later
    /// does not reload the same page again.
    ///
    /// Both `onAppear` and `onChange` can fire for the same hand-off, so the pending value
    /// is taken and cleared in one step — clearing it asynchronously let both callers pass
    /// the guard and load the page twice.
    private func consumePendingAddress() {
        guard let pending = appState.pendingBrowserUrl else { return }
        appState.pendingBrowserUrl = nil
        addressText = pending
        viewModel.load(pending)
    }

    @ViewBuilder
    private func errorPage(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .appFont(size: 40)
                .foregroundColor(AppTheme.textTertiary)

            Text(L("Seite konnte nicht geladen werden"))
                .appFont(size: 16, weight: .bold)
                .foregroundColor(AppTheme.textPrimary)

            Text(message)
                .appFont(size: 13)
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: { viewModel.reload() }) {
                Text(L("Erneut versuchen"))
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(AppTheme.cyanAccent))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }

    // MARK: - Address Bar

    private var addressBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: viewModel.isSecure ? "lock.fill" : "globe")
                    .appFont(size: 13)
                    .foregroundColor(viewModel.isSecure ? AppTheme.success : AppTheme.textTertiary)
                    .accessibilityHidden(true)

                TextField(L("Adresse eingeben"), text: $addressText)
                    .appFont(size: 14)
                    .foregroundColor(AppTheme.textPrimary)
                    .urlField()
                    .submitLabel(.go)
                    .focused($addressFocused)
                    .onSubmit {
                        addressFocused = false
                        viewModel.load(addressText)
                    }
                    #if os(iOS)
                    // Tapping the bar should let the user type a new address straight
                    // away, not drop a caret into the middle of the current URL.
                    .onChange(of: addressFocused) { _, focused in
                        guard focused else { return }
                        DispatchQueue.main.async {
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil
                            )
                        }
                    }
                    #endif

                if addressFocused && !addressText.isEmpty {
                    ClearFieldButton(size: 15) { addressText = "" }
                }

                // VPN Shield Button
                Button(action: { showVPNSettingsSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: vpnManager.isEnabled ? "shield.fill" : "shield")
                            .appFont(size: 13, weight: .bold)
                        if vpnManager.isEnabled {
                            Text(vpnManager.selectedServer.flag)
                                .appFont(size: 11)
                        } else {
                            Text("VPN")
                                .appFont(size: 11, weight: .semibold)
                        }
                    }
                    .foregroundColor(vpnManager.isEnabled ? AppTheme.cyanAccent : AppTheme.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule().fill(vpnManager.isEnabled ? AppTheme.cyanAccent.opacity(0.15) : AppTheme.surfaceLight)
                    )
                }
                .accessibilityLabel(vpnManager.isEnabled ? L("VPN ist aktiv") : L("VPN ist getrennt"))

                if viewModel.isLoading {
                    Button(action: { viewModel.stop() }) {
                        Image(systemName: "xmark")
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .accessibilityLabel(L("Laden abbrechen"))
                } else {
                    Button(action: { viewModel.reload() }) {
                        Image(systemName: "arrow.clockwise")
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .accessibilityLabel(L("Seite neu laden"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassCard(cornerRadius: 18, fillColor: AppTheme.surface.opacity(0.85))

            if addressFocused {
                Button(L("Abbrechen")) {
                    addressFocused = false
                    addressText = viewModel.displayedAddress
                }
                .appFont(size: 14, weight: .medium)
                .foregroundColor(AppTheme.cyanAccent)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: addressFocused)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Addon Banner

    @ViewBuilder
    private func addonBanner(manifest: AddonManifest) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill")
                .appFont(size: 20)
                .foregroundColor(AppTheme.cyanAccent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(L("MediaHub Addon gefunden"))
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(AppTheme.cyanAccent)
                Text(manifest.displayName)
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(AppTheme.textPrimary)
            }

            Spacer()

            Button(action: { viewModel.installDetectedAddon() }) {
                Text(viewModel.isInstalling ? "…" : L("Installieren"))
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppTheme.cyanGradient)
                    .cornerRadius(10)
            }
            .disabled(viewModel.isInstalling)
        }
        .padding(12)
        .background(AppTheme.surface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.cyanAccent.opacity(0.5), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Bottom Navigation

    private var navigationBar: some View {
        HStack(spacing: 28) {
            Button(action: { viewModel.goBack() }) {
                Image(systemName: "chevron.left")
                    .appFont(size: 17, weight: .semibold)
            }
            .disabled(!viewModel.canGoBack)
            .accessibilityLabel(L("Eine Seite zurück"))

            Button(action: { viewModel.goForward() }) {
                Image(systemName: "chevron.right")
                    .appFont(size: 17, weight: .semibold)
            }
            .disabled(!viewModel.canGoForward)
            .accessibilityLabel(L("Eine Seite vor"))

            Spacer()

            if let url = viewModel.currentURL {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .appFont(size: 16, weight: .semibold)
                }
                .accessibilityLabel(L("Seite teilen"))
            }
        }
        .foregroundColor(AppTheme.textSecondary)
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 78)
    }
}

// MARK: - WKWebView Bridge

#if canImport(WebKit) && os(iOS)
private struct WebViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: BrowserViewModel
    let vpnRevision: Int

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let dataStore = WKWebsiteDataStore.default()
        VPNManager.shared.applyToWebsiteDataStore(dataStore)
        config.websiteDataStore = dataStore
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = .clear
        webView.isOpaque = false
        viewModel.attach(webView)
        viewModel.loadStartPageIfIdle()
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastRevision != vpnRevision {
            context.coordinator.lastRevision = vpnRevision
            VPNManager.shared.applyToWebsiteDataStore(uiView.configuration.websiteDataStore)
            uiView.reload()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel, revision: vpnRevision) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let viewModel: BrowserViewModel
        var lastRevision: Int

        init(viewModel: BrowserViewModel, revision: Int) {
            self.viewModel = viewModel
            self.lastRevision = revision
        }

        /// WebKit cannot load `mhub://` and friends, so those links used to do nothing at
        /// all — on the one screen whose job is finding addons. They are routed to the
        /// installer instead; other non-web schemes go to the system.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
                decisionHandler(.allow)
                return
            }

            if BrowserViewModel.isAddonScheme(url.absoluteString.lowercased()) {
                decisionHandler(.cancel)
                Task { @MainActor in viewModel.installAddon(from: url.absoluteString) }
                return
            }

            if scheme == "http" || scheme == "https" || scheme == "about" || scheme == "data" {
                decisionHandler(.allow)
                return
            }

            // mailto:, tel:, itms-apps: and anything else the system owns.
            decisionHandler(.cancel)
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #endif
        }

        /// `target="_blank"` links produced no window at all before, because WebKit asks
        /// the UI delegate to create one and there was none. Load them in place.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in viewModel.navigationStarted(url: webView.url) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.navigationFinished(url: webView.url, title: webView.title)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in viewModel.navigationFailed(error) }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in viewModel.navigationFailed(error) }
        }

        /// Without this the view just goes blank and stays blank when the content process
        /// is killed (common under memory pressure).
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }
    }
}
#endif
