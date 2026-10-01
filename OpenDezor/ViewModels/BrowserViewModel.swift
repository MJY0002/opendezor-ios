import Foundation
import Combine
#if canImport(WebKit)
import WebKit
#endif

/// State behind the in-app browser, plus the addon sniffing that justifies having one.
///
/// After every completed navigation the current origin is handed to `AddonDetector`. That
/// is the same detection the omnibox uses, so a page that advertises a MediaHub source
/// turns into a one-tap install without the user having to know the manifest URL.
@MainActor
public class BrowserViewModel: ObservableObject {
    @Published public var displayedAddress: String = ""
    @Published public var pageTitle: String = ""
    @Published public var progress: Double = 0
    @Published public var isLoading: Bool = false
    @Published public var canGoBack: Bool = false
    @Published public var canGoForward: Bool = false
    @Published public var isSecure: Bool = false
    @Published public var currentURL: URL?
    /// Set when a navigation fails, so the user sees why instead of a blank page.
    @Published public var errorMessage: String?

    @Published public var detectedManifest: AddonManifest?
    @Published public var isInstalling: Bool = false

    public static let startPage = "https://duckduckgo.com"

    private let detector: AddonDetector
    private let addonManager: AddonManager
    private var detectedUrlString: String?
    private var detectionTask: Task<Void, Never>?
    /// Hosts already probed, so revisiting a site does not re-run detection every time.
    private var probedOrigins: Set<String> = []

    #if canImport(WebKit)
    private weak var webView: WKWebView?
    private var observations: [NSKeyValueObservation] = []
    /// A load requested before the web view existed.
    ///
    /// The browser tab is only built when it is first shown, so a hand-off from another
    /// screen — the omnibox, or tapping a cast member — arrives while `webView` is still
    /// nil. Without this the request was silently dropped and the tab opened blank with
    /// the right address in the bar.
    private var pendingLoad: URL?
    #endif

    /// Whether a load is waiting for the web view to exist. Exposed for tests.
    var hasPendingLoad: Bool {
        #if canImport(WebKit)
        return pendingLoad != nil
        #else
        return false
        #endif
    }

    /// AddonManager.shared is MainActor-isolated, so it cannot be a default argument;
    /// resolving it inside the initializer keeps the same injectable shape.
    public init(detector: AddonDetector = .shared, addonManager: AddonManager? = nil) {
        self.detector = detector
        self.addonManager = addonManager ?? AddonManager.shared
    }

    // MARK: - Web View Wiring

    #if canImport(WebKit)
    public func attach(_ webView: WKWebView) {
        self.webView = webView

        // Observing only `estimatedProgress` left the address bar and the back/forward
        // buttons stale on single-page sites, which navigate without a delegate callback.
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.progress = view.estimatedProgress }
            },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in if let url = view.url { self?.updateAddress(url) } }
            },
            webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.pageTitle = view.title ?? "" }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoForward = view.canGoForward }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.isLoading = view.isLoading }
            }
        ]

        // Perform whatever was requested before this view existed.
        if let pendingLoad {
            self.pendingLoad = nil
            webView.load(URLRequest(url: pendingLoad))
        }
    }

    /// Loads the start page, unless something has already been requested. Kept separate
    /// from `attach` so a pending address from the omnibox is not overwritten by it.
    public func loadStartPageIfIdle() {
        guard let webView, webView.url == nil, displayedAddress.isEmpty else { return }
        load(Self.startPage)
    }
    #endif

    // MARK: - Navigation

    /// Accepts what a user actually types: a bare host, a full URL, an addon scheme, or a
    /// search phrase.
    public func load(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lower = trimmed.lowercased()

        // Addon schemes are an install request, not a page to render. Prefixing them with
        // https, as the old build did, produced "https://mhub://…" and silently failed.
        if Self.isAddonScheme(lower) {
            installAddon(from: trimmed)
            return
        }

        let target: URL?
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            target = URL(string: trimmed)
        } else if Self.looksLikeHost(trimmed) {
            target = URL(string: "https://" + trimmed)
        } else {
            target = Self.searchURL(for: trimmed)
        }

        guard let target else {
            errorMessage = "\(L("Ungültige URL")): \(trimmed)"
            return
        }
        errorMessage = nil
        displayedAddress = target.absoluteString
        #if canImport(WebKit)
        if let webView {
            webView.load(URLRequest(url: target))
        } else {
            // Queued until `attach` — see `pendingLoad`.
            pendingLoad = target
        }
        #endif
    }

    static func isAddonScheme(_ lowercasedInput: String) -> Bool {
        ["mhub://", "mediaurl://", "dezor://", "opendezor://"]
            .contains { lowercasedInput.hasPrefix($0) }
    }

    /// True for things that are addresses rather than search phrases, including
    /// `localhost:8080` and bare IPs, which the old "must contain a dot" rule missed.
    static func looksLikeHost(_ input: String) -> Bool {
        guard !input.contains(" ") else { return false }
        let hostPart = input.split(separator: "/").first.map(String.init) ?? input
        if hostPart.lowercased().hasPrefix("localhost") { return true }
        let withoutPort = hostPart.split(separator: ":").first.map(String.init) ?? hostPart
        guard withoutPort.contains(".") else { return false }
        // A trailing dot or an empty label is not a host.
        let labels = withoutPort.split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && !labels.contains(where: { $0.isEmpty })
    }

    /// `.urlQueryAllowed` leaves `&`, `+` and `=` untouched, which tore a query like
    /// "c++ & rust" into broken parameters.
    static func searchURL(for query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        return URL(string: "https://duckduckgo.com/?q=\(encoded)")
    }

    public func reload() {
        errorMessage = nil
        #if canImport(WebKit)
        webView?.reload()
        #endif
    }

    public func stop() {
        #if canImport(WebKit)
        webView?.stopLoading()
        #endif
        isLoading = false
    }

    public func goBack() {
        #if canImport(WebKit)
        webView?.goBack()
        #endif
    }

    public func goForward() {
        #if canImport(WebKit)
        webView?.goForward()
        #endif
    }

    // MARK: - Navigation Callbacks

    public func navigationStarted(url: URL?) {
        isLoading = true
        errorMessage = nil
        detectedManifest = nil
        detectionTask?.cancel()
        if let url { updateAddress(url) }
    }

    public func navigationFinished(url: URL?, title: String?) {
        isLoading = false
        progress = 0
        pageTitle = title ?? ""
        if let url {
            updateAddress(url)
            detectAddon(at: url)
        }
        refreshNavigationState()
    }

    public func navigationFailed(_ error: Error) {
        isLoading = false
        progress = 0
        refreshNavigationState()

        let nsError = error as NSError
        // -999 is "a newer navigation replaced this one" — normal, not a failure worth
        // showing. Everything else leaves the user on a blank page unless we explain it.
        guard nsError.code != NSURLErrorCancelled else { return }
        errorMessage = nsError.localizedDescription
    }

    private func updateAddress(_ url: URL) {
        currentURL = url
        displayedAddress = url.absoluteString
        isSecure = url.scheme?.lowercased() == "https"
    }

    private func refreshNavigationState() {
        #if canImport(WebKit)
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
        #endif
    }

    // MARK: - Addon Detection

    /// Probes the visited origin for a MediaHub manifest. Runs detached and failure is the
    /// normal case — most pages are just pages — so nothing is reported when it misses.
    private func detectAddon(at url: URL) {
        guard let host = url.host, !host.isEmpty else { return }
        let scheme = url.scheme ?? "https"
        // Keep the port: an addon served from localhost:8080 was never found without it.
        var origin = "\(scheme)://\(host)"
        if let port = url.port { origin += ":\(port)" }

        guard !probedOrigins.contains(origin) else { return }
        if isAlreadyInstalled(host: host) { return }

        detectionTask?.cancel()
        detectionTask = Task { [weak self] in
            guard let self else { return }
            guard let (manifest, endpoint) = try? await self.detector.detect(from: origin) else {
                self.probedOrigins.insert(origin)
                return
            }
            if Task.isCancelled { return }
            // Keep the endpoint detection resolved rather than re-deriving it on install;
            // the manifest host often differs from the site (the site host vs. the manifest host).
            self.detectedUrlString = endpoint
            self.detectedManifest = manifest
        }
    }

    /// Compares hosts properly. The old substring test matched `a.to` inside `kaa.to`.
    private func isAlreadyInstalled(host: String) -> Bool {
        addonManager.activeAddons.contains { addon in
            guard let installedHost = URL(string: addon.endpoint)?.host else { return false }
            return installedHost.caseInsensitiveCompare(host) == .orderedSame
        }
    }

    public func installDetectedAddon() {
        guard let urlString = detectedUrlString else { return }
        install(urlString)
    }

    /// Installs from an `mhub://`-style link tapped on a page or typed in the address bar.
    public func installAddon(from url: String) {
        install(url)
    }

    private func install(_ urlString: String) {
        isInstalling = true
        Task {
            defer { isInstalling = false }
            do {
                let manifest = try await addonManager.addAddon(from: urlString)
                detectedManifest = nil
                AppState.shared.showToast(
                    message: "\(L("Addon")) '\(manifest.displayName)' \(L("erfolgreich installiert!"))",
                    icon: "checkmark.seal.fill"
                )
            } catch {
                AppState.shared.showToast(
                    message: "\(L("Fehler beim Installieren des Addons")): \(error.localizedDescription)",
                    isError: true
                )
            }
        }
    }
}
