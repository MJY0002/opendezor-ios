import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Image Memory Cache
//
// Internal rather than private so `StorageService.applyPreferences` can set the budget
// directly; it used to reach it through a free-function wrapper that only delegated.
enum ImageCache {
    static let shared: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 400
        // Cost is tracked in bytes; the budget comes from the user's cache setting.
        cache.totalCostLimit = 500 * 1024 * 1024
        return cache
    }()

    /// URLs that already answered with an error or unusable data. Addon artwork hosts go
    /// dead regularly (IPTV logos often 404), and without this every scroll past
    /// a channel fires the same doomed request again.
    static let failed: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 1000
        return cache
    }()

    /// Applies the user's size budget. Called when settings are loaded or changed.
    static func applyLimit(megabytes: Int) {
        shared.totalCostLimit = max(32, megabytes) * 1024 * 1024
    }

    /// Rough decoded size, used as the cache cost so the byte budget means something.
    static func cost(of image: PlatformImage) -> Int {
        #if canImport(UIKit)
        guard let cg = image.cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
        #else
        return Int(image.size.width * image.size.height * 4)
        #endif
    }
}

#if canImport(UIKit)
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
public typealias PlatformImage = NSImage
#endif

// MARK: - Image Proxy
//
// The official Dezor client routes every image through its own cache
// (`cache.dezor.net/image/get?url=…&size=…`).
// It matters here because addons hand out full-size artwork — some addons serve
// `image.tmdb.org/t/p/original/…` at several MB per poster, versus ~64 KB through the
// proxy. Off by preference, since it means every image URL is sent to dezor.net.
public enum ImageProxy {
    public static let endpoint = "https://cache.dezor.net/image/get"

    public enum Size: String {
        case small, medium, large
    }

    public static func url(for original: String, size: Size) -> String {
        // Favicons are tiny already and the proxy mangles them; the original client
        // skips them too.
        guard !original.lowercased().hasSuffix(".ico"),
              original.lowercased().hasPrefix("http"),
              var components = URLComponents(string: endpoint) else { return original }

        components.queryItems = [
            URLQueryItem(name: "url", value: original),
            URLQueryItem(name: "size", value: size.rawValue)
        ]
        return components.url?.absoluteString ?? original
    }
}

// MARK: - CachedAsyncImage
public struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let urlString: String?
    private let proxySize: ImageProxy.Size
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    
    @State private var loadedImage: PlatformImage? = nil
    
    /// `proxySize` picks the variant requested from the image cache; it is ignored when
    /// the proxy is switched off.
    public init(
        url: String?,
        proxySize: ImageProxy.Size = .medium,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.urlString = url
        self.proxySize = proxySize
        self.content = content
        self.placeholder = placeholder
    }
    
    public var body: some View {
        // Callers pass content that uses .scaledToFill(), which grows past the proposed
        // size and would otherwise report a width wider than the screen — dragging the
        // surrounding layout sideways. Color.clear takes exactly the proposed size and
        // an overlay cannot influence it, so the image is confined and then clipped.
        // Every call site sets its own frame, so there is no intrinsic size to preserve.
        Color.clear
            .overlay(
                ZStack {
                    if let platformImg = loadedImage {
                        #if canImport(UIKit)
                        content(Image(uiImage: platformImg))
                        #elseif canImport(AppKit)
                        content(Image(nsImage: platformImg))
                        #endif
                    } else {
                        placeholder()
                    }
                }
            )
            .clipped()
            // Restarts whenever the URL changes and cancels the stale load, so a recycled
            // tile or a hero whose item arrives late never shows the previous artwork —
            // or nothing, which is what the old `isLoading` guard produced.
            .task(id: urlString) {
                await loadImage()
            }
    }

    @MainActor
    private func loadImage() async {
        guard let urlStr = urlString, !urlStr.isEmpty else {
            loadedImage = nil
            return
        }

        // Cache under the original URL so toggling the proxy does not orphan entries.
        let cacheKey = NSString(string: urlStr)
        if let cached = ImageCache.shared.object(forKey: cacheKey) {
            loadedImage = cached
            return
        }
        loadedImage = nil
        if ImageCache.failed.object(forKey: cacheKey) != nil {
            return
        }

        let useProxy = StorageService.shared.settings.useImageProxy
        let effective = useProxy ? ImageProxy.url(for: urlStr, size: proxySize) : urlStr
        guard let url = URL(string: effective) else { return }

        var resolved = await Self.fetch(url)

        // The proxy answers 500 when it cannot reach the source, so fall back to the
        // original URL once before giving up on this image.
        if resolved == nil, !Task.isCancelled,
           useProxy, effective != urlStr,
           let direct = URL(string: urlStr) {
            resolved = await Self.fetch(direct)
        }

        // A cancelled load is not a failed image: the view moved on to another URL.
        guard !Task.isCancelled else { return }

        if let resolved {
            ImageCache.shared.setObject(resolved, forKey: cacheKey, cost: ImageCache.cost(of: resolved))
        } else {
            ImageCache.failed.setObject(1, forKey: cacheKey)
        }
        loadedImage = resolved
    }

    /// One artwork request. Returns nil for a transport failure, a non-2xx status or
    /// undecodable bytes — the caller treats all three the same way.
    private static func fetch(_ url: URL) async -> PlatformImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(MediaHubClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else { return nil }

        #if canImport(UIKit)
        return UIImage(data: data)
        #elseif canImport(AppKit)
        return NSImage(data: data)
        #else
        return nil
        #endif
    }
}
