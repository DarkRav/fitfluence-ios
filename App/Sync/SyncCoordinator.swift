import Foundation
import UIKit

actor SyncCoordinator {
    static let shared = SyncCoordinator()

    private let outboxStore: SyncOutboxStore
    private let worker: SyncWorker

    private var athleteTrainingClient: AthleteTrainingClientProtocol?
    private var networkMonitor: NetworkMonitoring

    private var activeNamespace: String?
    private var isStarted = false

    private var networkObserverTask: Task<Void, Never>?
    private var foregroundTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?

    private let periodicIntervalSeconds: UInt64

    init(
        outboxStore: SyncOutboxStore = SyncOutboxStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
        periodicIntervalSeconds: UInt64 = 180,
    ) {
        self.outboxStore = outboxStore
        worker = SyncWorker(outboxStore: outboxStore)
        self.networkMonitor = networkMonitor
        self.periodicIntervalSeconds = periodicIntervalSeconds
    }

    func configure(
        athleteTrainingClient: AthleteTrainingClientProtocol?,
        networkMonitor: NetworkMonitoring,
    ) async {
        self.athleteTrainingClient = athleteTrainingClient
        self.networkMonitor = networkMonitor
        startIfNeeded()
    }

    func activate(namespace: String) async {
        await prepareNamespace(namespace: namespace)
        await processNow(reason: "activate")
    }

    func enqueueUpsertSet(
        namespace: String,
        workoutInstanceId: String?,
        exerciseExecutionId: String,
        setNumber: Int,
        weight: Double?,
        reps: Int?,
        rpe: Int?,
        isCompleted: Bool?,
        isWarmup: Bool?,
        restSecondsActual: Int?,
        processImmediately: Bool = true,
    ) async -> SyncOutboxMutationResult {
        await prepareNamespace(namespace: namespace)

        if let workoutInstanceId {
            _ = await outboxStore.enqueue(
                .startWorkout(workoutInstanceId: workoutInstanceId, startedAt: nil),
                namespace: namespace,
            )
        }

        let result = await outboxStore.enqueue(
            .upsertSet(
                workoutInstanceId: workoutInstanceId,
                exerciseExecutionId: exerciseExecutionId,
                setNumber: setNumber,
                weight: weight,
                reps: reps,
                rpe: rpe,
                isCompleted: isCompleted,
                isWarmup: isWarmup,
                restSecondsActual: restSecondsActual,
            ),
            namespace: namespace,
        )

        if processImmediately {
            await processNow(reason: "enqueue_set")
        }
        return result
    }

    func enqueueStartWorkout(
        namespace: String,
        workoutInstanceId: String,
        startedAt: Date? = Date(),
    ) async -> SyncOutboxMutationResult {
        await prepareNamespace(namespace: namespace)
        let result = await outboxStore.enqueue(
            .startWorkout(workoutInstanceId: workoutInstanceId, startedAt: startedAt),
            namespace: namespace,
        )
        await processNow(reason: "enqueue_start")
        return result
    }

    func enqueueCompleteWorkout(
        namespace: String,
        workoutInstanceId: String,
        completedAt: Date? = Date(),
    ) async -> SyncOutboxMutationResult {
        await prepareNamespace(namespace: namespace)
        let result = await outboxStore.enqueue(
            .completeWorkout(workoutInstanceId: workoutInstanceId, completedAt: completedAt),
            namespace: namespace,
        )
        await processNow(reason: "enqueue_complete")
        return result
    }

    func enqueueAbandonWorkout(
        namespace: String,
        workoutInstanceId: String,
        abandonedAt: Date? = Date(),
    ) async -> SyncOutboxMutationResult {
        await prepareNamespace(namespace: namespace)
        let result = await outboxStore.enqueue(
            .abandonWorkout(workoutInstanceId: workoutInstanceId, abandonedAt: abandonedAt),
            namespace: namespace,
        )
        await processNow(reason: "enqueue_abandon")
        return result
    }

    func retryNow(namespace: String) async {
        await prepareNamespace(namespace: namespace)
        await processNow(reason: "manual_retry")
    }

    func diagnostics(namespace: String) async -> SyncDiagnosticsSnapshot {
        await outboxStore.diagnostics(namespace: namespace)
    }

    func exportSyncLog(namespace: String, limit: Int = 200) async -> String {
        await outboxStore.exportLogText(namespace: namespace, limit: limit)
    }

    func pendingCount(namespace: String) async -> Int {
        await outboxStore.pendingCount(namespace: namespace)
    }

    func hasPendingAbandon(namespace: String, workoutInstanceId: String) async -> Bool {
        await outboxStore.hasPendingAbandon(namespace: namespace, workoutInstanceId: workoutInstanceId)
    }

    func resolveSyncIndicator(namespace: String) async -> SyncStatusKind {
        let diagnostics = await outboxStore.diagnostics(namespace: namespace)
        if diagnostics.pendingCount > 0 {
            FFLog.info(
                "sync-indicator namespace=\(namespace) source=local_outbox_pending status=\(SyncStatusKind.savedLocally.rawValue) pendingCount=\(diagnostics.pendingCount) hasDelayedRetries=\(diagnostics.hasDelayedRetries) lastSyncError=\(diagnostics.lastSyncError ?? "-")",
            )
            return .savedLocally
        }
        if diagnostics.hasDelayedRetries {
            FFLog.info(
                "sync-indicator namespace=\(namespace) source=local_outbox_delayed status=\(SyncStatusKind.delayed.rawValue) pendingCount=\(diagnostics.pendingCount) hasDelayedRetries=\(diagnostics.hasDelayedRetries) lastSyncError=\(diagnostics.lastSyncError ?? "-")",
            )
            return .delayed
        }

        guard let athleteTrainingClient else {
            FFLog.info(
                "sync-indicator namespace=\(namespace) source=no_client status=\(SyncStatusKind.synced.rawValue) pendingCount=\(diagnostics.pendingCount) hasDelayedRetries=\(diagnostics.hasDelayedRetries)",
            )
            return .synced
        }

        let result = await athleteTrainingClient.syncStatus()
        switch result {
        case let .success(response):
            let resolvedStatus: SyncStatusKind
            if response.isDelayed == true {
                resolvedStatus = .delayed
            } else if response.hasPendingLocalChanges == true || (response.pendingOperations ?? 0) > 0 {
                resolvedStatus = .savedLocally
            } else {
                switch response.status {
                case .savedLocally:
                    resolvedStatus = .savedLocally
                case .delayed:
                    resolvedStatus = .delayed
                case .synced, .unknown, .none:
                    resolvedStatus = .synced
                }
            }
            FFLog.info(
                "sync-indicator namespace=\(namespace) source=remote_sync_status status=\(resolvedStatus.rawValue) remoteStatus=\(response.status?.rawValue ?? "nil") isDelayed=\(response.isDelayed?.description ?? "nil") hasPendingLocalChanges=\(response.hasPendingLocalChanges?.description ?? "nil") pendingOperations=\(response.pendingOperations.map(String.init) ?? "nil") lastSyncError=\(diagnostics.lastSyncError ?? "-")",
            )
            return resolvedStatus

        case .failure:
            let fallbackStatus: SyncStatusKind = diagnostics.pendingCount > 0 ? .savedLocally : .synced
            FFLog.info(
                "sync-indicator namespace=\(namespace) source=remote_sync_status_failed status=\(fallbackStatus.rawValue) pendingCount=\(diagnostics.pendingCount) hasDelayedRetries=\(diagnostics.hasDelayedRetries) lastSyncError=\(diagnostics.lastSyncError ?? "-")",
            )
            return fallbackStatus
        }
    }

    private func prepareNamespace(namespace: String) async {
        let normalized = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let shouldLogActivation = activeNamespace != normalized
        activeNamespace = normalized
        startIfNeeded()
        if shouldLogActivation {
            await outboxStore.appendSystemLog(namespace: normalized, message: "Sync namespace activated")
        }
    }

    private func processNow(reason: String) async {
        guard let namespace = activeNamespace else { return }

        let online = networkMonitor.currentStatus
        await outboxStore.appendSystemLog(
            namespace: namespace,
            message: "Sync trigger: \(reason)",
            error: nil,
        )

        await worker.process(
            namespace: namespace,
            athleteTrainingClient: athleteTrainingClient,
            isOnline: online,
        )
    }

    private func startIfNeeded() {
        guard !isStarted else { return }
        isStarted = true
        let monitor = networkMonitor
        let interval = periodicIntervalSeconds

        networkObserverTask = Task { [weak self] in
            guard let self else { return }
            for await isOnline in monitor.statusUpdates() {
                if Task.isCancelled { return }
                if isOnline {
                    await self.processNow(reason: "network_restored")
                }
            }
        }

        foregroundTask = Task { [weak self] in
            guard let self else { return }
            for await _ in NotificationCenter.default.notifications(named: UIApplication.willEnterForegroundNotification) {
                if Task.isCancelled { return }
                await self.processNow(reason: "foreground")
            }
        }

        periodicTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
                if Task.isCancelled { return }

                guard let namespace = await self.currentActiveNamespace() else { continue }
                let pendingCount = await self.outboxStore.pendingCount(namespace: namespace)
                if pendingCount > 0 {
                    await self.processNow(reason: "periodic")
                }
            }
        }
    }

    private func currentActiveNamespace() -> String? {
        activeNamespace
    }
}
