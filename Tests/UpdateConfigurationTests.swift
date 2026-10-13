import Foundation
import Testing

@Suite("Update configuration and preferences")
struct UpdateConfigurationTests {
    private let key = Data(repeating: 1, count: 32).base64EncodedString()

    @Test("HTTPS feed requires a valid signing key")
    func validConfiguration() {
        #expect(UpdateConfiguration(info: ["SUFeedURL": "https://updates.example.org/appcast.xml", "SUPublicEDKey": key]).isReady)
        #expect(!UpdateConfiguration(info: ["SUFeedURL": "https://updates.example.org/appcast.xml"]).isReady)
        #expect(!UpdateConfiguration(info: ["SUPublicEDKey": key]).isReady)
    }

    @Test("insecure, credential-bearing, and invalid configurations never start checking")
    func rejectsUnsafeConfiguration() {
        for url in ["", "http://updates.example.org/appcast.xml", "https://secret:password@updates.example.org/feed", "https://updates.example.org/feed#fragment"] {
            #expect(!UpdateConfiguration(info: ["SUFeedURL": url, "SUPublicEDKey": key]).isReady)
        }
        #expect(!UpdateConfiguration(info: ["SUFeedURL": "https://updates.example.org/feed", "SUPublicEDKey": "invalid"]).isReady)
    }

    @Test("automatic checks default off and persist without changing audio preferences")
    func savesUserChoice() throws {
        let suite = "LevelsUpdatePreferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unchanged-audio-settings", forKey: "appVolumes")
        let first = UpdatePreferences(defaults: defaults)
        #expect(!first.automaticallyChecks)
        first.automaticallyChecks = true
        #expect(UpdatePreferences(defaults: defaults).automaticallyChecks)
        first.automaticallyChecks = false
        #expect(!UpdatePreferences(defaults: defaults).automaticallyChecks)
        #expect(defaults.string(forKey: "appVolumes") == "unchanged-audio-settings")
    }
}
