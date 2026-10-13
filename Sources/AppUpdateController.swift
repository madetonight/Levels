import AppKit
import Sparkle

/// Sparkle owns scheduling, archive verification, install prompts, and relaunch.
/// No update networking starts until a real HTTPS feed and key are configured.
@MainActor
final class AppUpdateController {
    private let configuration: UpdateConfiguration
    private let preferences: UpdatePreferences
    private var controller: SPUStandardUpdaterController?

    init(defaults: UserDefaults = .standard, info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        configuration = UpdateConfiguration(info: info)
        preferences = UpdatePreferences(defaults: defaults)
    }

    var isConfigured: Bool { configuration.isReady }
    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? true }
    var automaticallyChecks: Bool { controller?.updater.automaticallyChecksForUpdates ?? preferences.automaticallyChecks }

    func start() {
        guard configuration.isReady, controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
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
}
