import Foundation

extension MixerEngine {
    /// Release audio interception before sleep. The stored levels and routes
    /// remain intact; cached aggregate existence is not proof of running IO.
    func prepareForSleep() {
        routingTask?.cancel()
        routingTask = nil
        bluetoothRefreshTask?.cancel()
        bluetoothRefreshTask = nil
        wakeResyncTask?.cancel()
        wakeResyncTask = nil
        tapLifecycle.prepareForSleep()
        discardHALBoundState()
    }

    func recoverAfterWake() {
        wakeResyncTask?.cancel()
        tapLifecycle.prepareForWake()
        resyncAudioState()
        // Drivers and IOBluetooth often publish their final object IDs shortly
        // after didWake. One controlled second pass replaces a notification
        // storm and catches devices that were not ready on the immediate pass.
        wakeResyncTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(1), tolerance: .milliseconds(250))
            } catch {
                return
            }
            guard let self else { return }
            wakeResyncTask = nil
            guard !tapLifecycle.isSleeping else { return }
            resyncAudioState()
        }
    }

    private func resyncAudioState() {
        deviceMonitor.refresh()
        inputDeviceMonitor.refresh()
        multiOutput.handleDevicesChanged(present: deviceMonitor.devices)
        systemVolume.resync()
        inputVolume.resync()
        processMonitor.refresh()
        bluetooth.refresh()
        reconcileTapRouting()
    }
}
