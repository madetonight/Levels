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
        get { defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: "SUEnableAutomaticChecks") }
    }
}

/// Keep a verified update visible across relaunches, without caching an alert
/// for a build that has already been installed or was explicitly skipped.
struct UpdateAvailability {
    let defaults: UserDefaults
    let currentBuild: String
    private static let buildKey = "LevelsAvailableUpdateBuild"
    private static let versionKey = "LevelsAvailableUpdateVersion"

    var version: String? {
        guard let build = defaults.string(forKey: Self.buildKey),
              build.compare(currentBuild, options: .numeric) == .orderedDescending,
              defaults.string(forKey: "SUSkippedVersion") != build else { return nil }
        return defaults.string(forKey: Self.versionKey)
    }

    func found(version: String, build: String) {
        guard build.compare(currentBuild, options: .numeric) == .orderedDescending else {
            clear()
            return
        }
        defaults.set(build, forKey: Self.buildKey)
        defaults.set(version, forKey: Self.versionKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.buildKey)
        defaults.removeObject(forKey: Self.versionKey)
    }
}
