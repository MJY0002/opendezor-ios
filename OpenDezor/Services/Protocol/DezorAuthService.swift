import Foundation
import Combine

@MainActor
public class DezorAuthService: ObservableObject {
    public static let shared = DezorAuthService()

    private let userKey = "opendezor_user_account"
    // The token lives in the Keychain (TokenStore), not UserDefaults — it is credential
    // material and used to sit in a plaintext plist.
    private let regionKey = "opendezor_region"

    private let client: DezorPingClient

    @Published public var currentUser: DezorUser?
    /// Assigned by the backend, never generated locally. Empty until the first
    /// `connect.check` ping returns one.
    @Published public var connectCode: String = ""
    @Published public var isAuthenticating: Bool = false
    @Published public var isRequestingCode: Bool = false
    @Published public var errorMessage: String?
    @Published public var region: String = "??"

    /// Device token issued by the backend. Sent as the auth header on every addon and
    /// stream request, and required on every subsequent ping.
    public private(set) var token: String?

    private var pollingTask: Task<Void, Never>?

    public init(client: DezorPingClient? = nil) {
        self.client = client ?? DezorPingClient.shared
        self.token = TokenStore.token
        self.region = UserDefaults.standard.string(forKey: regionKey) ?? "??"
        loadSavedUser()
    }

    public var isLoggedIn: Bool {
        currentUser?.hasAccount == true
    }

    public var hasUnlimitedVPN: Bool {
        currentUser?.hasPremium == true
    }

    public var connectUrlString: String {
        let lng = Locale.current.language.languageCode?.identifier ?? "de"
        return DezorPingClient.connectEndpointTemplate
            .replacingOccurrences(of: "{code}", with: connectCode)
            .replacingOccurrences(of: "{lng}", with: lng)
    }

    // MARK: - Ping

    /// Issues a ping and folds the envelope (token, region, user) back into local state.
    /// Returns the `result` payload of the invoked procedure, if any.
    @discardableResult
    private func ping(reason: String, call: String? = nil, params: [String: Any]? = nil) async throws -> DezorPingResult? {
        let vpn = VPNManager.shared
        let proxyState = DezorProxyState(
            enabled: vpn.isEnabled,
            autoServer: vpn.selectedServer.id == "auto",
            id: vpn.selectedServer.isCustom ? nil : vpn.selectedServer.id
        )
        let response = try await client.ping(
            token: token,
            reason: reason,
            call: call,
            params: params,
            proxyState: proxyState
        )

        if let newToken = response.token, !newToken.isEmpty, newToken != token {
            token = newToken
            TokenStore.token = newToken
        }
        if let newRegion = response.region, !newRegion.isEmpty, newRegion != region {
            region = newRegion
            UserDefaults.standard.set(newRegion, forKey: regionKey)
        }
        if let user = response.user {
            persistUser(user)
            // The free proxy allowance is metered per token, exactly as in the official
            // client: anonymous users get a budget, an account raises or removes it.
            VPNManager.shared.isProxyLocked = !user.hasPremium && user.remainingProxyDuration <= 0
        }
        // The backend only ships `proxy` on some pings; applyProxyConfig ignores empties
        // so a plain keep-alive never clears a good server list.
        if let proxy = response.proxy {
            VPNManager.shared.applyProxyConfig(proxy)
        }
        if let envelopeError = response.error, !envelopeError.isEmpty {
            throw MediaHubError.httpError(statusCode: 200, message: envelopeError)
        }
        if let error = response.result?.error, !error.isEmpty {
            throw MediaHubError.httpError(statusCode: 200, message: error)
        }
        return response.result
    }

    /// Refreshes token and account state. Safe to call at launch; it also provisions the
    /// anonymous token that the addon and stream requests need.
    public func refresh(reason: String = "ping") async {
        do {
            try await ping(reason: reason)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Email & Password

    public func login(email: String, password: String) async throws {
        try await authenticate(email: email, password: password, call: "user.login", reason: "login")
    }

    public func register(email: String, password: String) async throws {
        try await authenticate(email: email, password: password, call: "user.register", reason: "register")
    }

    private func authenticate(email: String, password: String, call: String, reason: String) async throws {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleanEmail.range(of: "^.+@.+\\..+$", options: .regularExpression) != nil else {
            throw MediaHubError.httpError(statusCode: 400, message: L("Bitte gib eine gültige E-Mail-Adresse ein."))
        }
        guard !cleanPassword.isEmpty else {
            throw MediaHubError.httpError(statusCode: 400, message: L("Bitte gib dein Passwort ein."))
        }
        if currentUser?.email?.isEmpty == false {
            throw MediaHubError.httpError(statusCode: 400, message: L("Du bist bereits angemeldet."))
        }

        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            // The backend needs a token before it will accept credentials.
            if token == nil { try await ping(reason: "prepareLogin") }
            try await ping(reason: reason, call: call, params: ["email": cleanEmail, "password": cleanPassword])

            guard isLoggedIn else {
                throw MediaHubError.httpError(
                    statusCode: 401,
                    message: L("Anmeldung fehlgeschlagen. Bitte prüfe E-Mail und Passwort.")
                )
            }
            stopConnectCodePolling()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Connect Code Pairing

    /// Requests a connect code and keeps polling until the account is linked.
    /// The code itself comes from the backend; the first poll sends `code: null`.
    public func startConnectCodePolling() {
        guard !isLoggedIn else { return }
        pollingTask?.cancel()
        isRequestingCode = connectCode.isEmpty

        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                var delayMs: Double = 6000
                do {
                    let params: [String: Any] = [
                        "code": self.connectCode.isEmpty ? NSNull() : self.connectCode,
                        "interval": "fast"
                    ]
                    let result = try await self.ping(reason: "connect", call: "connect.check", params: params)

                    self.isRequestingCode = false
                    self.errorMessage = nil
                    if let code = result?.code, !code.isEmpty {
                        self.connectCode = code
                    }
                    if let next = result?.nextPing, next > 0 {
                        delayMs = next
                    }
                    if self.isLoggedIn {
                        self.pollingTask = nil
                        return
                    }
                } catch {
                    self.isRequestingCode = false
                    self.errorMessage = error.localizedDescription
                    // A rejected code is stale — drop it so the next poll requests a new one.
                    self.connectCode = ""
                    delayMs = 10000
                }

                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: UInt64(max(2000, delayMs) * 1_000_000))
            }
        }
    }

    public func stopConnectCodePolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isRequestingCode = false

        // Tell the backend to release the code.
        let code = connectCode
        guard !code.isEmpty else { return }
        connectCode = ""
        Task { [weak self] in
            try? await self?.ping(reason: "connectRemove", call: "connect.remove", params: ["code": code])
        }
    }

    // MARK: - Manual Token

    /// Accepts a token copied out of another Dezor installation and verifies it against
    /// the backend before adopting it.
    public func setManualToken(_ rawToken: String) async throws {
        var cleanToken = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanToken.lowercased().hasPrefix("bearer ") {
            cleanToken = String(cleanToken.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !cleanToken.isEmpty else {
            throw MediaHubError.httpError(statusCode: 400, message: L("Bitte gib einen Token ein."))
        }

        let previousToken = token
        let previousUser = currentUser
        isAuthenticating = true
        defer { isAuthenticating = false }

        token = cleanToken
        TokenStore.token = cleanToken

        do {
            try await ping(reason: "manualToken")
        } catch {
            token = previousToken
            if let previousToken {
                TokenStore.token = previousToken
            } else {
                TokenStore.token = nil
            }
            currentUser = previousUser
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Logout

    public func logout() async {
        stopConnectCodePolling()
        if currentUser?.hasAccount == true {
            _ = try? await ping(reason: "logout", call: "user.logout")
        }
        currentUser = nil
        token = nil
        UserDefaults.standard.removeObject(forKey: userKey)
        TokenStore.token = nil
        // Re-provision an anonymous token so playback keeps working at the free tier.
        await refresh(reason: "afterLogout")
    }

    // MARK: - Persistence

    private func persistUser(_ user: DezorUser) {
        guard user != currentUser else { return }
        currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }

    private func loadSavedUser() {
        guard let data = UserDefaults.standard.data(forKey: userKey),
              let user = try? JSONDecoder().decode(DezorUser.self, from: data) else {
            return
        }
        currentUser = user
    }
}
