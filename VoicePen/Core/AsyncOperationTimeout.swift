import Foundation

enum AsyncOperationTimeout {
    static func run<T: Sendable>(
        timeout: Duration,
        timeoutError: @escaping () -> Error,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let controller = AsyncOperationTimeoutController()

        return try await withTaskCancellationHandler {
            controller.start(
                timeout: timeout,
                timeoutError: timeoutError,
                operation: {
                    AsyncOperationTimeoutValue(try await operation())
                }
            )
            defer { controller.cancelOutstandingTasks() }

            let result = await controller.wait()
            return try result.get().cast(to: T.self)
        } onCancel: {
            Task { @MainActor in
                controller.cancel()
            }
        }
    }
}

private final class AsyncOperationTimeoutController: @unchecked Sendable {
    private let state = AsyncOperationTimeoutState()
    private let lock = NSLock()
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func start(
        timeout: Duration,
        timeoutError: @escaping () -> Error,
        operation: @escaping () async throws -> AsyncOperationTimeoutValue
    ) {
        let operationTask = Task {
            do {
                let value = try await operation()
                await self.state.finish(.success(value))
            } catch {
                await self.state.finish(.failure(error))
            }
        }

        let timeoutTask = Task {
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }

            operationTask.cancel()
            await self.state.finish(.failure(timeoutError()))
        }

        lock.lock()
        self.operationTask = operationTask
        self.timeoutTask = timeoutTask
        lock.unlock()
    }

    func wait() async -> Result<AsyncOperationTimeoutValue, Error> {
        await state.wait()
    }

    func cancelOutstandingTasks() {
        let tasks = tasks()
        tasks.operation?.cancel()
        tasks.timeout?.cancel()
    }

    func cancel() {
        cancelOutstandingTasks()
        Task {
            await state.finish(.failure(CancellationError()))
        }
    }

    private func tasks() -> (operation: Task<Void, Never>?, timeout: Task<Void, Never>?) {
        lock.lock()
        defer { lock.unlock() }
        return (operationTask, timeoutTask)
    }
}

// Keep the timeout controller non-generic. The Release optimizer currently
// crashes on the generic variant in this target.
private struct AsyncOperationTimeoutValue: @unchecked Sendable {
    private let value: Any

    init(_ value: some Sendable) {
        self.value = value
    }

    func cast<T>(to _: T.Type) throws -> T {
        guard let typedValue = value as? T else {
            throw CancellationError()
        }
        return typedValue
    }
}

private actor AsyncOperationTimeoutState {
    private var result: Result<AsyncOperationTimeoutValue, Error>?
    private var continuation: CheckedContinuation<Result<AsyncOperationTimeoutValue, Error>, Never>?

    func finish(_ result: Result<AsyncOperationTimeoutValue, Error>) {
        guard self.result == nil else { return }

        self.result = result
        continuation?.resume(returning: result)
        continuation = nil
    }

    func wait() async -> Result<AsyncOperationTimeoutValue, Error> {
        if let result {
            return result
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}
