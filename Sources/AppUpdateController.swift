import AppKit
import Observation
import Sparkle

/// Sparkle owns scheduling, archive verification, install prompts, and relaunch.
/// No update networking starts until a real HTTPS feed and key are configured.
@MainActor @Observable
final class AppUpdateController: NSObject, @preconcurrency SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private let configuration: UpdateConfiguration
    private let preferences: UpdatePreferences
    private let availability: UpdateAvailability
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored var onAvailabilityChange: (() -> Void)?
    private(set) var availableVersion: String?

    init(defaults: UserDefaults = .standard, info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        configuration = UpdateConfiguration(info: info)
        preferences = UpdatePreferences(defaults: defaults)
        availability = UpdateAvailability(defaults: defaults, currentBuild: info["CFBundleVersion"] as? String ?? "0")
        availableVersion = availability.version
        super.init()
    }

    var isConfigured: Bool { configuration.isReady }
    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? true }
    var automaticallyChecks: Bool { controller?.updater.automaticallyChecksForUpdates ?? preferences.automaticallyChecks }
    var hasUpdateAvailable: Bool { availableVersion != nil }

    func start() {
        guard configuration.isReady, controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    func checkForUpdates() {
        guard configuration.isReady else {
            let alert = NSAlert()
            alert.messageText = "Updates aren’t available yet"
            alert.informativeText = "Updates haven’t been published for this build yet. You can check here once the update service is available."
            alert.addButton(withTitle: "Done")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        start()
        if controller?.updater.canCheckForUpdates == true {
            controller?.checkForUpdates(nil)
        }
    }

    func setAutomaticChecks(_ enabled: Bool) {
        if let controller {
            controller.updater.automaticallyChecksForUpdates = enabled
        } else {
            preferences.automaticallyChecks = enabled
        }
    }

    private func refreshAvailability() {
        let next = availability.version
        guard availableVersion != next else { return }
        availableVersion = next
        onAvailabilityChange?()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availability.found(version: item.displayVersionString, build: item.versionString)
        refreshAvailability()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availability.clear()
        refreshAvailability()
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Scheduled checks use our dot/menu reminder. Manual checks still open
        // Sparkle's normal install dialog, and installation needs user approval.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availability.found(version: update.displayVersionString, build: update.versionString)
        refreshAvailability()
    }

    func standardUserDriverWillFinishUpdateSession() { refreshAvailability() }

    #if RENDER_SHOTS
    func seedAvailableUpdateForRender(version: String, build: String) {
        availability.found(version: version, build: build)
        refreshAvailability()
    }
    #endif
}
