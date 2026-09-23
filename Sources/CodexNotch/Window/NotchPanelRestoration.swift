import Foundation

/// A short recovery burst for asynchronous application, Space and display changes.
/// The injected scheduler must defer its operation, including a zero delay.
final class NotchPanelRestoration {
    typealias Cancellation = () -> Void
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Cancellation

    private let schedule: Scheduler
    private var generation = UUID()
    private var pending: [UUID: Cancellation] = [:]

    init(schedule: @escaping Scheduler = NotchPanelRestoration.scheduleOnMainQueue) {
        self.schedule = schedule
    }

    func request(_ operation: @escaping () -> Void) {
        cancel()
        let requestedGeneration = generation
        for delay in [0.0, 0.25, 0.75] {
            let identifier = UUID()
            pending[identifier] = schedule(delay) { [weak self] in
                guard let self, self.generation == requestedGeneration else { return }
                self.pending.removeValue(forKey: identifier)
                operation()
            }
        }
    }

    func cancel() {
        generation = UUID()
        let cancellations = Array(pending.values)
        pending.removeAll()
        cancellations.forEach { $0() }
    }

    deinit {
        cancel()
    }

    private static func scheduleOnMainQueue(
        after delay: TimeInterval,
        operation: @escaping () -> Void
    ) -> Cancellation {
        let work = DispatchWorkItem(block: operation)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return { work.cancel() }
    }

    /// Deterministic fixtures; does not create windows or access user state.
    static func runSelfChecks() throws -> Int {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw CheckError(message: message) }
            checks += 1
        }

        // An application or Space transition can finish withdrawing windows
        // after its first callback. Model the old single-pass failure first.
        let oldQueue = FixtureQueue()
        var oldSensorAvailable = false
        _ = oldQueue.schedule(0) { oldSensorAvailable = true }
        oldQueue.deliver(0)
        oldSensorAvailable = false
        oldQueue.deliver(0.75)
        try check(!oldSensorAvailable, "A single next-loop restore misses later window withdrawal")

        let queue = FixtureQueue()
        let restoration = NotchPanelRestoration(schedule: queue.schedule)
        var sensorAvailable = false
        var restoredGeometry: [Int] = []
        var currentGeometry = 1
        restoration.request {
            sensorAvailable = true
            restoredGeometry.append(currentGeometry)
        }
        try check(!sensorAvailable, "Restoration must not run inline during a workspace callback")
        try check(queue.entries.map(\.delay) == [0, 0.25, 0.75], "Recovery must be finite and cover the transition")
        queue.deliver(0)
        try check(sensorAvailable, "The next-loop callback restores the hover sensor")
        sensorAvailable = false
        currentGeometry = 2
        queue.deliver(0.25)
        try check(sensorAvailable, "The hover sensor recovers after late window withdrawal")
        sensorAvailable = false
        currentGeometry = 3
        queue.deliver(0.75)
        try check(sensorAvailable, "The final bounded pass recovers a later display transition")
        try check(restoredGeometry == [1, 2, 3], "Each pass must consult current geometry instead of a captured frame")
        queue.deliver(60)
        try check(restoredGeometry.count == 3 && queue.entries.count == 3, "Recovery must not become permanent polling")

        let cancelledQueue = FixtureQueue()
        let cancelled = NotchPanelRestoration(schedule: cancelledQueue.schedule)
        var hiddenSensorRestores = 0
        cancelled.request { hiddenSensorRestores += 1 }
        cancelled.cancel()
        try check(cancelledQueue.entries.allSatisfy(\.cancelled), "Hiding or stopping must cancel queued callbacks")
        cancelledQueue.deliver(1, evenIfCancelled: true)
        try check(hiddenSensorRestores == 0, "Already-enqueued stale callbacks must not revive a hidden or fallback panel")

        let replacedQueue = FixtureQueue()
        let replaced = NotchPanelRestoration(schedule: replacedQueue.schedule)
        var restoredRequests: [String] = []
        replaced.request { restoredRequests.append("old") }
        replaced.request { restoredRequests.append("current") }
        try check(replacedQueue.entries.prefix(3).allSatisfy(\.cancelled), "A new transition cancels its predecessor")
        replacedQueue.deliver(1, evenIfCancelled: true)
        try check(restoredRequests == ["current", "current", "current"], "Only the latest transition may restore its requested panel")

        let fallbackQueue = FixtureQueue()
        let fallback = NotchPanelRestoration(schedule: fallbackQueue.schedule)
        var fallbackPasses = 0
        fallback.request {
            fallbackPasses += 1
            // A fresh geometry render can discover mirroring or menu-bar mode.
            fallback.cancel()
        }
        fallbackQueue.deliver(1, evenIfCancelled: true)
        try check(fallbackPasses == 1, "Cancellation inside a geometry refresh invalidates the remaining passes")

        let releasedQueue = FixtureQueue()
        var released: NotchPanelRestoration? = NotchPanelRestoration(schedule: releasedQueue.schedule)
        var afterRelease = 0
        released?.request { afterRelease += 1 }
        released = nil
        try check(releasedQueue.entries.allSatisfy(\.cancelled), "Controller teardown must cancel recovery work")
        releasedQueue.deliver(1, evenIfCancelled: true)
        try check(afterRelease == 0, "Released restoration owners cannot revive a panel")
        return checks
    }

    private struct CheckError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private final class FixtureQueue {
        final class Entry {
            let delay: TimeInterval
            let operation: () -> Void
            var cancelled = false
            var delivered = false

            init(delay: TimeInterval, operation: @escaping () -> Void) {
                self.delay = delay
                self.operation = operation
            }
        }

        var entries: [Entry] = []

        func schedule(_ delay: TimeInterval, _ operation: @escaping () -> Void) -> Cancellation {
            let entry = Entry(delay: delay, operation: operation)
            entries.append(entry)
            return { entry.cancelled = true }
        }

        func deliver(_ through: TimeInterval, evenIfCancelled: Bool = false) {
            for entry in entries where entry.delay <= through && !entry.delivered {
                entry.delivered = true
                if !entry.cancelled || evenIfCancelled { entry.operation() }
            }
        }
    }
}
