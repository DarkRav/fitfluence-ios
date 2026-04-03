import Foundation

struct SyncOutboxMutationResult: Equatable, Sendable {
    let operation: SyncOperation?
    let wasIgnored: Bool
    let ignoredReason: String?
}

actor SyncOutboxStore {
    private struct PersistedState: Codable, Equatable, Sendable {
        var operations: [SyncOperation]
        var logs: [SyncLogEntry]
        var lastSyncAttemptAt: Date?
        var lastSyncError: String?

        static let empty = PersistedState(
            operations: [],
            logs: [],
            lastSyncAttemptAt: nil,
            lastSyncError: nil,
        )
    }

    private let baseURL: URL
    private let fileManager: FileManager
    private var stateByNamespace: [String: PersistedState] = [:]

    init(
        baseURL: URL? = nil,
        fileManager: FileManager = .default,
    ) {
        self.fileManager = fileManager

        if let baseURL {
            self.baseURL = baseURL
        } else {
            let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.baseURL = root.appendingPathComponent("fitfluence-sync-outbox", isDirectory: true)
        }

        ensureRootExists()
    }

    func enqueue(_ operation: SyncOperation, namespace: String) async -> SyncOutboxMutationResult {
        var state = loadState(namespace: namespace)
        let now = Date()

        let result = applyEnqueue(operation: operation, in: &state, now: now)
        pruneTerminalOperations(in: &state)
        persist(state: state, namespace: namespace)
        stateByNamespace[namespace] = state

        return result
    }

    func unsentOperations(namespace: String, at date: Date = Date()) async -> [SyncOperation] {
        let state = loadState(namespace: namespace)
        return state.operations
            .filter { operation in
                guard operation.status.isUnsent else { return false }
                if operation.status == .error,
                   let nextRetryAt = operation.nextRetryAt,
                   nextRetryAt > date
                {
                    return false
                }
                return true
            }
            .sorted(by: sortByCreatedAt)
    }

    func allOperations(namespace: String) async -> [SyncOperation] {
        let state = loadState(namespace: namespace)
        return state.operations.sorted(by: sortByCreatedAt)
    }

    func recoverInFlight(namespace: String) async {
        var state = loadState(namespace: namespace)
        let now = Date()
        var hasChanges = false

        for index in state.operations.indices where state.operations[index].status == .inFlight {
            state.operations[index].status = .pending
            state.operations[index].updatedAt = now
            hasChanges = true

            appendLog(
                to: &state,
                SyncLogEntry(
                    operationId: state.operations[index].id,
                    operationType: state.operations[index].type,
                    operationStatus: .pending,
                    message: "Recovered IN_FLIGHT operation after restart",
                ),
            )
        }

        if hasChanges {
            persist(state: state, namespace: namespace)
            stateByNamespace[namespace] = state
        }
    }

    func markInFlight(operationId: UUID, namespace: String) async {
        mutate(namespace: namespace) { state in
            guard let index = state.operations.firstIndex(where: { $0.id == operationId }) else { return }
            state.operations[index].markInFlight(at: Date())
            appendLog(
                to: &state,
                SyncLogEntry(
                    operationId: state.operations[index].id,
                    operationType: state.operations[index].type,
                    operationStatus: .inFlight,
                    message: "Operation moved to IN_FLIGHT",
                ),
            )
        }
    }

    func markSent(operationId: UUID, namespace: String) async {
        mutate(namespace: namespace) { state in
            guard let index = state.operations.firstIndex(where: { $0.id == operationId }) else { return }
            state.operations[index].markSent(at: Date())
            appendLog(
                to: &state,
                SyncLogEntry(
                    operationId: state.operations[index].id,
                    operationType: state.operations[index].type,
                    operationStatus: .sent,
                    message: "Operation sent",
                ),
            )
            state.lastSyncError = nil
        }
    }

    func markRetryableError(
        operationId: UUID,
        namespace: String,
        error: String,
        nextRetryAt: Date?,
        retryCount: Int,
    ) async {
        mutate(namespace: namespace) { state in
            guard let index = state.operations.firstIndex(where: { $0.id == operationId }) else { return }
            state.operations[index].retryCount = retryCount
            state.operations[index].markError(error: error, nextRetryAt: nextRetryAt, at: Date())
            state.lastSyncError = error
            appendLog(
                to: &state,
                SyncLogEntry(
                    operationId: state.operations[index].id,
                    operationType: state.operations[index].type,
                    operationStatus: .error,
                    message: "Operation failed, scheduled retry",
                    error: error,
                ),
            )
        }
    }

    func markDead(operationId: UUID, namespace: String, error: String) async {
        mutate(namespace: namespace) { state in
            guard let index = state.operations.firstIndex(where: { $0.id == operationId }) else { return }
            state.operations[index].markDead(error: error, at: Date())
            state.lastSyncError = error
            appendLog(
                to: &state,
                SyncLogEntry(
                    operationId: state.operations[index].id,
                    operationType: state.operations[index].type,
                    operationStatus: .dead,
                    message: "Operation moved to DEAD",
                    error: error,
                ),
            )
        }
    }

    func markSyncAttempt(namespace: String, error: String?) async {
        mutate(namespace: namespace) { state in
            state.lastSyncAttemptAt = Date()
            if let error {
                state.lastSyncError = error
            }
        }
    }

    func diagnostics(namespace: String, logLimit: Int = 80) async -> SyncDiagnosticsSnapshot {
        let state = loadState(namespace: namespace)
        let pendingCount = state.operations.count(where: { $0.status.isUnsent })
        let hasDelayedRetries = state.operations.contains(where: { operation in
            if operation.status == .error, operation.nextRetryAt == nil {
                return true
            }
            return operation.status == .error && operation.retryCount >= 3
        })

        return SyncDiagnosticsSnapshot(
            pendingCount: pendingCount,
            lastSyncAttemptAt: state.lastSyncAttemptAt,
            lastSyncError: state.lastSyncError,
            logs: Array(state.logs.suffix(max(1, logLimit))),
            hasDelayedRetries: hasDelayedRetries,
        )
    }

    func appendSystemLog(namespace: String, message: String, error: String? = nil) async {
        mutate(namespace: namespace) { state in
            appendLog(
                to: &state,
                SyncLogEntry(
                    operationId: nil,
                    operationType: nil,
                    operationStatus: nil,
                    message: message,
                    error: error,
                ),
            )
            if let error {
                state.lastSyncError = error
            }
        }
    }

    func exportLogText(namespace: String, limit: Int = 200) async -> String {
        let state = loadState(namespace: namespace)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let lines = state.logs.suffix(max(1, limit)).map { entry in
            let ts = formatter.string(from: entry.timestamp)
            let opType = entry.operationType?.rawValue ?? "SYSTEM"
            let opId = entry.operationId?.uuidString ?? "-"
            let status = entry.operationStatus?.rawValue ?? "-"
            let errorChunk = entry.error.map { " error=\($0)" } ?? ""
            return "\(ts) type=\(opType) id=\(opId) status=\(status) msg=\(entry.message)\(errorChunk)"
        }

        return lines.joined(separator: "\n")
    }

    func pendingCount(namespace: String) async -> Int {
        let state = loadState(namespace: namespace)
        return state.operations.count(where: { $0.status.isUnsent })
    }

    func hasPendingAbandon(namespace: String, workoutInstanceId: String) async -> Bool {
        let state = loadState(namespace: namespace)
        return state.operations.contains { operation in
            operation.workoutInstanceId == workoutInstanceId &&
                operation.type == .abandonWorkout &&
                operation.status.isUnsent
        }
    }

    private func applyEnqueue(
        operation: SyncOperation,
        in state: inout PersistedState,
        now: Date,
    ) -> SyncOutboxMutationResult {
        let unsentIndices = state.operations.indices.filter { state.operations[$0].status.isUnsent }

        if let workoutId = operation.workoutInstanceId {
            if operation.type == .upsertSet,
               let terminal = state.operations.first(where: {
                   $0.workoutInstanceId == workoutId &&
                       $0.status.isUnsent &&
                       ($0.type == .completeWorkout || $0.type == .abandonWorkout)
               })
            {
                appendLog(
                    to: &state,
                    SyncLogEntry(
                        operationId: terminal.id,
                        operationType: terminal.type,
                        operationStatus: terminal.status,
                        message: "Ignored set update because terminal operation is already queued",
                    ),
                )
                return SyncOutboxMutationResult(operation: terminal, wasIgnored: true, ignoredReason: "terminal_exists")
            }

            if operation.type == .completeWorkout,
               let abandon = state.operations.first(where: {
                   $0.workoutInstanceId == workoutId && $0.status.isUnsent && $0.type == .abandonWorkout
               })
            {
                appendLog(
                    to: &state,
                    SyncLogEntry(
                        operationId: abandon.id,
                        operationType: abandon.type,
                        operationStatus: abandon.status,
                        message: "Ignored COMPLETE_WORKOUT because ABANDON_WORKOUT is already queued",
                    ),
                )
                return SyncOutboxMutationResult(operation: abandon, wasIgnored: true, ignoredReason: "abandon_conflict")
            }

            if operation.type == .abandonWorkout {
                for index in unsentIndices where state.operations[index].workoutInstanceId == workoutId {
                    switch state.operations[index].type {
                    case .upsertSet, .completeWorkout:
                        state.operations[index].markDead(error: "discarded_by_abandon", at: now)
                        appendLog(
                            to: &state,
                            SyncLogEntry(
                                operationId: state.operations[index].id,
                                operationType: state.operations[index].type,
                                operationStatus: .dead,
                                message: "Discarded because ABANDON_WORKOUT was queued",
                            ),
                        )
                    case .startWorkout, .abandonWorkout:
                        continue
                    }
                }
            }
        }

        if let existingIndex = unsentIndices.first(where: { state.operations[$0].dedupeKey == operation.dedupeKey }) {
            state.operations[existingIndex] = state.operations[existingIndex].withUpdatedPayload(operation.payload, at: now)
            appendLog(
                to: &state,
                SyncLogEntry(
                    operationId: state.operations[existingIndex].id,
                    operationType: state.operations[existingIndex].type,
                    operationStatus: .pending,
                    message: "Operation deduped and payload updated",
                ),
            )
            return SyncOutboxMutationResult(operation: state.operations[existingIndex], wasIgnored: false, ignoredReason: nil)
        }

        state.operations.append(operation)
        appendLog(
            to: &state,
            SyncLogEntry(
                operationId: operation.id,
                operationType: operation.type,
                operationStatus: .pending,
                message: "Operation queued",
            ),
        )
        return SyncOutboxMutationResult(operation: operation, wasIgnored: false, ignoredReason: nil)
    }

    private func mutate(namespace: String, block: (inout PersistedState) -> Void) {
        var state = loadState(namespace: namespace)
        block(&state)
        pruneTerminalOperations(in: &state)
        persist(state: state, namespace: namespace)
        stateByNamespace[namespace] = state
    }

    private func appendLog(to state: inout PersistedState, _ entry: SyncLogEntry) {
        state.logs.append(entry)
        if state.logs.count > 400 {
            state.logs.removeFirst(state.logs.count - 400)
        }

        let opType = entry.operationType?.rawValue ?? "SYSTEM"
        let opId = entry.operationId?.uuidString ?? "-"
        let opStatus = entry.operationStatus?.rawValue ?? "-"
        let errorChunk = entry.error.map { " error=\($0)" } ?? ""
        FFLog.info("sync-log type=\(opType) id=\(opId) status=\(opStatus) msg=\(entry.message)\(errorChunk)")
    }

    private func pruneTerminalOperations(in state: inout PersistedState) {
        let terminalIndices = state.operations
            .indices
            .filter { index in
                let status = state.operations[index].status
                return status == .sent || status == .dead
            }

        guard terminalIndices.count > 150 else { return }

        let sorted = terminalIndices.sorted { lhs, rhs in
            state.operations[lhs].updatedAt < state.operations[rhs].updatedAt
        }

        let extra = terminalIndices.count - 150
        for index in sorted.prefix(extra).sorted(by: >) {
            state.operations.remove(at: index)
        }
    }

    private func loadState(namespace: String) -> PersistedState {
        if let cached = stateByNamespace[namespace] {
            return cached
        }

        let url = fileURL(namespace: namespace)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PersistedState.self, from: data)
        else {
            stateByNamespace[namespace] = .empty
            return .empty
        }

        stateByNamespace[namespace] = decoded
        return decoded
    }

    private func persist(state: PersistedState, namespace: String) {
        let namespaceURL = directoryURL(namespace: namespace)
        if !fileManager.fileExists(atPath: namespaceURL.path) {
            try? fileManager.createDirectory(at: namespaceURL, withIntermediateDirectories: true)
        }

        guard let payload = try? JSONEncoder().encode(state) else { return }

        let targetURL = fileURL(namespace: namespace)
        let tmpURL = namespaceURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("tmp")

        do {
            try payload.write(to: tmpURL, options: .atomic)
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.moveItem(at: tmpURL, to: targetURL)
        } catch {
            try? fileManager.removeItem(at: tmpURL)
            FFLog.error("sync-outbox persist failed namespace=\(namespace) error=\(error.localizedDescription)")
        }
    }

    private func ensureRootExists() {
        if !fileManager.fileExists(atPath: baseURL.path) {
            try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }
    }

    private func directoryURL(namespace: String) -> URL {
        baseURL.appendingPathComponent(safeFilename(namespace), isDirectory: true)
    }

    private func fileURL(namespace: String) -> URL {
        directoryURL(namespace: namespace)
            .appendingPathComponent("outbox")
            .appendingPathExtension("json")
    }

    private func safeFilename(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    private func sortByCreatedAt(lhs: SyncOperation, rhs: SyncOperation) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.updatedAt < rhs.updatedAt
        }
        return lhs.createdAt < rhs.createdAt
    }
}
