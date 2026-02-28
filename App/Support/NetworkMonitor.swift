import Foundation
import Network

protocol NetworkMonitoring: Sendable {
    var currentStatus: Bool { get }
    func statusUpdates() -> AsyncStream<Bool>
}

final class NetworkMonitor: NetworkMonitoring, @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private let relay = NetworkStatusRelay()

    private let lock = NSLock()
    private var isOnlineValue = true

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        queue = DispatchQueue(label: "com.fitfluence.network.monitor")

        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            self?.updateStatus(online)
        }

        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    var currentStatus: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isOnlineValue
    }

    func statusUpdates() -> AsyncStream<Bool> {
        relay.stream(initial: currentStatus)
    }

    private func updateStatus(_ isOnline: Bool) {
        lock.lock()
        isOnlineValue = isOnline
        lock.unlock()

        relay.broadcast(isOnline)
    }
}

private final class NetworkStatusRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    func stream(initial: Bool) -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.yield(initial)
            continuation.onTermination = { [weak self] _ in
                self?.remove(id)
            }
        }
    }

    func broadcast(_ value: Bool) {
        lock.lock()
        let all = continuations.values
        lock.unlock()
        for continuation in all {
            continuation.yield(value)
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        continuations[id] = nil
        lock.unlock()
    }
}

struct StaticNetworkMonitor: NetworkMonitoring {
    let currentStatus: Bool

    func statusUpdates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            continuation.yield(currentStatus)
            continuation.finish()
        }
    }
}
