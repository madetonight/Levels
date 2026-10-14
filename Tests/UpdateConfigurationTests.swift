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

    @Test("automatic checks default on; a saved opt-out persists without changing audio preferences")
    func savesUserChoice() throws {
        let suite = "LevelsUpdatePreferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unchanged-audio-settings", forKey: "appVolumes")
        let first = UpdatePreferences(defaults: defaults)
        #expect(first.automaticallyChecks)
        first.automaticallyChecks = true
        #expect(UpdatePreferences(defaults: defaults).automaticallyChecks)
        first.automaticallyChecks = false
        #expect(!UpdatePreferences(defaults: defaults).automaticallyChecks)
        #expect(defaults.string(forKey: "appVolumes") == "unchanged-audio-settings")
    }

    @Test("update reminder survives relaunch, clears after installation, and respects a skipped version")
    func updateReminder() throws {
        let suite = "LevelsUpdateNotice-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("preserved", forKey: "appVolumes")
        let notice = UpdateAvailability(defaults: defaults, currentBuild: "9")
        #expect(notice.version == nil)
        notice.found(version: "0.1.8", build: "10")
        #expect(UpdateAvailability(defaults: defaults, currentBuild: "9").version == "0.1.8")
        #expect(UpdateAvailability(defaults: defaults, currentBuild: "10").version == nil)
        defaults.set("10", forKey: "SUSkippedVersion")
        #expect(notice.version == nil)
        notice.found(version: "0.1.9", build: "11")
        #expect(notice.version == "0.1.9")
        notice.clear()
        #expect(notice.version == nil)
        #expect(defaults.string(forKey: "appVolumes") == "preserved")
    }
}
