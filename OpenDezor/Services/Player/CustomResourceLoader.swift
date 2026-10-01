import Foundation
import AVFoundation

// MARK: - Custom URL Asset & Resource Loader Delegate
public class CustomResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    public static let customScheme = "mhubstream"
    
    private let headers: [String: String]
    private var activeTasks: [AVAssetResourceLoadingRequest: URLSessionDataTask] = [:]
    private let session: URLSession
    
    @MainActor
    public init(headers: [String: String]) {
        self.headers = headers
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 60
        VPNManager.shared.applyToURLSessionConfiguration(config)
        self.session = URLSession(configuration: config)
        super.init()
    }
    
    // MARK: - Helper to rewrite URL to custom scheme if resource loader is used
    public static func makeCustomURL(from originalUrl: URL) -> URL {
        guard var components = URLComponents(url: originalUrl, resolvingAgainstBaseURL: false) else {
            return originalUrl
        }
        components.scheme = customScheme
        return components.url ?? originalUrl
    }
    
    public static func restoreOriginalURL(from customUrl: URL) -> URL? {
        guard var components = URLComponents(url: customUrl, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        return components.url
    }
    
    // MARK: - AVAssetResourceLoaderDelegate
    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let url = loadingRequest.request.url else {
            return false
        }
        
        // Restore HTTP/HTTPS scheme
        guard let originalUrl = Self.restoreOriginalURL(from: url) else {
            return false
        }
        
        var request = URLRequest(url: originalUrl)
        request.httpMethod = loadingRequest.request.httpMethod ?? "GET"
        
        // Inject Custom Headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Same token source as MediaHubClient — see TokenStore.
        if let userToken = TokenStore.token, !userToken.isEmpty {
            if request.value(forHTTPHeaderField: "Authorization") == nil {
                request.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
            }
            if request.value(forHTTPHeaderField: "x-user-token") == nil {
                request.setValue(userToken, forHTTPHeaderField: "x-user-token")
            }
        }
        
        // Apply Range Header if requested
        if let dataRequest = loadingRequest.dataRequest {
            if dataRequest.requestedOffset > 0 || dataRequest.requestedLength > 0 {
                let lower = dataRequest.requestedOffset
                let upper: Int64 = (dataRequest.requestedLength > 0)
                    ? (lower + Int64(dataRequest.requestedLength) - 1)
                    : 0
                
                if upper > 0 {
                    request.setValue("bytes=\(lower)-\(upper)", forHTTPHeaderField: "Range")
                } else {
                    request.setValue("bytes=\(lower)-", forHTTPHeaderField: "Range")
                }
            }
        }
        
        let task = session.dataTask(with: request) { [weak self, weak loadingRequest] data, response, error in
            guard let self = self, let loadingRequest = loadingRequest else { return }
            
            if let error = error {
                loadingRequest.finishLoading(with: error)
                self.activeTasks.removeValue(forKey: loadingRequest)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                // Fill Content Information
                if let contentInfo = loadingRequest.contentInformationRequest {
                    contentInfo.isByteRangeAccessSupported = (httpResponse.allHeaderFields["Accept-Ranges"] as? String == "bytes") || (httpResponse.statusCode == 206)
                    contentInfo.contentType = httpResponse.mimeType
                    contentInfo.contentLength = httpResponse.expectedContentLength
                }
                
                // Fill Data Request
                if let dataRequest = loadingRequest.dataRequest, let data = data {
                    dataRequest.respond(with: data)
                }
                
                loadingRequest.finishLoading()
            } else {
                loadingRequest.finishLoading(with: NSError(domain: "CustomResourceLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP Response"]))
            }
            
            self.activeTasks.removeValue(forKey: loadingRequest)
        }
        
        activeTasks[loadingRequest] = task
        task.resume()
        return true
    }
    
    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        if let task = activeTasks[loadingRequest] {
            task.cancel()
            activeTasks.removeValue(forKey: loadingRequest)
        }
    }
}
