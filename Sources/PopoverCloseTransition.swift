import Foundation

/// A closing deadline independent of Core Animation's completion callbacks.
/// Cancellation invalidates the old close before a new presentation starts.
@MainActor
final class PopoverCloseTransition {
    private let duration: Duration
    private(set) var pendingTask: Task<Void, Never>?
    var isClosing: Bool { pendingTask != nil }

    init(duration: Duration = .milliseconds(180)) { self.duration = duration }

    @discardableResult
    func begin(animate: () -> Void, close: @escaping @MainActor () -> Void) -> Bool {
        guard pendingTask == nil else { return false }
        pendingTask = Task { @MainActor [weak self, duration] in
            do { try await Task.sleep(for: duration) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            self.pendingTask = nil
            close()
        }
        // Mark the transition first: starting it can synchronously trigger
        // another dismissal through a native menu-session callback.
        animate()
        return true
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}
