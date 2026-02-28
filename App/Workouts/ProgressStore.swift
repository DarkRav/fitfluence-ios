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

struct SessionSetState: Equatable, Sendable {
    var isCompleted: Bool
    var repsText: String
    var weightText: String
    var rpeText: String
}

struct SessionExerciseState: Equatable, Sendable {
    var exerciseId: String
    var sets: [SessionSetState]
    var isSkipped: Bool
}

struct WorkoutSessionState: Equatable, Sendable {
    var userSub: String
    var programId: String
    var workoutId: String
    var workoutTitle: String
    var currentExerciseIndex: Int
    var lastUpdated: Date
    var exercises: [SessionExerciseState]

    var completedSetsCount: Int {
        exercises.flatMap(\.sets).filter(\.isCompleted).count
    }

    var totalSetsCount: Int {
        exercises.flatMap(\.sets).count
    }
}

enum SessionUndoAction: Equatable, Sendable {
    case toggleComplete(exerciseId: String, setIndex: Int, previous: Bool)
    case updateReps(exerciseId: String, setIndex: Int, previous: String)
    case updateWeight(exerciseId: String, setIndex: Int, previous: String)
    case updateRPE(exerciseId: String, setIndex: Int, previous: String)
    case skipExercise(exerciseId: String, previous: Bool)
    case changeExerciseIndex(previous: Int)
}

actor WorkoutSessionManager {
    private let progressStore: WorkoutProgressStore
    private var undoStacks: [String: [SessionUndoAction]] = [:]

    init(progressStore: WorkoutProgressStore = LocalWorkoutProgressStore()) {
        self.progressStore = progressStore
    }

    func loadOrCreateSession(
        userSub: String,
        programId: String,
        workout: WorkoutDetailsModel,
    ) async -> WorkoutSessionState {
        let key = sessionKey(userSub: userSub, programId: programId, workoutId: workout.id)

        if let snapshot = await progressStore.load(userSub: userSub, programId: programId, workoutId: workout.id) {
            return sessionState(from: snapshot, workout: workout)
        }

        let session = WorkoutSessionState(
            userSub: userSub,
            programId: programId,
            workoutId: workout.id,
            workoutTitle: workout.title,
            currentExerciseIndex: 0,
            lastUpdated: Date(),
            exercises: workout.exercises.map { exercise in
                SessionExerciseState(
                    exerciseId: exercise.id,
                    sets: Array(
                        repeating: SessionSetState(
                            isCompleted: false,
                            repsText: "",
                            weightText: "",
                            rpeText: "",
                        ),
                        count: max(1, exercise.sets),
                    ),
                    isSkipped: false,
                )
            },
        )
        undoStacks[key] = []
        await autosave(session)
        return session
    }

    func toggleSetComplete(
        _ session: WorkoutSessionState,
        exerciseId: String,
        setIndex: Int,
    ) async -> WorkoutSessionState {
        await mutate(session, action: .toggleComplete(exerciseId: exerciseId, setIndex: setIndex, previous: false)) {
            target in
            guard let index = target.exercises.firstIndex(where: { $0.exerciseId == exerciseId }),
                  target.exercises[index].sets.indices.contains(setIndex)
            else { return }
            let previous = target.exercises[index].sets[setIndex].isCompleted
            recordUndo(
                for: target,
                action: .toggleComplete(exerciseId: exerciseId, setIndex: setIndex, previous: previous),
            )
            target.exercises[index].sets[setIndex].isCompleted.toggle()
        }
    }

    func updateSetReps(
        _ session: WorkoutSessionState,
        exerciseId: String,
        setIndex: Int,
        reps: String,
    ) async -> WorkoutSessionState {
        await mutate(session, action: .updateReps(exerciseId: exerciseId, setIndex: setIndex, previous: "")) { target in
            guard let index = target.exercises.firstIndex(where: { $0.exerciseId == exerciseId }),
                  target.exercises[index].sets.indices.contains(setIndex)
            else { return }
            let previous = target.exercises[index].sets[setIndex].repsText
            recordUndo(
                for: target,
                action: .updateReps(exerciseId: exerciseId, setIndex: setIndex, previous: previous),
            )
            target.exercises[index].sets[setIndex].repsText = reps
        }
    }

    func updateSetWeight(
        _ session: WorkoutSessionState,
        exerciseId: String,
        setIndex: Int,
        weight: String,
    ) async -> WorkoutSessionState {
        await mutate(session, action: .updateWeight(
            exerciseId: exerciseId,
            setIndex: setIndex,
            previous: "",
        )) { target in
            guard let index = target.exercises.firstIndex(where: { $0.exerciseId == exerciseId }),
                  target.exercises[index].sets.indices.contains(setIndex)
            else { return }
            let previous = target.exercises[index].sets[setIndex].weightText
            recordUndo(
                for: target,
                action: .updateWeight(exerciseId: exerciseId, setIndex: setIndex, previous: previous),
            )
            target.exercises[index].sets[setIndex].weightText = weight
        }
    }

    func updateSetRPE(
        _ session: WorkoutSessionState,
        exerciseId: String,
        setIndex: Int,
        rpe: String,
    ) async -> WorkoutSessionState {
        await mutate(session, action: .updateRPE(exerciseId: exerciseId, setIndex: setIndex, previous: "")) { target in
            guard let index = target.exercises.firstIndex(where: { $0.exerciseId == exerciseId }),
                  target.exercises[index].sets.indices.contains(setIndex)
            else { return }
            let previous = target.exercises[index].sets[setIndex].rpeText
            recordUndo(
                for: target,
                action: .updateRPE(exerciseId: exerciseId, setIndex: setIndex, previous: previous),
            )
            target.exercises[index].sets[setIndex].rpeText = rpe
        }
    }

    func skipExercise(_ session: WorkoutSessionState, exerciseId: String) async -> WorkoutSessionState {
        await mutate(session, action: .skipExercise(exerciseId: exerciseId, previous: false)) { target in
            guard let index = target.exercises.firstIndex(where: { $0.exerciseId == exerciseId }) else { return }
            let previous = target.exercises[index].isSkipped
            recordUndo(for: target, action: .skipExercise(exerciseId: exerciseId, previous: previous))
            target.exercises[index].isSkipped = true
        }
    }

    func moveExercise(_ session: WorkoutSessionState, to index: Int) async -> WorkoutSessionState {
        await mutate(session, action: .changeExerciseIndex(previous: session.currentExerciseIndex)) { target in
            let clamped = max(0, min(index, max(0, target.exercises.count - 1)))
            let previous = target.currentExerciseIndex
            recordUndo(for: target, action: .changeExerciseIndex(previous: previous))
            target.currentExerciseIndex = clamped
        }
    }

    func undo(_ session: WorkoutSessionState) async -> WorkoutSessionState {
        var next = session
        let key = sessionKey(userSub: next.userSub, programId: next.programId, workoutId: next.workoutId)
        guard var stack = undoStacks[key], let action = stack.popLast() else {
            return next
        }
        undoStacks[key] = stack

        applyUndo(action, to: &next)
        next.lastUpdated = Date()
        await autosave(next)
        return next
    }

    func finish(_ session: WorkoutSessionState) async {
        let snapshot = snapshot(from: session, isFinished: true)
        await progressStore.save(snapshot)
    }

    func latestActiveSession(userSub: String) async -> ActiveWorkoutSession? {
        await progressStore.latestActiveSession(userSub: userSub)
    }

    private func mutate(
        _ session: WorkoutSessionState,
        action _: SessionUndoAction,
        block: (inout WorkoutSessionState) -> Void,
    ) async -> WorkoutSessionState {
        var next = session
        block(&next)
        next.lastUpdated = Date()
        await autosave(next)
        return next
    }

    private func autosave(_ session: WorkoutSessionState) async {
        let snapshot = snapshot(from: session, isFinished: false)
        await progressStore.save(snapshot)
    }

    private func recordUndo(for session: WorkoutSessionState, action: SessionUndoAction) {
        let key = sessionKey(userSub: session.userSub, programId: session.programId, workoutId: session.workoutId)
        var stack = undoStacks[key] ?? []
        stack.append(action)
        undoStacks[key] = Array(stack.suffix(20))
    }

    private func applyUndo(_ action: SessionUndoAction, to session: inout WorkoutSessionState) {
        switch action {
        case let .toggleComplete(exerciseId, setIndex, previous):
            guard let exerciseIndex = session.exercises.firstIndex(where: { $0.exerciseId == exerciseId }),
                  session.exercises[exerciseIndex].sets.indices.contains(setIndex)
            else { return }
            session.exercises[exerciseIndex].sets[setIndex].isCompleted = previous
        case let .updateReps(exerciseId, setIndex, previous):
            guard let exerciseIndex = session.exercises.firstIndex(where: { $0.exerciseId == exerciseId }),
                  session.exercises[exerciseIndex].sets.indices.contains(setIndex)
            else { return }
            session.exercises[exerciseIndex].sets[setIndex].repsText = previous
        case let .updateWeight(exerciseId, setIndex, previous):
            guard let exerciseIndex = session.exercises.firstIndex(where: { $0.exerciseId == exerciseId }),
                  session.exercises[exerciseIndex].sets.indices.contains(setIndex)
            else { return }
            session.exercises[exerciseIndex].sets[setIndex].weightText = previous
        case let .updateRPE(exerciseId, setIndex, previous):
            guard let exerciseIndex = session.exercises.firstIndex(where: { $0.exerciseId == exerciseId }),
                  session.exercises[exerciseIndex].sets.indices.contains(setIndex)
            else { return }
            session.exercises[exerciseIndex].sets[setIndex].rpeText = previous
        case let .skipExercise(exerciseId, previous):
            guard let exerciseIndex = session.exercises.firstIndex(where: { $0.exerciseId == exerciseId }) else {
                return
            }
            session.exercises[exerciseIndex].isSkipped = previous
        case let .changeExerciseIndex(previous):
            session.currentExerciseIndex = previous
        }
    }

    private func sessionState(
        from snapshot: WorkoutProgressSnapshot,
        workout: WorkoutDetailsModel,
    ) -> WorkoutSessionState {
        let exercises = workout.exercises.map { exercise in
            let stored = snapshot.exercises[exercise.id]
            let sets = Array(0 ..< max(1, exercise.sets)).map { index in
                if let storedSet = stored?.sets[safe: index] {
                    return SessionSetState(
                        isCompleted: storedSet.isCompleted,
                        repsText: storedSet.repsText,
                        weightText: storedSet.weightText,
                        rpeText: storedSet.rpeText,
                    )
                }
                return SessionSetState(isCompleted: false, repsText: "", weightText: "", rpeText: "")
            }
            return SessionExerciseState(exerciseId: exercise.id, sets: sets, isSkipped: false)
        }
        return WorkoutSessionState(
            userSub: snapshot.userSub,
            programId: snapshot.programId,
            workoutId: snapshot.workoutId,
            workoutTitle: workout.title,
            currentExerciseIndex: max(0, min(snapshot.currentExerciseIndex ?? 0, max(0, exercises.count - 1))),
            lastUpdated: snapshot.lastUpdated,
            exercises: exercises,
        )
    }

    private func snapshot(from session: WorkoutSessionState, isFinished: Bool) -> WorkoutProgressSnapshot {
        let exercises = Dictionary(uniqueKeysWithValues: session.exercises.map { exercise in
            let sets = exercise.sets.map {
                StoredSetProgress(
                    isCompleted: $0.isCompleted,
                    repsText: $0.repsText,
                    weightText: $0.weightText,
                    rpeText: $0.rpeText,
                )
            }
            return (exercise.exerciseId, StoredExerciseProgress(sets: sets))
        })
        return WorkoutProgressSnapshot(
            userSub: session.userSub,
            programId: session.programId,
            workoutId: session.workoutId,
            currentExerciseIndex: session.currentExerciseIndex,
            isFinished: isFinished,
            lastUpdated: session.lastUpdated,
            exercises: exercises,
        )
    }

    private func sessionKey(userSub: String, programId: String, workoutId: String) -> String {
        "\(userSub)::\(programId)::\(workoutId)"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
