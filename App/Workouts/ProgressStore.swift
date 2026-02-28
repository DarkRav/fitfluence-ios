import Foundation

enum WorkoutProgressStatus: String, Equatable, Sendable {
    case notStarted
    case inProgress
    case completed

    var title: String {
        switch self {
        case .notStarted:
            "Не начата"
        case .inProgress:
            "В процессе"
        case .completed:
            "Завершена"
        }
    }
}

struct StoredSetProgress: Codable, Equatable, Sendable {
    var isCompleted: Bool
    var repsText: String
    var weightText: String
    var rpeText: String
}

struct StoredExerciseProgress: Codable, Equatable, Sendable {
    var sets: [StoredSetProgress]
}

struct WorkoutProgressSnapshot: Codable, Equatable, Sendable {
    let userSub: String
    let programId: String
    let workoutId: String
    var currentExerciseIndex: Int?
    var isFinished: Bool
    var lastUpdated: Date
    var exercises: [String: StoredExerciseProgress]

    var status: WorkoutProgressStatus {
        if isFinished {
            return .completed
        }

        let allSets = exercises.values.flatMap(\.sets)
        let hasCompletedSet = allSets.contains(where: \.isCompleted)
        let hasEnteredValues = allSets.contains { set in
            !set.repsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !set.weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !set.rpeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if hasCompletedSet || hasEnteredValues {
            return .inProgress
        }

        return .notStarted
    }
}

struct ActiveWorkoutSession: Equatable, Sendable {
    let userSub: String
    let programId: String
    let workoutId: String
    let status: WorkoutProgressStatus
    let currentExerciseIndex: Int?
    let lastUpdated: Date
}

protocol WorkoutProgressStore: Sendable {
    func load(userSub: String, programId: String, workoutId: String) async -> WorkoutProgressSnapshot?
    func save(_ snapshot: WorkoutProgressSnapshot) async
    func status(userSub: String, programId: String, workoutId: String) async -> WorkoutProgressStatus
    func statuses(userSub: String, programId: String, workoutIds: [String]) async -> [String: WorkoutProgressStatus]
    func latestActiveSession(userSub: String) async -> ActiveWorkoutSession?
}

actor LocalWorkoutProgressStore: WorkoutProgressStore {
    private let defaults: UserDefaults
    private let keyPrefix = "fitfluence.workout.progress"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(userSub: String, programId: String, workoutId: String) async -> WorkoutProgressSnapshot? {
        let key = storageKey(userSub: userSub, programId: programId, workoutId: workoutId)
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WorkoutProgressSnapshot.self, from: data)
    }

    func save(_ snapshot: WorkoutProgressSnapshot) async {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let key = storageKey(userSub: snapshot.userSub, programId: snapshot.programId, workoutId: snapshot.workoutId)
        defaults.set(data, forKey: key)
    }

    func status(userSub: String, programId: String, workoutId: String) async -> WorkoutProgressStatus {
        guard let snapshot = await load(userSub: userSub, programId: programId, workoutId: workoutId) else {
            return .notStarted
        }
        return snapshot.status
    }

    func statuses(userSub: String, programId: String, workoutIds: [String]) async -> [String: WorkoutProgressStatus] {
        var result: [String: WorkoutProgressStatus] = [:]
        for workoutID in workoutIds {
            result[workoutID] = await status(userSub: userSub, programId: programId, workoutId: workoutID)
        }
        return result
    }

    func latestActiveSession(userSub: String) async -> ActiveWorkoutSession? {
        let snapshots = defaults.dictionaryRepresentation()
            .keys
            .filter { $0.hasPrefix("\(keyPrefix).\(userSub).") }
            .compactMap { key -> WorkoutProgressSnapshot? in
                guard let data = defaults.data(forKey: key) else { return nil }
                return try? JSONDecoder().decode(WorkoutProgressSnapshot.self, from: data)
            }
            .filter { $0.status == .inProgress || ($0.status == .notStarted && !$0.isFinished) }
            .sorted {
                if $0.status != $1.status {
                    return $0.status == .inProgress
                }
                return $0.lastUpdated > $1.lastUpdated
            }

        guard let snapshot = snapshots.first else { return nil }
        return ActiveWorkoutSession(
            userSub: snapshot.userSub,
            programId: snapshot.programId,
            workoutId: snapshot.workoutId,
            status: snapshot.status,
            currentExerciseIndex: snapshot.currentExerciseIndex,
            lastUpdated: snapshot.lastUpdated,
        )
    }

    private func storageKey(userSub: String, programId: String, workoutId: String) -> String {
        "\(keyPrefix).\(userSub).\(programId).\(workoutId)"
    }
}
