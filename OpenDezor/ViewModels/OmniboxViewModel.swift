import Foundation
import Combine

@MainActor
public class OmniboxViewModel: ObservableObject {
    @Published public var inputQuery: String = ""
    @Published public var isCheckingAddon: Bool = false
    @Published public var detectedAddonManifest: AddonManifest? = nil
    @Published public var detectedAddonUrl: String? = nil
    /// Drives the push to the full search page; the page runs the search itself.
    @Published public var isSearchPagePresented: Bool = false
    public private(set) var searchPageQuery: String = ""
    @Published public var errorMessage: String? = nil
    /// Set when a typed address turned out not to be an addon; the view offers to open it
    /// in the browser tab.
    @Published public var pendingBrowserUrl: String? = nil
    
    private let client: MediaHubClient
    private let addonManager: AddonManager
    private let storage: StorageService
    
    public init(
        client: MediaHubClient,
        addonManager: AddonManager,
        storage: StorageService
    ) {
        self.client = client
        self.addonManager = addonManager
        self.storage = storage
    }
    
    public convenience init() {
        self.init(client: .shared, addonManager: .shared, storage: .shared)
    }
    
    public var recentSearches: [String] {
        storage.searchHistory
    }
    
    public func isInputUrl(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("mhub://") || trimmed.hasPrefix("mediaurl://") {
            return true
        }
        if trimmed.contains(".json") || (trimmed.contains(".") && !trimmed.contains(" ") && trimmed.count > 4) {
            return true
        }
        return false
    }
    
    public func handleInputSubmit() async {
        let trimmed = inputQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if isInputUrl(trimmed) {
            await checkAndPromptAddon(url: trimmed)
        } else {
            openSearchPage(query: trimmed)
        }
    }
    
    public func checkAndPromptAddon(url: String) async {
        isCheckingAddon = true
        errorMessage = nil
        detectedAddonManifest = nil
        detectedAddonUrl = nil
        
        do {
            let (manifest, _) = try await client.detectAndLoadAddon(from: url)
            self.detectedAddonManifest = manifest
            self.detectedAddonUrl = url
            self.isCheckingAddon = false
        } catch {
            self.isCheckingAddon = false
            // Not an addon — it is still a web address, so hand it to the browser instead
            // of dead-ending on an error.
            self.pendingBrowserUrl = url
            self.errorMessage = "\(L("Kein gültiges Addon unter")) '\(url)' \(L("gefunden."))"
        }
    }
    
    public func installDetectedAddon() async -> Bool {
        guard let url = detectedAddonUrl else { return false }
        do {
            _ = try await addonManager.addAddon(from: url)
            self.detectedAddonManifest = nil
            self.detectedAddonUrl = nil
            self.inputQuery = ""
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
    
    public func openSearchPage(query: String = "") {
        searchPageQuery = query
        inputQuery = ""
        isSearchPagePresented = true
    }
    
    public func clear() {
        pendingBrowserUrl = nil
        inputQuery = ""
        detectedAddonManifest = nil
        detectedAddonUrl = nil
        errorMessage = nil
    }
}
