import Foundation

enum WorkoutLifecycleState: String, Equatable, Sendable {
    case draft
    case inProgress
    case completed
    case cancelled
}

struct WorkoutRouteTarget: Equatable, Sendable {
    let programId: String
    let workoutId: String
    let title: String
}

struct ActiveEnrollmentState: Equatable, Sendable {
    let programId: String
    let programTitle: String
    let completedSessions: Int
    let totalSessions: Int
    let resumeWorkout: WorkoutRouteTarget?
    let todayWorkout: WorkoutRouteTarget?
    let nextWorkoutToStart: WorkoutRouteTarget?

    var preferredLaunchWorkout: WorkoutRouteTarget? {
        resumeWorkout ?? todayWorkout ?? nextWorkoutToStart
    }

    var isCompleted: Bool {
        totalSessions > 0 && completedSessions >= totalSessions
    }

    var totalSessionsForProgress: Int {
        max(totalSessions, completedSessions, 1)
    }
}

enum WorkoutDomainRules {
    static func progressStatus(
        isFinished: Bool,
        exercises: [String: StoredExerciseProgress],
    ) -> WorkoutProgressStatus {
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

    static func canTransition(from: WorkoutLifecycleState, to: WorkoutLifecycleState) -> Bool {
        if from == to {
            return true
        }

        switch (from, to) {
        case (.draft, .inProgress), (.draft, .completed), (.draft, .cancelled):
            return true
        case (.inProgress, .completed), (.inProgress, .cancelled):
            return true
        case (.completed, _), (.cancelled, _):
            return false
        default:
            return false
        }
    }

    static func canLaunchSession(
        session: ActiveWorkoutSession,
        isOnline: Bool,
        hasCachedWorkoutDetails: Bool,
        hasSnapshotDetails: Bool,
    ) -> Bool {
        if session.source == .program, UUID(uuidString: session.programId) != nil, isOnline {
            return true
        }

        if hasCachedWorkoutDetails || hasSnapshotDetails {
            return true
        }

        return false
    }

    static func resolveActiveEnrollment(
        _ progress: ActiveEnrollmentProgressResponse,
        fallbackProgramId: String? = nil,
        fallbackProgramTitle: String? = nil,
    ) -> ActiveEnrollmentState? {
        guard let programId = normalized(progress.programId) ?? normalized(fallbackProgramId) else {
            return nil
        }

        let currentTarget = makeTarget(
            programId: programId,
            workoutId: progress.currentWorkoutId,
            title: progress.currentWorkoutTitle,
            fallbackTitle: "Текущая тренировка",
        )
        let nextTarget = makeTarget(
            programId: programId,
            workoutId: progress.nextWorkoutId,
            title: progress.nextWorkoutTitle,
            fallbackTitle: "Следующая тренировка",
        )
        let todayTarget = makeTarget(
            programId: programId,
            workoutId: progress.todayWorkoutId,
            title: progress.todayWorkoutTitle,
            fallbackTitle: "Тренировка на сегодня",
        )

        let resumeTarget: WorkoutRouteTarget? = {
            if progress.currentWorkoutStatus == .inProgress, let currentTarget {
                return currentTarget
            }
            if progress.nextWorkoutStatus == .inProgress, let nextTarget {
                return nextTarget
            }
            return nil
        }()
        let todayToStart: WorkoutRouteTarget? = {
            guard let todayTarget else { return nil }
            guard progress.todayWorkoutStatus != .completed,
                  progress.todayWorkoutStatus != .missed,
                  progress.todayWorkoutStatus != .abandoned
            else {
                return nil
            }
            guard todayTarget.workoutId != resumeTarget?.workoutId else { return nil }
            return todayTarget
        }()

        let nextToStart: WorkoutRouteTarget? = {
            guard let nextTarget else { return nil }
            guard nextTarget.workoutId != resumeTarget?.workoutId,
                  nextTarget.workoutId != todayToStart?.workoutId
            else {
                return nil
            }
            return nextTarget
        }()

        let completedSessions = max(0, progress.completedSessions ?? 0)
        let totalSessions = max(completedSessions, max(0, progress.totalSessions ?? 0))
        return ActiveEnrollmentState(
            programId: programId,
            programTitle: normalized(progress.programTitle) ?? normalized(fallbackProgramTitle) ?? "Активная программа",
            completedSessions: completedSessions,
            totalSessions: totalSessions,
            resumeWorkout: resumeTarget,
            todayWorkout: todayToStart,
            nextWorkoutToStart: nextToStart,
        )
    }

    static func remoteInProgressSession(
        userSub: String,
        progress: ActiveEnrollmentProgressResponse,
        updatedAt: Date = Date(),
    ) -> ActiveWorkoutSession? {
        guard let resumeTarget = resolveActiveEnrollment(progress)?.resumeWorkout else {
            return nil
        }
        return ActiveWorkoutSession(
            userSub: userSub,
            programId: resumeTarget.programId,
            workoutId: resumeTarget.workoutId,
            source: .program,
            status: .inProgress,
            currentExerciseIndex: nil,
            lastUpdated: updatedAt,
        )
    }

    static func nextWorkoutTarget(
        from progress: ActiveEnrollmentProgressResponse,
        fallbackProgramId: String? = nil,
        excludingWorkoutId: String? = nil,
    ) -> WorkoutRouteTarget? {
        guard let target = resolveActiveEnrollment(progress, fallbackProgramId: fallbackProgramId)?.nextWorkoutToStart else {
            return nil
        }
        guard target.workoutId != normalized(excludingWorkoutId) else {
            return nil
        }
        return target
    }

    static func resolveNextWorkout(
        workouts: [WorkoutSummary],
        statuses: [String: WorkoutProgressStatus],
        activeSessionWorkoutId: String?,
    ) -> WorkoutSummary? {
        guard !workouts.isEmpty else { return nil }

        if let activeSessionWorkoutId,
           let inProgress = workouts.first(where: { $0.id == activeSessionWorkoutId })
        {
            return inProgress
        }

        if let planned = workouts.first(where: { (statuses[$0.id] ?? .notStarted) != .completed }) {
            return planned
        }

        return workouts.first
    }

    private static func makeTarget(
        programId: String,
        workoutId: String?,
        title: String?,
        fallbackTitle: String,
    ) -> WorkoutRouteTarget? {
        guard let workoutId = normalized(workoutId) else { return nil }
        return WorkoutRouteTarget(
            programId: programId,
            workoutId: workoutId,
            title: normalized(title) ?? fallbackTitle,
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

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
    var isWarmup: Bool

    init(
        isCompleted: Bool,
        repsText: String,
        weightText: String,
        rpeText: String,
        isWarmup: Bool = false,
    ) {
        self.isCompleted = isCompleted
        self.repsText = repsText
        self.weightText = weightText
        self.rpeText = rpeText
        self.isWarmup = isWarmup
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        repsText = try container.decode(String.self, forKey: .repsText)
        weightText = try container.decode(String.self, forKey: .weightText)
        rpeText = try container.decode(String.self, forKey: .rpeText)
        isWarmup = try container.decodeIfPresent(Bool.self, forKey: .isWarmup) ?? false
    }
}

struct StoredExerciseProgress: Codable, Equatable, Sendable {
    var sets: [StoredSetProgress]
}

struct WorkoutProgressSnapshot: Codable, Equatable, Sendable {
    let userSub: String
    let programId: String
    let workoutId: String
    var currentExerciseIndex: Int?
    var startedAt: Date? = nil
    var source: WorkoutSource? = nil
    var workoutDetails: WorkoutDetailsModel? = nil
    var hasLocalOnlyStructuralChanges: Bool
    var isFinished: Bool
    var lastUpdated: Date
    var exercises: [String: StoredExerciseProgress]

    init(
        userSub: String,
        programId: String,
        workoutId: String,
        currentExerciseIndex: Int?,
        startedAt: Date? = nil,
        source: WorkoutSource? = nil,
        workoutDetails: WorkoutDetailsModel? = nil,
        hasLocalOnlyStructuralChanges: Bool = false,
        isFinished: Bool,
        lastUpdated: Date,
        exercises: [String: StoredExerciseProgress],
    ) {
        self.userSub = userSub
        self.programId = programId
        self.workoutId = workoutId
        self.currentExerciseIndex = currentExerciseIndex
        self.startedAt = startedAt
        self.source = source
        self.workoutDetails = workoutDetails
        self.hasLocalOnlyStructuralChanges = hasLocalOnlyStructuralChanges
        self.isFinished = isFinished
        self.lastUpdated = lastUpdated
        self.exercises = exercises
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userSub = try container.decode(String.self, forKey: .userSub)
        programId = try container.decode(String.self, forKey: .programId)
        workoutId = try container.decode(String.self, forKey: .workoutId)
        currentExerciseIndex = try container.decodeIfPresent(Int.self, forKey: .currentExerciseIndex)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        source = try container.decodeIfPresent(WorkoutSource.self, forKey: .source)
        workoutDetails = try container.decodeIfPresent(WorkoutDetailsModel.self, forKey: .workoutDetails)
        hasLocalOnlyStructuralChanges = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasLocalOnlyStructuralChanges,
        ) ?? false
        isFinished = try container.decode(Bool.self, forKey: .isFinished)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        exercises = try container.decode([String: StoredExerciseProgress].self, forKey: .exercises)
    }

    var status: WorkoutProgressStatus {
        WorkoutDomainRules.progressStatus(
            isFinished: isFinished,
            exercises: exercises,
        )
    }
}

struct ActiveWorkoutSession: Equatable, Sendable {
    let userSub: String
    let programId: String
    let workoutId: String
    let source: WorkoutSource
    let status: WorkoutProgressStatus
    let currentExerciseIndex: Int?
    let lastUpdated: Date
}

protocol WorkoutProgressStore: Sendable {
    func load(userSub: String, programId: String, workoutId: String) async -> WorkoutProgressSnapshot?
    func save(_ snapshot: WorkoutProgressSnapshot) async
    func remove(userSub: String, programId: String, workoutId: String) async
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

    func remove(userSub: String, programId: String, workoutId: String) async {
        let key = storageKey(userSub: userSub, programId: programId, workoutId: workoutId)
        defaults.removeObject(forKey: key)
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
            .filter { !$0.isFinished }
            .sorted {
                let lhsPriority = activeSessionSortPriority(for: $0.status)
                let rhsPriority = activeSessionSortPriority(for: $1.status)
                if lhsPriority != rhsPriority {
                    return lhsPriority > rhsPriority
                }
                return $0.lastUpdated > $1.lastUpdated
            }

        guard let snapshot = snapshots.first else { return nil }
        return ActiveWorkoutSession(
            userSub: snapshot.userSub,
            programId: snapshot.programId,
            workoutId: snapshot.workoutId,
            source: snapshot.source ?? .program,
            status: snapshot.status,
            currentExerciseIndex: snapshot.currentExerciseIndex,
            lastUpdated: snapshot.lastUpdated,
        )
    }

    private func activeSessionSortPriority(for status: WorkoutProgressStatus) -> Int {
        switch status {
        case .inProgress:
            return 2
        case .notStarted:
            return 1
        case .completed:
            return 0
        }
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
    var isWarmup: Bool
}

struct SessionSetDefaults: Equatable, Sendable {
    var repsText: String?
    var weightText: String?
    var rpeText: String?
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
    var workoutDetails: WorkoutDetailsModel
    var source: WorkoutSource
    var startedAt: Date
    var currentExerciseIndex: Int
    var lastUpdated: Date
    var exercises: [SessionExerciseState]
    var hasLocalOnlyStructuralChanges: Bool

    var completedSetsCount: Int {
        exercises.flatMap(\.sets).filter(\.isCompleted).count
    }

    var totalSetsCount: Int {
        exercises.flatMap(\.sets).count
    }
}

enum WorkoutSessionLoadResult: Equatable, Sendable {
    case session(WorkoutSessionState)
    case blockedByActiveSession(ActiveWorkoutSession)
}

enum SessionUndoAction: Equatable, Sendable {
    case toggleComplete(exerciseId: String, setIndex: Int, previous: Bool)
    case updateReps(exerciseId: String, setIndex: Int, previous: String)
    case updateWeight(exerciseId: String, setIndex: Int, previous: String)
    case updateRPE(exerciseId: String, setIndex: Int, previous: String)
    case toggleWarmup(exerciseId: String, setIndex: Int, previous: Bool)
    case skipExercise(exerciseId: String, previous: Bool)
    case changeExerciseIndex(previous: Int)
    case addSet(exerciseId: String, setIndex: Int, previousLocalOnlyStructuralChanges: Bool)
    case removeSet(
        exerciseId: String,
        setIndex: Int,
        removedSet: SessionSetState,
        previousLocalOnlyStructuralChanges: Bool
    )
    case addExercise(
        exerciseIndex: Int,
        previousCurrentExerciseIndex: Int,
        previousLocalOnlyStructuralChanges: Bool
    )
    case replaceExercise(
        exerciseIndex: Int,
        previousExercise: WorkoutExercise,
        previousState: SessionExerciseState,
        previousLocalOnlyStructuralChanges: Bool
    )
    case reorderExercises(
        previousExercises: [WorkoutExercise],
        previousStates: [SessionExerciseState],
        previousCurrentExerciseIndex: Int,
        previousLocalOnlyStructuralChanges: Bool
    )
}

actor WorkoutSessionManager {
    private let progressStore: WorkoutProgressStore
    private let trainingStore: TrainingStore
    private var undoStacks: [String: [SessionUndoAction]] = [:]

    init(
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
        trainingStore: TrainingStore = LocalTrainingStore(),
    ) {
        self.progressStore = progressStore
        self.trainingStore = trainingStore
    }

    func loadOrCreateSession(
        userSub: String,
        programId: String,
        workout: WorkoutDetailsModel,
        source: WorkoutSource = .program,
    ) async -> WorkoutSessionLoadResult {
        let key = sessionKey(userSub: userSub, programId: programId, workoutId: workout.id)

        if let activeSession = await progressStore.latestActiveSession(userSub: userSub),
           activeSession.programId != programId || activeSession.workoutId != workout.id
        {
            return .blockedByActiveSession(activeSession)
        }

        if let snapshot = await progressStore.load(userSub: userSub, programId: programId, workoutId: workout.id) {
            return .session(sessionState(from: snapshot, workout: workout))
        }

        let session = WorkoutSessionState(
            userSub: userSub,
            programId: programId,
            workoutId: workout.id,
            workoutTitle: workout.title,
            workoutDetails: workout,
            source: source,
            startedAt: Date(),
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
                            isWarmup: false,
                        ),
                        count: max(1, exercise.sets),
                    ),
                    isSkipped: false,
                )
            },
            hasLocalOnlyStructuralChanges: false,
        )
        undoStacks[key] = []
        await autosave(session)
        return .session(session)
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

    func toggleSetWarmup(
        _ session: WorkoutSessionState,
        exerciseId: String,
        setIndex: Int,
    ) async -> WorkoutSessionState {
        await mutate(session, action: .toggleWarmup(exerciseId: exerciseId, setIndex: setIndex, previous: false)) {
            target in
            guard let index = target.exercises.firstIndex(where: { $0.exerciseId == exerciseId }),
                  target.exercises[index].sets.indices.contains(setIndex)
            else { return }
            let previous = target.exercises[index].sets[setIndex].isWarmup
            recordUndo(
                for: target,
                action: .toggleWarmup(exerciseId: exerciseId, setIndex: setIndex, previous: previous),
            )
            target.exercises[index].sets[setIndex].isWarmup.toggle()
        }
    }

    func addSet(
        _ session: WorkoutSessionState,
        exerciseId: String,
        duplicateLast: Bool,
    ) async -> WorkoutSessionState {
        await mutate(session, action: .addSet(exerciseId: exerciseId, setIndex: 0, previousLocalOnlyStructuralChanges: false)) {
            target in
            guard let exerciseIndex = target.exercises.firstIndex(where: { $0.exerciseId == exerciseId }),
                  let workoutExerciseIndex = target.workoutDetails.exercises.firstIndex(where: { $0.id == exerciseId })
            else { return }

            let newSet = duplicateLast
                ? {
                    let source = target.exercises[exerciseIndex].sets.last ?? SessionSetState(
                        isCompleted: false,
                        repsText: "",
                        weightText: "",
                        rpeText: "",
                        isWarmup: false,
                    )
                    return SessionSetState(
                        isCompleted: false,
                        repsText: source.repsText,
                        weightText: source.weightText,
                        rpeText: source.rpeText,
                        isWarmup: source.isWarmup,
                    )
                }()
                : SessionSetState(
                    isCompleted: false,
                    repsText: "",
                    weightText: "",
                    rpeText: "",
                    isWarmup: false,
                )

            let insertIndex = target.exercises[exerciseIndex].sets.count
            let previousLocalOnlyFlag = target.hasLocalOnlyStructuralChanges
            recordUndo(
                for: target,
                action: .addSet(
                    exerciseId: exerciseId,
                    setIndex: insertIndex,
                    previousLocalOnlyStructuralChanges: previousLocalOnlyFlag,
                ),
            )
            target.exercises[exerciseIndex].sets.append(newSet)
            var updatedExercises = target.workoutDetails.exercises
            updatedExercises[workoutExerciseIndex] = updatedExercises[workoutExerciseIndex]
                .updatingSetCount(target.exercises[exerciseIndex].sets.count)
            target.workoutDetails = target.workoutDetails.updatingExercises(updatedExercises)
            target.hasLocalOnlyStructuralChanges = true
        }
    }

    func removeSet(
        _ session: WorkoutSessionState,
        exerciseId: String,
        setIndex: Int,
    ) async -> WorkoutSessionState {
        await mutate(
            session,
            action: .removeSet(
                exerciseId: exerciseId,
                setIndex: setIndex,
                removedSet: SessionSetState(isCompleted: false, repsText: "", weightText: "", rpeText: "", isWarmup: false),
                previousLocalOnlyStructuralChanges: false,
            ),
        ) { target in
            guard let exerciseIndex = target.exercises.firstIndex(where: { $0.exerciseId == exerciseId }),
                  target.exercises[exerciseIndex].sets.indices.contains(setIndex),
                  target.exercises[exerciseIndex].sets.count > 1,
                  let workoutExerciseIndex = target.workoutDetails.exercises.firstIndex(where: { $0.id == exerciseId })
            else { return }

            let removedSet = target.exercises[exerciseIndex].sets.remove(at: setIndex)
            let previousLocalOnlyFlag = target.hasLocalOnlyStructuralChanges
            recordUndo(
                for: target,
                action: .removeSet(
                    exerciseId: exerciseId,
                    setIndex: setIndex,
                    removedSet: removedSet,
                    previousLocalOnlyStructuralChanges: previousLocalOnlyFlag,
                ),
            )
            var updatedExercises = target.workoutDetails.exercises
            updatedExercises[workoutExerciseIndex] = updatedExercises[workoutExerciseIndex]
                .updatingSetCount(target.exercises[exerciseIndex].sets.count)
            target.workoutDetails = target.workoutDetails.updatingExercises(updatedExercises)
            target.hasLocalOnlyStructuralChanges = true
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

    func addExercise(
        _ session: WorkoutSessionState,
        exercise: WorkoutExercise,
        afterExerciseId: String?,
    ) async -> WorkoutSessionState {
        await mutate(
            session,
            action: .addExercise(
                exerciseIndex: 0,
                previousCurrentExerciseIndex: session.currentExerciseIndex,
                previousLocalOnlyStructuralChanges: false,
            ),
        ) { target in
            let previousCurrentExerciseIndex = target.currentExerciseIndex
            let previousLocalOnlyFlag = target.hasLocalOnlyStructuralChanges
            let baseIndex = afterExerciseId.flatMap { id in
                target.workoutDetails.exercises.firstIndex(where: { $0.id == id })
            } ?? (target.workoutDetails.exercises.count - 1)
            let insertIndex = min(target.workoutDetails.exercises.count, max(0, baseIndex + 1))

            recordUndo(
                for: target,
                action: .addExercise(
                    exerciseIndex: insertIndex,
                    previousCurrentExerciseIndex: previousCurrentExerciseIndex,
                    previousLocalOnlyStructuralChanges: previousLocalOnlyFlag,
                ),
            )

            var updatedExercises = target.workoutDetails.exercises
            updatedExercises.insert(exercise, at: insertIndex)
            target.workoutDetails = target.workoutDetails.updatingExercises(updatedExercises.normalizedWorkoutOrder())
            target.exercises.insert(
                SessionExerciseState(
                    exerciseId: exercise.id,
                    sets: Array(
                        repeating: SessionSetState(
                            isCompleted: false,
                            repsText: "",
                            weightText: "",
                            rpeText: "",
                            isWarmup: false,
                        ),
                        count: max(1, exercise.sets),
                    ),
                    isSkipped: false,
                ),
                at: insertIndex,
            )
            target.currentExerciseIndex = insertIndex
            target.hasLocalOnlyStructuralChanges = true
        }
    }

    func replaceExercise(
        _ session: WorkoutSessionState,
        exerciseId: String,
        with exercise: WorkoutExercise,
    ) async -> WorkoutSessionState {
        await mutate(
            session,
            action: .replaceExercise(
                exerciseIndex: 0,
                previousExercise: exercise,
                previousState: SessionExerciseState(exerciseId: exerciseId, sets: [], isSkipped: false),
                previousLocalOnlyStructuralChanges: false,
            ),
        ) { target in
            guard let exerciseIndex = target.exercises.firstIndex(where: { $0.exerciseId == exerciseId }),
                  target.workoutDetails.exercises.indices.contains(exerciseIndex)
            else {
                return
            }

            let previousExercise = target.workoutDetails.exercises[exerciseIndex]
            let previousState = target.exercises[exerciseIndex]
            let previousLocalOnlyFlag = target.hasLocalOnlyStructuralChanges
            recordUndo(
                for: target,
                action: .replaceExercise(
                    exerciseIndex: exerciseIndex,
                    previousExercise: previousExercise,
                    previousState: previousState,
                    previousLocalOnlyStructuralChanges: previousLocalOnlyFlag,
                ),
            )

            var updatedExercises = target.workoutDetails.exercises
            updatedExercises[exerciseIndex] = exercise.updatingOrderIndex(exerciseIndex)
            target.workoutDetails = target.workoutDetails.updatingExercises(updatedExercises)
            target.exercises[exerciseIndex] = SessionExerciseState(
                exerciseId: exercise.id,
                sets: Array(
                    repeating: SessionSetState(
                        isCompleted: false,
                        repsText: "",
                        weightText: "",
                        rpeText: "",
                        isWarmup: false,
                    ),
                    count: max(1, exercise.sets),
                ),
                isSkipped: false,
            )
            target.hasLocalOnlyStructuralChanges = true
        }
    }

    func reorderExercises(
        _ session: WorkoutSessionState,
        sourceExerciseId: String,
        targetExerciseId: String,
    ) async -> WorkoutSessionState {
        await mutate(
            session,
            action: .reorderExercises(
                previousExercises: session.workoutDetails.exercises,
                previousStates: session.exercises,
                previousCurrentExerciseIndex: session.currentExerciseIndex,
                previousLocalOnlyStructuralChanges: session.hasLocalOnlyStructuralChanges,
            ),
        ) { target in
            guard let sourceIndex = target.workoutDetails.exercises.firstIndex(where: { $0.id == sourceExerciseId }),
                  let targetIndex = target.workoutDetails.exercises.firstIndex(where: { $0.id == targetExerciseId }),
                  sourceIndex != targetIndex
            else {
                return
            }

            let previousExercises = target.workoutDetails.exercises
            let previousStates = target.exercises
            let previousCurrentExerciseIndex = target.currentExerciseIndex
            let previousLocalOnlyFlag = target.hasLocalOnlyStructuralChanges
            recordUndo(
                for: target,
                action: .reorderExercises(
                    previousExercises: previousExercises,
                    previousStates: previousStates,
                    previousCurrentExerciseIndex: previousCurrentExerciseIndex,
                    previousLocalOnlyStructuralChanges: previousLocalOnlyFlag,
                ),
            )

            var updatedExercises = target.workoutDetails.exercises
            let movedExercise = updatedExercises.remove(at: sourceIndex)
            updatedExercises.insert(movedExercise, at: targetIndex)
            target.workoutDetails = target.workoutDetails.updatingExercises(updatedExercises.normalizedWorkoutOrder())

            var updatedStates = target.exercises
            let movedState = updatedStates.remove(at: sourceIndex)
            updatedStates.insert(movedState, at: targetIndex)
            target.exercises = updatedStates

            if let currentExerciseId = previousExercises[safe: previousCurrentExerciseIndex]?.id,
               let newCurrentIndex = target.workoutDetails.exercises.firstIndex(where: { $0.id == currentExerciseId }) {
                target.currentExerciseIndex = newCurrentIndex
            }

            target.hasLocalOnlyStructuralChanges = true
        }
    }

    func applySetDefaults(
        _ session: WorkoutSessionState,
        exerciseId: String,
        defaults: [SessionSetDefaults],
        overwriteExisting: Bool = false,
    ) async -> WorkoutSessionState {
        await mutate(session, action: .changeExerciseIndex(previous: session.currentExerciseIndex)) { target in
            guard let exerciseIndex = target.exercises.firstIndex(where: { $0.exerciseId == exerciseId }) else {
                return
            }

            for (setIndex, defaultSet) in defaults.enumerated() {
                guard target.exercises[exerciseIndex].sets.indices.contains(setIndex) else {
                    continue
                }

                if let reps = defaultSet.repsText {
                    let existing = target.exercises[exerciseIndex].sets[setIndex].repsText
                    if overwriteExisting || existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        target.exercises[exerciseIndex].sets[setIndex].repsText = reps
                    }
                }

                if let weight = defaultSet.weightText {
                    let existing = target.exercises[exerciseIndex].sets[setIndex].weightText
                    if overwriteExisting || existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        target.exercises[exerciseIndex].sets[setIndex].weightText = weight
                    }
                }

                if let rpe = defaultSet.rpeText {
                    let existing = target.exercises[exerciseIndex].sets[setIndex].rpeText
                    if overwriteExisting || existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        target.exercises[exerciseIndex].sets[setIndex].rpeText = rpe
                    }
                }
            }
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

    func replaceSession(_ session: WorkoutSessionState) async -> WorkoutSessionState {
        await autosave(session)
        return session
    }

    func finish(_ session: WorkoutSessionState) async {
        let finishedAt = Date()
        let completedSets = session.exercises.flatMap(\.sets).filter(\.isCompleted)
        let volume = completedSets.reduce(0.0) { partial, set in
            let reps = Double(set.repsText) ?? 0
            let weight = Double(set.weightText) ?? 0
            return partial + reps * weight
        }
        let rpeValues = completedSets.compactMap { Int($0.rpeText) }
        let averageRPE = rpeValues.isEmpty ? nil : Int(round(Double(rpeValues.reduce(0, +)) / Double(rpeValues.count)))

        let record = CompletedWorkoutRecord(
            id: UUID().uuidString,
            userSub: session.userSub,
            programId: session.programId,
            workoutId: session.workoutId,
            workoutTitle: session.workoutTitle,
            source: session.source,
            startedAt: session.startedAt,
            finishedAt: finishedAt,
            durationSeconds: max(0, Int(finishedAt.timeIntervalSince(session.startedAt))),
            completedSets: session.completedSetsCount,
            totalSets: session.totalSetsCount,
            volume: volume,
            workoutDetails: session.workoutDetails,
            notes: nil,
            overallRPE: averageRPE,
        )

        let snapshot = snapshot(from: session, isFinished: true)
        await progressStore.save(snapshot)
        await trainingStore.appendHistory(record)
    }

    func latestActiveSession(userSub: String) async -> ActiveWorkoutSession? {
        await progressStore.latestActiveSession(userSub: userSub)
    }

    func recoverWorkoutDetails(userSub: String, programId: String, workoutId: String) async -> WorkoutDetailsModel? {
        await progressStore.load(userSub: userSub, programId: programId, workoutId: workoutId)?.workoutDetails
    }

    func lastCompletedWorkout(userSub: String) async -> CompletedWorkoutRecord? {
        await trainingStore.lastCompleted(userSub: userSub)
    }

    func weeklySummary(userSub: String, weekStart: Date) async -> WeeklyTrainingSummary {
        await trainingStore.weeklySummary(userSub: userSub, weekStart: weekStart)
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
        case let .toggleWarmup(exerciseId, setIndex, previous):
            guard let exerciseIndex = session.exercises.firstIndex(where: { $0.exerciseId == exerciseId }),
                  session.exercises[exerciseIndex].sets.indices.contains(setIndex)
            else { return }
            session.exercises[exerciseIndex].sets[setIndex].isWarmup = previous
        case let .skipExercise(exerciseId, previous):
            guard let exerciseIndex = session.exercises.firstIndex(where: { $0.exerciseId == exerciseId }) else {
                return
            }
            session.exercises[exerciseIndex].isSkipped = previous
        case let .changeExerciseIndex(previous):
            session.currentExerciseIndex = previous
        case let .addSet(exerciseId, setIndex, previousLocalOnlyStructuralChanges):
            guard let exerciseIndex = session.exercises.firstIndex(where: { $0.exerciseId == exerciseId }),
                  session.exercises[exerciseIndex].sets.indices.contains(setIndex),
                  let workoutExerciseIndex = session.workoutDetails.exercises.firstIndex(where: { $0.id == exerciseId })
            else {
                return
            }
            session.exercises[exerciseIndex].sets.remove(at: setIndex)
            var updatedExercises = session.workoutDetails.exercises
            updatedExercises[workoutExerciseIndex] = updatedExercises[workoutExerciseIndex]
                .updatingSetCount(session.exercises[exerciseIndex].sets.count)
            session.workoutDetails = session.workoutDetails.updatingExercises(updatedExercises)
            session.hasLocalOnlyStructuralChanges = previousLocalOnlyStructuralChanges
        case let .removeSet(exerciseId, setIndex, removedSet, previousLocalOnlyStructuralChanges):
            guard let exerciseIndex = session.exercises.firstIndex(where: { $0.exerciseId == exerciseId }),
                  let workoutExerciseIndex = session.workoutDetails.exercises.firstIndex(where: { $0.id == exerciseId })
            else {
                return
            }
            let insertIndex = min(setIndex, session.exercises[exerciseIndex].sets.count)
            session.exercises[exerciseIndex].sets.insert(removedSet, at: insertIndex)
            var updatedExercises = session.workoutDetails.exercises
            updatedExercises[workoutExerciseIndex] = updatedExercises[workoutExerciseIndex]
                .updatingSetCount(session.exercises[exerciseIndex].sets.count)
            session.workoutDetails = session.workoutDetails.updatingExercises(updatedExercises)
            session.hasLocalOnlyStructuralChanges = previousLocalOnlyStructuralChanges
        case let .addExercise(exerciseIndex, previousCurrentExerciseIndex, previousLocalOnlyStructuralChanges):
            guard session.workoutDetails.exercises.indices.contains(exerciseIndex),
                  session.exercises.indices.contains(exerciseIndex)
            else {
                return
            }
            var updatedExercises = session.workoutDetails.exercises
            updatedExercises.remove(at: exerciseIndex)
            session.workoutDetails = session.workoutDetails.updatingExercises(updatedExercises.normalizedWorkoutOrder())
            session.exercises.remove(at: exerciseIndex)
            session.currentExerciseIndex = max(
                0,
                min(previousCurrentExerciseIndex, max(0, session.exercises.count - 1)),
            )
            session.hasLocalOnlyStructuralChanges = previousLocalOnlyStructuralChanges
        case let .replaceExercise(exerciseIndex, previousExercise, previousState, previousLocalOnlyStructuralChanges):
            guard session.workoutDetails.exercises.indices.contains(exerciseIndex),
                  session.exercises.indices.contains(exerciseIndex)
            else {
                return
            }
            var updatedExercises = session.workoutDetails.exercises
            updatedExercises[exerciseIndex] = previousExercise.updatingOrderIndex(exerciseIndex)
            session.workoutDetails = session.workoutDetails.updatingExercises(updatedExercises)
            session.exercises[exerciseIndex] = previousState
            session.hasLocalOnlyStructuralChanges = previousLocalOnlyStructuralChanges
        case let .reorderExercises(previousExercises, previousStates, previousCurrentExerciseIndex, previousLocalOnlyStructuralChanges):
            session.workoutDetails = session.workoutDetails.updatingExercises(previousExercises)
            session.exercises = previousStates
            session.currentExerciseIndex = previousCurrentExerciseIndex
            session.hasLocalOnlyStructuralChanges = previousLocalOnlyStructuralChanges
        }
    }

    private func sessionState(
        from snapshot: WorkoutProgressSnapshot,
        workout: WorkoutDetailsModel,
    ) -> WorkoutSessionState {
        let resolvedWorkout = snapshot.workoutDetails ?? workout
        let exercises = resolvedWorkout.exercises.map { exercise in
            let stored = snapshot.exercises[exercise.id]
            let sets = Array(0 ..< max(1, exercise.sets)).map { index in
                if let storedSet = stored?.sets[safe: index] {
                    return SessionSetState(
                        isCompleted: storedSet.isCompleted,
                        repsText: storedSet.repsText,
                        weightText: storedSet.weightText,
                        rpeText: storedSet.rpeText,
                        isWarmup: storedSet.isWarmup,
                    )
                }
                return SessionSetState(
                    isCompleted: false,
                    repsText: "",
                    weightText: "",
                    rpeText: "",
                    isWarmup: false,
                )
            }
            return SessionExerciseState(exerciseId: exercise.id, sets: sets, isSkipped: false)
        }
        return WorkoutSessionState(
            userSub: snapshot.userSub,
            programId: snapshot.programId,
            workoutId: snapshot.workoutId,
            workoutTitle: resolvedWorkout.title,
            workoutDetails: resolvedWorkout,
            source: snapshot.source ?? .program,
            startedAt: snapshot.startedAt ?? snapshot.lastUpdated,
            currentExerciseIndex: max(0, min(snapshot.currentExerciseIndex ?? 0, max(0, exercises.count - 1))),
            lastUpdated: snapshot.lastUpdated,
            exercises: exercises,
            hasLocalOnlyStructuralChanges: snapshot.hasLocalOnlyStructuralChanges,
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
                    isWarmup: $0.isWarmup,
                )
            }
            return (exercise.exerciseId, StoredExerciseProgress(sets: sets))
        })
        return WorkoutProgressSnapshot(
            userSub: session.userSub,
            programId: session.programId,
            workoutId: session.workoutId,
            currentExerciseIndex: session.currentExerciseIndex,
            startedAt: session.startedAt,
            source: session.source,
            workoutDetails: session.workoutDetails,
            hasLocalOnlyStructuralChanges: session.hasLocalOnlyStructuralChanges,
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

private extension WorkoutExercise {
    func updatingSetCount(_ sets: Int) -> WorkoutExercise {
        WorkoutExercise(
            id: id,
            name: name,
            description: description,
            sets: max(1, sets),
            repsMin: repsMin,
            repsMax: repsMax,
            targetRpe: targetRpe,
            restSeconds: restSeconds,
            notes: notes,
            orderIndex: orderIndex,
            isBodyweight: isBodyweight,
            media: media,
        )
    }

    func updatingOrderIndex(_ orderIndex: Int) -> WorkoutExercise {
        WorkoutExercise(
            id: id,
            name: name,
            description: description,
            sets: sets,
            repsMin: repsMin,
            repsMax: repsMax,
            targetRpe: targetRpe,
            restSeconds: restSeconds,
            notes: notes,
            orderIndex: orderIndex,
            isBodyweight: isBodyweight,
            media: media,
            )
    }
}

private extension WorkoutDetailsModel {
    func updatingExercises(_ exercises: [WorkoutExercise]) -> WorkoutDetailsModel {
        WorkoutDetailsModel(
            id: id,
            title: title,
            dayOrder: dayOrder,
            coachNote: coachNote,
            exercises: exercises,
        )
    }
}

private extension Array where Element == WorkoutExercise {
    func normalizedWorkoutOrder() -> [WorkoutExercise] {
        enumerated().map { index, exercise in
            exercise.updatingOrderIndex(index)
        }
    }
}
