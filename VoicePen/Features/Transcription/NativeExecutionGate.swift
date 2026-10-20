import Foundation

actor NativeExecutionGate {
    static let shared = NativeExecutionGate()
    private var owner: UUID?
    private var queue: [(UUID, CheckedContinuation<UUID, Error>)] = []
    private var queueObservers: [CheckedContinuation<Void, Never>] = []

    var queuedCount: Int { queue.count }

    func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        let ticket = try await acquire()
        do {
            try Task.checkCancellation()
            let value = try await operation()
            release(ticket)
            try Task.checkCancellation()
            return value
        } catch {
            release(ticket)
            throw error
        }
    }

    func acquire() async throws -> UUID {
        try Task.checkCancellation()
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard owner != nil else {
                    owner = id
                    continuation.resume(returning: id)
                    return
                }
                queue.append((id, continuation))
                queueObservers.forEach { $0.resume() }
                queueObservers.removeAll()
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func release(_ id: UUID) {
        guard owner == id else { return }
        if queue.isEmpty {
            owner = nil
            return
        }
        let next = queue.removeFirst()
        owner = next.0
        next.1.resume(returning: next.0)
    }

    func waitUntilQueued() async {
        if !queue.isEmpty { return }
        await withCheckedContinuation { queueObservers.append($0) }
    }

    private func cancel(_ id: UUID) {
        guard let index = queue.firstIndex(where: { $0.0 == id }) else { return }
        queue.remove(at: index).1.resume(throwing: CancellationError())
    }
}

nonisolated final class NativeContextLease: @unchecked Sendable {
    private let release: @Sendable () -> Void
    init(release: @escaping @Sendable () -> Void) { self.release = release }
    deinit { release() }
}
