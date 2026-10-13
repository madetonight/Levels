import Foundation

/// Reject unconfigured or insecure feeds before starting the updater.
struct UpdateConfiguration {
    let feedURL: URL?
    let publicKey: String?

    init(info: [String: Any]) {
        let address = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        if let url = URL(string: address), url.scheme == "https",
           let host = url.host, !host.isEmpty,
           url.user == nil, url.password == nil, url.fragment == nil {
            feedURL = url
        } else {
            feedURL = nil
        }
        publicKey = Data(base64Encoded: key)?.count == 32 ? key : nil
    }

    var isReady: Bool { feedURL != nil && publicKey != nil }
}

struct UpdatePreferences {
    let defaults: UserDefaults

    var automaticallyChecks: Bool {
        get { defaults.bool(forKey: "SUEnableAutomaticChecks") }
        nonmutating set { defaults.set(newValue, forKey: "SUEnableAutomaticChecks") }
    }
}
