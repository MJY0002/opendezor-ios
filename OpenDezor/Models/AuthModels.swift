import Foundation

/// Mirrors the `user` record returned by every `/api/app/ping` response.
/// Field names and defaults follow the Dezor ping API.
public struct DezorUser: Codable, Equatable {
    public var email: String?
    public var refKey: String?
    public var hasAccount: Bool
    public var hasPremium: Bool
    public var premiumRuntime: Double
    public var hasSubscription: Bool
    public var subscriptionExpiresSoon: Bool
    public var subscriptionInit: Double
    public var nextBilling: Double
    public var forceRegister: Bool
    /// Milliseconds of playback the backend still grants this token. Anonymous tokens get
    /// 300000 (5 minutes); a premium account raises or removes the cap.
    public var remainingPlayDuration: Double
    public var remainingProxyDuration: Double
    public var tokenLock: Bool

    public init(
        email: String? = nil,
        refKey: String? = nil,
        hasAccount: Bool = false,
        hasPremium: Bool = false,
        premiumRuntime: Double = 0,
        hasSubscription: Bool = false,
        subscriptionExpiresSoon: Bool = false,
        subscriptionInit: Double = 0,
        nextBilling: Double = 0,
        forceRegister: Bool = false,
        remainingPlayDuration: Double = 24 * 3600 * 1000,
        remainingProxyDuration: Double = 24 * 3600 * 1000,
        tokenLock: Bool = false
    ) {
        self.email = email
        self.refKey = refKey
        self.hasAccount = hasAccount
        self.hasPremium = hasPremium
        self.premiumRuntime = premiumRuntime
        self.hasSubscription = hasSubscription
        self.subscriptionExpiresSoon = subscriptionExpiresSoon
        self.subscriptionInit = subscriptionInit
        self.nextBilling = nextBilling
        self.forceRegister = forceRegister
        self.remainingPlayDuration = remainingPlayDuration
        self.remainingProxyDuration = remainingProxyDuration
        self.tokenLock = tokenLock
    }

    // The backend omits fields freely and sends `coupons`/`userModal` shapes we do not model,
    // so every key decodes leniently with the documented default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? nil
        refKey = try c.decodeIfPresent(String.self, forKey: .refKey) ?? nil
        hasAccount = try c.decodeIfPresent(Bool.self, forKey: .hasAccount) ?? false
        hasPremium = try c.decodeIfPresent(Bool.self, forKey: .hasPremium) ?? false
        premiumRuntime = try c.decodeIfPresent(Double.self, forKey: .premiumRuntime) ?? 0
        hasSubscription = try c.decodeIfPresent(Bool.self, forKey: .hasSubscription) ?? false
        subscriptionExpiresSoon = try c.decodeIfPresent(Bool.self, forKey: .subscriptionExpiresSoon) ?? false
        subscriptionInit = try c.decodeIfPresent(Double.self, forKey: .subscriptionInit) ?? 0
        nextBilling = try c.decodeIfPresent(Double.self, forKey: .nextBilling) ?? 0
        forceRegister = try c.decodeIfPresent(Bool.self, forKey: .forceRegister) ?? false
        remainingPlayDuration = try c.decodeIfPresent(Double.self, forKey: .remainingPlayDuration) ?? 0
        remainingProxyDuration = try c.decodeIfPresent(Double.self, forKey: .remainingProxyDuration) ?? 0
        tokenLock = try c.decodeIfPresent(Bool.self, forKey: .tokenLock) ?? false
    }

    public var displayName: String {
        if let email, !email.isEmpty { return email }
        return hasAccount ? L("Dezor Account") : L("Nicht angemeldet")
    }

    /// `premiumRuntime` is a millisecond epoch; 0 means "no expiry stored".
    public var formattedExpiryDate: String {
        guard premiumRuntime > 0 else {
            return hasSubscription ? L("Aktives Abo") : (hasPremium ? L("Unbegrenzt aktiv") : L("Kein Premium"))
        }
        let date = Date(timeIntervalSince1970: premiumRuntime / 1000.0)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: LocalizationController.shared.code == "de" ? "de_DE" : "en_US")
        return formatter.string(from: date)
    }

    /// Human-readable form of the remaining playback allowance.
    public var formattedRemainingPlayTime: String {
        let minutes = Int(remainingPlayDuration / 60000)
        if minutes >= 60 {
            return "\(minutes / 60) \(L("Std.")) \(minutes % 60) \(L("Min."))"
        }
        return "\(minutes) \(L("Min."))"
    }
}
