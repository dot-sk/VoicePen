import Foundation

protocol HotkeyHoldScheduler: AnyObject {
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> CancellableTask
}

protocol CancellableTask: AnyObject {
    func cancel()
}

final class LiveHotkeyHoldScheduler: HotkeyHoldScheduler {
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> CancellableTask {
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action()
        }
        return TaskCancellable(task: task)
    }
}

private final class TaskCancellable: CancellableTask {
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task.cancel()
    }
}

@MainActor
final class HotkeyHoldGate {
    private let holdDuration: TimeInterval
    private let scheduler: HotkeyHoldScheduler
    private var pendingTask: CancellableTask?
    private var didTrigger = false

    convenience init(holdDuration: TimeInterval) {
        self.init(holdDuration: holdDuration, scheduler: LiveHotkeyHoldScheduler())
    }

    init(holdDuration: TimeInterval, scheduler: HotkeyHoldScheduler) {
        self.holdDuration = holdDuration
        self.scheduler = scheduler
    }

    func keyDown(onTrigger: @escaping @MainActor () -> Void) {
        guard pendingTask == nil, !didTrigger else { return }

        pendingTask = scheduler.schedule(after: holdDuration) { [weak self] in
            guard let self else { return }
            self.pendingTask = nil
            self.didTrigger = true
            onTrigger()
        }
    }

    func keyUp(onReleaseAfterTrigger: @escaping @MainActor () -> Void) {
        pendingTask?.cancel()
        pendingTask = nil

        guard didTrigger else { return }
        didTrigger = false
        onReleaseAfterTrigger()
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
        didTrigger = false
    }
}
