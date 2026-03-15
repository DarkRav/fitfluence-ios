import Foundation

struct ActiveEnrollmentProgressResponse: Codable, Equatable, Sendable {
    let enrollmentId: String?
    let status: String?
    let programId: String?
    let programTitle: String?
    let programVersionId: String?
    let currentWorkoutId: String?
    let currentWorkoutTitle: String?
    let currentWorkoutStatus: AthleteWorkoutInstanceStatus?
    let nextWorkoutId: String?
    let nextWorkoutTitle: String?
    let nextWorkoutStatus: AthleteWorkoutInstanceStatus?
    let completedSessions: Int?
    let totalSessions: Int?
    let completionPercent: Double?
    let lastCompletedAt: String?
    let updatedAt: String?

    static let empty = ActiveEnrollmentProgressResponse(
        enrollmentId: nil,
        status: nil,
        programId: nil,
        programTitle: nil,
        programVersionId: nil,
        currentWorkoutId: nil,
        currentWorkoutTitle: nil,
        currentWorkoutStatus: nil,
        nextWorkoutId: nil,
        nextWorkoutTitle: nil,
        nextWorkoutStatus: nil,
        completedSessions: nil,
        totalSessions: nil,
        completionPercent: nil,
        lastCompletedAt: nil,
        updatedAt: nil,
    )
}

enum AthleteWorkoutInstanceStatus: String, Codable, Equatable, Sendable {
    case planned = "PLANNED"
    case inProgress = "IN_PROGRESS"
    case completed = "COMPLETED"
    case missed = "MISSED"
    case abandoned = "ABANDONED"
}

struct AthleteStatsSummaryResponse: Codable, Equatable, Sendable {
    let streakDays: Int?
    let workouts7d: Int?
    let totalWorkouts: Int?
    let totalMinutes7d: Int?
    let lastWorkoutAt: String?

    private enum CodingKeys: String, CodingKey {
        case streakDays
        case workouts7d
        case totalWorkouts
        case totalMinutes7d
        case lastWorkoutAt
    }

    private enum DecodingKeys: String, CodingKey {
        case streakDays
        case currentStreakDays
        case streak
        case workouts7d
        case workoutsLast7Days
        case last7dWorkouts
        case totalWorkouts
        case workoutsTotal
        case totalMinutes7d
        case minutes7d
        case minutesLast7Days
        case lastWorkoutAt
        case lastCompletedAt
        case latestWorkoutAt
        case data
        case value
        case item
        case summary
        case stats
    }

    init(
        streakDays: Int?,
        workouts7d: Int?,
        totalWorkouts: Int?,
        totalMinutes7d: Int?,
        lastWorkoutAt: String?,
    ) {
        self.streakDays = streakDays
        self.workouts7d = workouts7d
        self.totalWorkouts = totalWorkouts
        self.totalMinutes7d = totalMinutes7d
        self.lastWorkoutAt = lastWorkoutAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DecodingKeys.self)

        if let wrapped = container.decodeLossySummary(forKeys: [.data, .value, .item, .summary, .stats]) {
            streakDays = wrapped.streakDays
            workouts7d = wrapped.workouts7d
            totalWorkouts = wrapped.totalWorkouts
            totalMinutes7d = wrapped.totalMinutes7d
            lastWorkoutAt = wrapped.lastWorkoutAt
            return
        }

        streakDays = container.decodeLossyInt(forKeys: [.streakDays, .currentStreakDays, .streak])
        workouts7d = container.decodeLossyInt(forKeys: [.workouts7d, .workoutsLast7Days, .last7dWorkouts])
        totalWorkouts = container.decodeLossyInt(forKeys: [.totalWorkouts, .workoutsTotal])
        totalMinutes7d = container.decodeLossyInt(forKeys: [.totalMinutes7d, .minutes7d, .minutesLast7Days])
        lastWorkoutAt = container.decodeLossyString(forKeys: [.lastWorkoutAt, .lastCompletedAt, .latestWorkoutAt])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(streakDays, forKey: .streakDays)
        try container.encodeIfPresent(workouts7d, forKey: .workouts7d)
        try container.encodeIfPresent(totalWorkouts, forKey: .totalWorkouts)
        try container.encodeIfPresent(totalMinutes7d, forKey: .totalMinutes7d)
        try container.encodeIfPresent(lastWorkoutAt, forKey: .lastWorkoutAt)
    }
}

private struct AthleteStatsSummaryPayload: Codable, Equatable, Sendable {
    let streakDays: Int?
    let workouts7d: Int?
    let totalWorkouts: Int?
    let totalMinutes7d: Int?
    let lastWorkoutAt: String?

    private enum DecodingKeys: String, CodingKey {
        case streakDays
        case currentStreakDays
        case streak
        case workouts7d
        case workoutsLast7Days
        case last7dWorkouts
        case totalWorkouts
        case workoutsTotal
        case totalMinutes7d
        case minutes7d
        case minutesLast7Days
        case lastWorkoutAt
        case lastCompletedAt
        case latestWorkoutAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DecodingKeys.self)
        streakDays = container.decodeLossyInt(forKeys: [.streakDays, .currentStreakDays, .streak])
        workouts7d = container.decodeLossyInt(forKeys: [.workouts7d, .workoutsLast7Days, .last7dWorkouts])
        totalWorkouts = container.decodeLossyInt(forKeys: [.totalWorkouts, .workoutsTotal])
        totalMinutes7d = container.decodeLossyInt(forKeys: [.totalMinutes7d, .minutes7d, .minutesLast7Days])
        lastWorkoutAt = container.decodeLossyString(forKeys: [.lastWorkoutAt, .lastCompletedAt, .latestWorkoutAt])
    }
}

enum AthleteWorkoutSource: String, Codable, Equatable, Sendable {
    case program = "PROGRAM"
    case custom = "CUSTOM"
}

struct AthleteWorkoutInstance: Codable, Equatable, Sendable {
    let id: String
    let enrollmentId: String?
    let workoutTemplateId: String?
    let title: String?
    let status: AthleteWorkoutInstanceStatus?
    let source: AthleteWorkoutSource
    let scheduledDate: String?
    let startedAt: String?
    let completedAt: String?
    let durationSeconds: Int?
    let notes: String?
    let programId: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case enrollmentId
        case workoutTemplateId
        case title
        case status
        case source
        case scheduledDate
        case startedAt
        case completedAt
        case durationSeconds
        case notes
        case programId
    }

    private enum DecodingKeys: String, CodingKey {
        case id
        case workoutInstanceId
        case enrollmentId
        case workoutTemplateId
        case title
        case status
        case source
        case scheduledDate
        case startedAt
        case completedAt
        case durationSeconds
        case notes
        case programId
    }

    init(
        id: String,
        enrollmentId: String?,
        workoutTemplateId: String?,
        title: String?,
        status: AthleteWorkoutInstanceStatus?,
        source: AthleteWorkoutSource,
        scheduledDate: String?,
        startedAt: String?,
        completedAt: String?,
        durationSeconds: Int?,
        notes: String?,
        programId: String?,
    ) {
        self.id = id
        self.enrollmentId = enrollmentId
        self.workoutTemplateId = workoutTemplateId
        self.title = title
        self.status = status
        self.source = source
        self.scheduledDate = scheduledDate
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationSeconds = durationSeconds
        self.notes = notes
        self.programId = programId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DecodingKeys.self)
        let resolvedID = container.decodeLossyString(forKeys: [.id, .workoutInstanceId]) ?? UUID().uuidString
        let resolvedSource = (try? container.decodeIfPresent(AthleteWorkoutSource.self, forKey: .source)) ?? .program

        id = resolvedID
        enrollmentId = container.decodeLossyString(forKeys: [.enrollmentId])
        workoutTemplateId = container.decodeLossyString(forKeys: [.workoutTemplateId])
        title = container.decodeLossyString(forKeys: [.title])
        status = try? container.decodeIfPresent(AthleteWorkoutInstanceStatus.self, forKey: .status)
        source = resolvedSource
        scheduledDate = container.decodeLossyString(forKeys: [.scheduledDate])
        startedAt = container.decodeLossyString(forKeys: [.startedAt])
        completedAt = container.decodeLossyString(forKeys: [.completedAt])
        durationSeconds = container.decodeLossyInt(forKeys: [.durationSeconds])
        notes = container.decodeLossyString(forKeys: [.notes])
        programId = container.decodeLossyString(forKeys: [.programId])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(enrollmentId, forKey: .enrollmentId)
        try container.encodeIfPresent(workoutTemplateId, forKey: .workoutTemplateId)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(scheduledDate, forKey: .scheduledDate)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(programId, forKey: .programId)
    }
}

struct AthleteExerciseBrief: Codable, Equatable, Sendable {
    let id: String
    let code: String?
    let name: String
    let description: String?
    let isBodyweight: Bool?
    let media: [ContentMedia]?
}

struct AthleteSetExecution: Codable, Equatable, Sendable {
    let id: String
    let setNumber: Int
    let weight: Double?
    let reps: Int?
    let rpe: Int?
    let isCompleted: Bool
    let restSecondsActual: Int?
}

struct AthleteExerciseExecution: Codable, Equatable, Sendable {
    let id: String
    let workoutInstanceId: String
    let exerciseTemplateId: String?
    let workoutPlanId: String?
    let exerciseId: String
    let orderIndex: Int
    let notes: String?
    let plannedSets: Int?
    let plannedRepsMin: Int?
    let plannedRepsMax: Int?
    let plannedTargetRpe: Int?
    let plannedRestSeconds: Int?
    let plannedNotes: String?
    let progressionPolicyId: String?
    let exercise: AthleteExerciseBrief?
    let sets: [AthleteSetExecution]?
}

struct AthleteWorkoutDetailsResponse: Codable, Equatable, Sendable {
    let workout: AthleteWorkoutInstance
    let exercises: [AthleteExerciseExecution]
}

struct AthleteWorkoutCompleteResponse: Codable, Equatable, Sendable {
    let workout: AthleteWorkoutInstance

    init(workout: AthleteWorkoutInstance) {
        self.workout = workout
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let direct = try? container.decode(AthleteWorkoutInstance.self)
        {
            workout = direct
            return
        }

        let wrapped = try WorkoutCompleteContainer(from: decoder)
        if let workout = wrapped.workout ?? wrapped.item ?? wrapped.data ?? wrapped.value {
            self.workout = workout
            return
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported complete workout payload"),
        )
    }
}

struct AthleteWorkoutComparisonResponse: Codable, Equatable, Sendable {
    let workoutInstanceId: String?
    let previousWorkoutInstanceId: String?
    let durationSeconds: Int?
    let totalSets: Int?
    let totalReps: Int?
    let volume: Double?
    let repsDelta: Int?
    let volumeDelta: Double?
    let durationDeltaSeconds: Int?
    let personalRecords: [AthletePersonalRecord]?
    let hasNewPersonalRecord: Bool?

    private enum CodingKeys: String, CodingKey {
        case workoutInstanceId
        case previousWorkoutInstanceId
        case durationSeconds
        case totalSets
        case totalReps
        case volume
        case repsDelta
        case volumeDelta
        case durationDeltaSeconds
        case personalRecords
        case hasNewPersonalRecord
    }

    private enum DecodingKeys: String, CodingKey {
        case id
        case workoutInstanceId
        case workoutId
        case previousWorkoutInstanceId
        case previousWorkoutId
        case previousInstanceId
        case durationSeconds
        case totalSets
        case totalReps
        case volume
        case repsDelta
        case deltaReps
        case repsDifference
        case repsDiff
        case volumeDelta
        case deltaVolume
        case volumeDifference
        case volumeDiff
        case durationDeltaSeconds
        case deltaDurationSeconds
        case durationDifferenceSeconds
        case durationDiffSeconds
        case personalRecords
        case newPersonalRecords
        case prs
        case hasNewPersonalRecord
        case hasNewPR
    }

    init(
        workoutInstanceId: String?,
        previousWorkoutInstanceId: String?,
        durationSeconds: Int?,
        totalSets: Int?,
        totalReps: Int?,
        volume: Double?,
        repsDelta: Int?,
        volumeDelta: Double?,
        durationDeltaSeconds: Int?,
        personalRecords: [AthletePersonalRecord]?,
        hasNewPersonalRecord: Bool?,
    ) {
        self.workoutInstanceId = workoutInstanceId
        self.previousWorkoutInstanceId = previousWorkoutInstanceId
        self.durationSeconds = durationSeconds
        self.totalSets = totalSets
        self.totalReps = totalReps
        self.volume = volume
        self.repsDelta = repsDelta
        self.volumeDelta = volumeDelta
        self.durationDeltaSeconds = durationDeltaSeconds
        self.personalRecords = personalRecords
        self.hasNewPersonalRecord = hasNewPersonalRecord
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DecodingKeys.self)
        workoutInstanceId = container.decodeLossyString(forKeys: [.workoutInstanceId, .workoutId, .id])
        previousWorkoutInstanceId = container.decodeLossyString(
            forKeys: [.previousWorkoutInstanceId, .previousWorkoutId, .previousInstanceId],
        )
        durationSeconds = container.decodeLossyInt(forKeys: [.durationSeconds])
        totalSets = container.decodeLossyInt(forKeys: [.totalSets])
        totalReps = container.decodeLossyInt(forKeys: [.totalReps])
        volume = container.decodeLossyDouble(forKeys: [.volume])
        repsDelta = container.decodeLossyInt(forKeys: [.repsDelta, .deltaReps, .repsDifference, .repsDiff])
        volumeDelta = container.decodeLossyDouble(
            forKeys: [.volumeDelta, .deltaVolume, .volumeDifference, .volumeDiff],
        )
        durationDeltaSeconds = container.decodeLossyInt(
            forKeys: [.durationDeltaSeconds, .deltaDurationSeconds, .durationDifferenceSeconds, .durationDiffSeconds],
        )
        personalRecords = container.decodeLossyArray(
            forKeys: [.personalRecords, .newPersonalRecords, .prs],
        )
        hasNewPersonalRecord = container.decodeLossyBool(forKeys: [.hasNewPersonalRecord, .hasNewPR])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(workoutInstanceId, forKey: .workoutInstanceId)
        try container.encodeIfPresent(previousWorkoutInstanceId, forKey: .previousWorkoutInstanceId)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(totalSets, forKey: .totalSets)
        try container.encodeIfPresent(totalReps, forKey: .totalReps)
        try container.encodeIfPresent(volume, forKey: .volume)
        try container.encodeIfPresent(repsDelta, forKey: .repsDelta)
        try container.encodeIfPresent(volumeDelta, forKey: .volumeDelta)
        try container.encodeIfPresent(durationDeltaSeconds, forKey: .durationDeltaSeconds)
        try container.encodeIfPresent(personalRecords, forKey: .personalRecords)
        try container.encodeIfPresent(hasNewPersonalRecord, forKey: .hasNewPersonalRecord)
    }
}

struct AthleteSetExecutionUpdateResponse: Codable, Equatable, Sendable {
    let set: AthleteSetExecution

    init(set: AthleteSetExecution) {
        self.set = set
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let direct = try? container.decode(AthleteSetExecution.self)
        {
            set = direct
            return
        }

        let wrapped = try SetExecutionUpdateContainer(from: decoder)
        if let set = wrapped.set ?? wrapped.item ?? wrapped.data ?? wrapped.value {
            self.set = set
            return
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported set update payload"),
        )
    }
}

struct AthleteCalendarResponse: Codable, Equatable, Sendable {
    let workouts: [AthleteWorkoutInstance]

    init(workouts: [AthleteWorkoutInstance]) {
        self.workouts = workouts
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let array = try? container.decode([AthleteWorkoutInstance].self)
        {
            workouts = array
            return
        }

        let wrapped = try CalendarContainer(from: decoder)
        workouts = wrapped.allWorkouts
    }
}

struct AthleteEnrollmentScheduleResponse: Codable, Equatable, Sendable {
    let enrollmentId: String?
    let workouts: [AthleteWorkoutInstance]

    init(enrollmentId: String?, workouts: [AthleteWorkoutInstance]) {
        self.enrollmentId = enrollmentId
        self.workouts = workouts
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let array = try? container.decode([AthleteWorkoutInstance].self)
        {
            enrollmentId = nil
            workouts = array
            return
        }

        let wrapped = try EnrollmentScheduleContainer(from: decoder)
        enrollmentId = wrapped.enrollmentId
        workouts = wrapped.allWorkouts
    }
}

enum AthleteSyncState: String, Codable, Equatable, Sendable {
    case synced = "SYNCED"
    case savedLocally = "SAVED_LOCALLY"
    case delayed = "DELAYED"
    case unknown = "UNKNOWN"
}

struct AthleteSyncStatusResponse: Codable, Equatable, Sendable {
    let status: AthleteSyncState?
    let hasPendingLocalChanges: Bool?
    let isDelayed: Bool?
    let pendingOperations: Int?
    let lastSyncedAt: String?
}

struct AthleteExerciseHistoryEntry: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let workoutInstanceId: String?
    let performedAt: String?
    let weight: Double?
    let reps: Int?
    let oneRepMaxEstimate: Double?
    let volume: Double?
    let notes: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case workoutInstanceId
        case performedAt
        case weight
        case reps
        case oneRepMaxEstimate
        case volume
        case notes
    }

    private enum DecodingKeys: String, CodingKey {
        case id
        case workoutInstanceId
        case performedAt
        case completedAt
        case finishedAt
        case weight
        case reps
        case oneRepMaxEstimate
        case estimatedOneRepMax
        case volume
        case notes
    }

    init(
        id: String,
        workoutInstanceId: String?,
        performedAt: String?,
        weight: Double?,
        reps: Int?,
        oneRepMaxEstimate: Double?,
        volume: Double?,
        notes: String?,
    ) {
        self.id = id
        self.workoutInstanceId = workoutInstanceId
        self.performedAt = performedAt
        self.weight = weight
        self.reps = reps
        self.oneRepMaxEstimate = oneRepMaxEstimate
        self.volume = volume
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DecodingKeys.self)
        id = container.decodeLossyString(forKeys: [.id]) ?? UUID().uuidString
        workoutInstanceId = container.decodeLossyString(forKeys: [.workoutInstanceId])
        performedAt = container.decodeLossyString(forKeys: [.performedAt, .completedAt, .finishedAt])
        weight = container.decodeLossyDouble(forKeys: [.weight])
        reps = container.decodeLossyInt(forKeys: [.reps])
        oneRepMaxEstimate = container.decodeLossyDouble(forKeys: [.oneRepMaxEstimate, .estimatedOneRepMax])
        volume = container.decodeLossyDouble(forKeys: [.volume])
        notes = container.decodeLossyString(forKeys: [.notes])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(workoutInstanceId, forKey: .workoutInstanceId)
        try container.encodeIfPresent(performedAt, forKey: .performedAt)
        try container.encodeIfPresent(weight, forKey: .weight)
        try container.encodeIfPresent(reps, forKey: .reps)
        try container.encodeIfPresent(oneRepMaxEstimate, forKey: .oneRepMaxEstimate)
        try container.encodeIfPresent(volume, forKey: .volume)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}

struct AthleteExerciseHistoryResponse: Codable, Equatable, Sendable {
    let exerciseId: String?
    let entries: [AthleteExerciseHistoryEntry]

    init(exerciseId: String?, entries: [AthleteExerciseHistoryEntry]) {
        self.exerciseId = exerciseId
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let array = try? container.decode([AthleteExerciseHistoryEntry].self)
        {
            exerciseId = nil
            entries = array
            return
        }

        let wrapped = try ExerciseHistoryContainer(from: decoder)
        exerciseId = wrapped.exerciseId
        entries = wrapped.allEntries
    }
}

struct AthleteExerciseLastPerformanceSet: Codable, Equatable, Sendable, Identifiable {
    let setNumber: Int
    let weight: Double?
    let reps: Int?
    let rpe: Int?
    let volume: Double?

    var id: Int {
        setNumber
    }

    private enum CodingKeys: String, CodingKey {
        case setNumber
        case weight
        case reps
        case rpe
        case volume
    }

    private enum DecodingKeys: String, CodingKey {
        case setNumber
        case number
        case set
        case order
        case weight
        case load
        case reps
        case repetitions
        case rpe
        case effort
        case volume
    }

    init(setNumber: Int, weight: Double?, reps: Int?, rpe: Int?, volume: Double?) {
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.volume = volume
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DecodingKeys.self)
        setNumber = max(1, container.decodeLossyInt(forKeys: [.setNumber, .number, .set, .order]) ?? 1)
        weight = container.decodeLossyDouble(forKeys: [.weight, .load])
        reps = container.decodeLossyInt(forKeys: [.reps, .repetitions])
        rpe = container.decodeLossyInt(forKeys: [.rpe, .effort])
        volume = container.decodeLossyDouble(forKeys: [.volume])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(setNumber, forKey: .setNumber)
        try container.encodeIfPresent(weight, forKey: .weight)
        try container.encodeIfPresent(reps, forKey: .reps)
        try container.encodeIfPresent(rpe, forKey: .rpe)
        try container.encodeIfPresent(volume, forKey: .volume)
    }
}

struct AthleteExerciseLastPerformanceResponse: Codable, Equatable, Sendable {
    let exerciseId: String?
    let workoutInstanceId: String?
    let performedAt: String?
    let sets: [AthleteExerciseLastPerformanceSet]

    private enum CodingKeys: String, CodingKey {
        case exerciseId
        case workoutInstanceId
        case performedAt
        case sets
    }

    private enum DecodingKeys: String, CodingKey {
        case exerciseId
        case workoutInstanceId
        case workoutId
        case performedAt
        case completedAt
        case finishedAt
        case sets
        case lastSets
        case data
        case value
    }

    init(
        exerciseId: String?,
        workoutInstanceId: String?,
        performedAt: String?,
        sets: [AthleteExerciseLastPerformanceSet],
    ) {
        self.exerciseId = exerciseId
        self.workoutInstanceId = workoutInstanceId
        self.performedAt = performedAt
        self.sets = sets
    }

    init(from decoder: Decoder) throws {
        if let direct = try? decoder.singleValueContainer().decode([AthleteExerciseLastPerformanceSet].self) {
            exerciseId = nil
            workoutInstanceId = nil
            performedAt = nil
            sets = direct.sorted(by: { $0.setNumber < $1.setNumber })
            return
        }

        if let wrapped = try? LastPerformanceWrappedContainer(from: decoder),
           let nested = wrapped.lastPerformance ?? wrapped.data ?? wrapped.value
        {
            exerciseId = nested.exerciseId
            workoutInstanceId = nested.workoutInstanceId
            performedAt = nested.performedAt
            sets = nested.sets.sorted(by: { $0.setNumber < $1.setNumber })
            return
        }

        let container = try decoder.container(keyedBy: DecodingKeys.self)
        exerciseId = container.decodeLossyString(forKeys: [.exerciseId])
        workoutInstanceId = container.decodeLossyString(forKeys: [.workoutInstanceId, .workoutId])
        performedAt = container.decodeLossyString(forKeys: [.performedAt, .completedAt, .finishedAt])
        sets = (container.decodeLossyArray(forKeys: [.sets, .lastSets, .data, .value]) ?? [])
            .sorted(by: { $0.setNumber < $1.setNumber })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(exerciseId, forKey: .exerciseId)
        try container.encodeIfPresent(workoutInstanceId, forKey: .workoutInstanceId)
        try container.encodeIfPresent(performedAt, forKey: .performedAt)
        try container.encode(sets, forKey: .sets)
    }
}

struct AthletePersonalRecord: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let exerciseId: String?
    let exerciseName: String?
    let metric: String?
    let value: Double?
    let unit: String?
    let achievedAt: String?
    let workoutInstanceId: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case exerciseId
        case exerciseName
        case metric
        case value
        case unit
        case achievedAt
        case workoutInstanceId
    }

    init(
        id: String,
        exerciseId: String?,
        exerciseName: String?,
        metric: String?,
        value: Double?,
        unit: String?,
        achievedAt: String?,
        workoutInstanceId: String?,
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.metric = metric
        self.value = value
        self.unit = unit
        self.achievedAt = achievedAt
        self.workoutInstanceId = workoutInstanceId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyString(forKeys: [.id]) ?? UUID().uuidString
        exerciseId = container.decodeLossyString(forKeys: [.exerciseId])
        exerciseName = container.decodeLossyString(forKeys: [.exerciseName])
        metric = container.decodeLossyString(forKeys: [.metric])
        value = container.decodeLossyDouble(forKeys: [.value])
        unit = container.decodeLossyString(forKeys: [.unit])
        achievedAt = container.decodeLossyString(forKeys: [.achievedAt])
        workoutInstanceId = container.decodeLossyString(forKeys: [.workoutInstanceId])
    }
}

struct AthletePersonalRecordsResponse: Codable, Equatable, Sendable {
    let records: [AthletePersonalRecord]

    init(records: [AthletePersonalRecord]) {
        self.records = records
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let array = try? container.decode([AthletePersonalRecord].self)
        {
            records = array
            return
        }

        let wrapped = try PersonalRecordsContainer(from: decoder)
        records = wrapped.allRecords
    }
}

struct CreatorProgramAnalytics: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String?
    let activeEnrollments: Int?
    let completions: Int?
    let completionRate: Double?
}

struct CreatorAnalyticsResponse: Codable, Equatable, Sendable {
    let totalFollowers: Int?
    let activeEnrollments: Int?
    let completionRate: Double?
    let totalCompletions: Int?
    let periodStart: String?
    let periodEnd: String?
    let programs: [CreatorProgramAnalytics]?
}

private struct StartWorkoutRequestBody: Codable, Sendable {
    let startedAt: String?
}

private struct CompleteWorkoutRequestBody: Codable, Sendable {
    let completedAt: String?
}

private struct AbandonWorkoutRequestBody: Codable, Sendable {
    let abandonedAt: String?
}

private struct UpdateExerciseSetRequestBody: Codable, Sendable {
    let weight: Double?
    let reps: Int?
    let rpe: Int?
    let isCompleted: Bool?
}

protocol AthleteTrainingClientProtocol: Sendable {
    func activeEnrollments() async -> Result<[ActiveEnrollmentProgressResponse], APIError>
    func activeEnrollmentProgress() async -> Result<ActiveEnrollmentProgressResponse, APIError>
    func calendar(month: String) async -> Result<AthleteCalendarResponse, APIError>
    func enrollmentSchedule(enrollmentId: String) async -> Result<AthleteEnrollmentScheduleResponse, APIError>
    func syncStatus() async -> Result<AthleteSyncStatusResponse, APIError>
    func exerciseHistory(
        exerciseId: String,
        page: Int?,
        size: Int?,
    ) async -> Result<AthleteExerciseHistoryResponse, APIError>
    func lastPerformance(exerciseId: String) async -> Result<AthleteExerciseLastPerformanceResponse, APIError>
    func personalRecords(exerciseId: String?) async -> Result<AthletePersonalRecordsResponse, APIError>
    func statsSummary() async -> Result<AthleteStatsSummaryResponse, APIError>
    func creatorAnalytics() async -> Result<CreatorAnalyticsResponse, APIError>
    func getWorkoutDetails(workoutInstanceId: String) async -> Result<AthleteWorkoutDetailsResponse, APIError>
    func startWorkout(workoutInstanceId: String, startedAt: Date?) async -> Result<AthleteWorkoutInstance, APIError>
    func completeWorkout(workoutInstanceId: String, completedAt: Date?) async -> Result<AthleteWorkoutInstance, APIError>
    func abandonWorkout(workoutInstanceId: String, abandonedAt: Date?) async -> Result<AthleteWorkoutInstance, APIError>
    func updateExerciseSet(
        exerciseExecutionId: String,
        setNumber: Int,
        weight: Double?,
        reps: Int?,
        rpe: Int?,
        isCompleted: Bool?,
    ) async -> Result<AthleteSetExecution, APIError>
    func workoutComparison(workoutInstanceId: String) async -> Result<AthleteWorkoutComparisonResponse, APIError>
}

extension AthleteTrainingClientProtocol {
    func activeEnrollments() async -> Result<[ActiveEnrollmentProgressResponse], APIError> {
        switch await activeEnrollmentProgress() {
        case let .success(value):
            return .success([value])
        case let .failure(error):
            return .failure(error)
        }
    }

    func calendar(month _: String) async -> Result<AthleteCalendarResponse, APIError> {
        .failure(.unknown)
    }

    func enrollmentSchedule(enrollmentId _: String) async -> Result<AthleteEnrollmentScheduleResponse, APIError> {
        .failure(.unknown)
    }

    func syncStatus() async -> Result<AthleteSyncStatusResponse, APIError> {
        .failure(.unknown)
    }

    func exerciseHistory(
        exerciseId _: String,
        page _: Int?,
        size _: Int?,
    ) async -> Result<AthleteExerciseHistoryResponse, APIError> {
        .failure(.unknown)
    }

    func lastPerformance(exerciseId _: String) async -> Result<AthleteExerciseLastPerformanceResponse, APIError> {
        .failure(.unknown)
    }

    func personalRecords(exerciseId _: String?) async -> Result<AthletePersonalRecordsResponse, APIError> {
        .failure(.unknown)
    }

    func statsSummary() async -> Result<AthleteStatsSummaryResponse, APIError> {
        .failure(.unknown)
    }

    func creatorAnalytics() async -> Result<CreatorAnalyticsResponse, APIError> {
        .failure(.unknown)
    }

    func completeWorkout(workoutInstanceId _: String, completedAt _: Date?) async -> Result<AthleteWorkoutInstance, APIError> {
        .failure(.unknown)
    }

    func abandonWorkout(workoutInstanceId _: String, abandonedAt _: Date?) async -> Result<AthleteWorkoutInstance, APIError> {
        .failure(.unknown)
    }

    func updateExerciseSet(
        exerciseExecutionId _: String,
        setNumber _: Int,
        weight _: Double?,
        reps _: Int?,
        rpe _: Int?,
        isCompleted _: Bool?,
    ) async -> Result<AthleteSetExecution, APIError> {
        .failure(.unknown)
    }

    func workoutComparison(workoutInstanceId _: String) async -> Result<AthleteWorkoutComparisonResponse, APIError> {
        .failure(.unknown)
    }

    func exerciseHistory(exerciseId: String) async -> Result<AthleteExerciseHistoryResponse, APIError> {
        await exerciseHistory(exerciseId: exerciseId, page: nil, size: nil)
    }

    func personalRecords() async -> Result<AthletePersonalRecordsResponse, APIError> {
        await personalRecords(exerciseId: nil)
    }
}

extension AthleteWorkoutDetailsResponse {
    func asWorkoutDetailsModel() -> WorkoutDetailsModel {
        let mappedExercises = exercises
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .enumerated()
            .map { index, execution in
                WorkoutExercise(
                    id: execution.exerciseId,
                    name: execution.exercise?.name.trimmedNilIfEmpty ?? "Упражнение \(index + 1)",
                    description: execution.exercise?.description?.trimmedNilIfEmpty,
                    sets: max(1, execution.plannedSets ?? execution.sets?.count ?? 1),
                    repsMin: execution.plannedRepsMin,
                    repsMax: execution.plannedRepsMax,
                    targetRpe: execution.plannedTargetRpe,
                    restSeconds: execution.plannedRestSeconds,
                    notes: execution.plannedNotes?.trimmedNilIfEmpty ?? execution.notes?.trimmedNilIfEmpty,
                    orderIndex: execution.orderIndex,
                    isBodyweight: execution.exercise?.isBodyweight ?? false,
                    media: execution.exercise?.media,
                )
            }

        let title = workout.title?.trimmedNilIfEmpty ?? "Тренировка"

        return WorkoutDetailsModel(
            id: workout.id,
            title: title,
            dayOrder: 0,
            coachNote: workout.notes?.trimmedNilIfEmpty,
            exercises: mappedExercises,
        )
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension APIClient: AthleteTrainingClientProtocol {
    func activeEnrollments() async -> Result<[ActiveEnrollmentProgressResponse], APIError> {
        let request = APIRequest.get(path: "/v1/athlete/enrollments/active", requiresAuthorization: true)
        let result = await decode(request, as: ActiveEnrollmentsResponse.self)
        switch result {
        case let .success(response):
            return .success(response.items)
        case let .failure(error):
            if case let .httpError(statusCode, _) = error, statusCode == 404 {
                return .success([])
            }
            return .failure(error)
        }
    }

    func activeEnrollmentProgress() async -> Result<ActiveEnrollmentProgressResponse, APIError> {
        let result = await activeEnrollments()
        switch result {
        case let .success(items):
            if let active = items.first(where: { $0.status?.uppercased() == "ACTIVE" }) {
                return .success(active)
            }
            if let first = items.first {
                return .success(first)
            }
            return .success(.empty)
        case let .failure(error):
            return .failure(error)
        }
    }

    func calendar(month: String) async -> Result<AthleteCalendarResponse, APIError> {
        let request = APIRequest.get(
            path: "/v1/athlete/calendar",
            queryItems: [URLQueryItem(name: "month", value: month)],
            requiresAuthorization: true,
        )
        return await decode(request, as: AthleteCalendarResponse.self)
    }

    func enrollmentSchedule(enrollmentId: String) async -> Result<AthleteEnrollmentScheduleResponse, APIError> {
        let request = APIRequest.get(
            path: "/v1/athlete/enrollments/\(enrollmentId)/schedule",
            requiresAuthorization: true,
        )
        return await decode(request, as: AthleteEnrollmentScheduleResponse.self)
    }

    func syncStatus() async -> Result<AthleteSyncStatusResponse, APIError> {
        let request = APIRequest.get(path: "/v1/athlete/sync/status", requiresAuthorization: true)
        return await decode(request, as: AthleteSyncStatusResponse.self)
    }

    func exerciseHistory(
        exerciseId: String,
        page: Int?,
        size: Int?,
    ) async -> Result<AthleteExerciseHistoryResponse, APIError> {
        var queryItems: [URLQueryItem] = []
        if let page {
            queryItems.append(URLQueryItem(name: "page", value: "\(page)"))
        }
        if let size {
            queryItems.append(URLQueryItem(name: "size", value: "\(size)"))
        }
        let request = APIRequest.get(
            path: "/v1/athlete/exercises/\(exerciseId)/history",
            queryItems: queryItems,
            requiresAuthorization: true,
        )
        return await decode(request, as: AthleteExerciseHistoryResponse.self)
    }

    func lastPerformance(exerciseId: String) async -> Result<AthleteExerciseLastPerformanceResponse, APIError> {
        let request = APIRequest.get(path: "/v1/athlete/exercises/\(exerciseId)/last-performance", requiresAuthorization: true)
        return await decode(request, as: AthleteExerciseLastPerformanceResponse.self)
    }

    func personalRecords(exerciseId: String?) async -> Result<AthletePersonalRecordsResponse, APIError> {
        var queryItems: [URLQueryItem] = []
        if let exerciseId {
            queryItems.append(URLQueryItem(name: "exerciseId", value: exerciseId))
        }
        let request = APIRequest.get(path: "/v1/athlete/prs", queryItems: queryItems, requiresAuthorization: true)
        return await decode(request, as: AthletePersonalRecordsResponse.self)
    }

    func statsSummary() async -> Result<AthleteStatsSummaryResponse, APIError> {
        let request = APIRequest.get(path: "/v1/athlete/stats/summary", requiresAuthorization: true)
        return await decode(request, as: AthleteStatsSummaryResponse.self)
    }

    func creatorAnalytics() async -> Result<CreatorAnalyticsResponse, APIError> {
        let creatorRequest = APIRequest.get(path: "/v1/creator/analytics", requiresAuthorization: true)
        let creatorResult = await decode(creatorRequest, as: CreatorAnalyticsResponse.self)
        switch creatorResult {
        case .success:
            return creatorResult
        case let .failure(error):
            if case let .httpError(statusCode, _) = error, statusCode == 404 {
                let influencerRequest = APIRequest.get(path: "/v1/influencer/analytics", requiresAuthorization: true)
                return await decode(influencerRequest, as: CreatorAnalyticsResponse.self)
            }
            return .failure(error)
        }
    }

    func getWorkoutDetails(workoutInstanceId: String) async -> Result<AthleteWorkoutDetailsResponse, APIError> {
        let request = APIRequest.get(path: "/v1/athlete/workouts/\(workoutInstanceId)", requiresAuthorization: true)
        return await decode(request, as: AthleteWorkoutDetailsResponse.self)
    }

    func startWorkout(workoutInstanceId: String, startedAt: Date?) async -> Result<AthleteWorkoutInstance, APIError> {
        do {
            var body: Data?
            if let startedAt {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let payload = StartWorkoutRequestBody(startedAt: formatter.string(from: startedAt))
                body = try JSONEncoder().encode(payload)
            }

            let request = APIRequest(
                path: "/v1/athlete/workouts/\(workoutInstanceId)/start",
                method: .post,
                body: body,
                requiresAuthorization: true,
            )
            return await decode(request, as: AthleteWorkoutInstance.self)
        } catch {
            return .failure(.unknown)
        }
    }

    func completeWorkout(workoutInstanceId: String, completedAt: Date?) async -> Result<AthleteWorkoutInstance, APIError> {
        do {
            var body: Data?
            if let completedAt {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let payload = CompleteWorkoutRequestBody(completedAt: formatter.string(from: completedAt))
                body = try JSONEncoder().encode(payload)
            }

            let request = APIRequest(
                path: "/v1/athlete/workouts/\(workoutInstanceId)/complete",
                method: .post,
                body: body,
                requiresAuthorization: true,
            )
            let responseResult = await decode(request, as: AthleteWorkoutCompleteResponse.self)
            switch responseResult {
            case let .success(response):
                return .success(response.workout)
            case let .failure(error):
                return .failure(error)
            }
        } catch {
            return .failure(.unknown)
        }
    }

    func abandonWorkout(workoutInstanceId: String, abandonedAt: Date?) async -> Result<AthleteWorkoutInstance, APIError> {
        do {
            var body: Data?
            if let abandonedAt {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let payload = AbandonWorkoutRequestBody(abandonedAt: formatter.string(from: abandonedAt))
                body = try JSONEncoder().encode(payload)
            }

            let request = APIRequest(
                path: "/v1/athlete/workouts/\(workoutInstanceId)/abandon",
                method: .post,
                body: body,
                requiresAuthorization: true,
            )
            let responseResult = await decode(request, as: AthleteWorkoutCompleteResponse.self)
            switch responseResult {
            case let .success(response):
                return .success(response.workout)
            case let .failure(error):
                return .failure(error)
            }
        } catch {
            return .failure(.unknown)
        }
    }

    func updateExerciseSet(
        exerciseExecutionId: String,
        setNumber: Int,
        weight: Double?,
        reps: Int?,
        rpe: Int?,
        isCompleted: Bool?,
    ) async -> Result<AthleteSetExecution, APIError> {
        do {
            let payload = UpdateExerciseSetRequestBody(
                weight: weight,
                reps: reps,
                rpe: rpe,
                isCompleted: isCompleted,
            )
            let body = try JSONEncoder().encode(payload)
            let request = APIRequest(
                path: "/v1/athlete/exercise-executions/\(exerciseExecutionId)/sets/\(setNumber)",
                method: .put,
                body: body,
                requiresAuthorization: true,
            )

            let responseResult = await decode(request, as: AthleteSetExecutionUpdateResponse.self)
            switch responseResult {
            case let .success(response):
                return .success(response.set)
            case let .failure(error):
                return .failure(error)
            }
        } catch {
            return .failure(.unknown)
        }
    }

    func workoutComparison(workoutInstanceId: String) async -> Result<AthleteWorkoutComparisonResponse, APIError> {
        let request = APIRequest.get(
            path: "/v1/athlete/workouts/\(workoutInstanceId)/comparison",
            requiresAuthorization: true,
        )
        return await decode(request, as: AthleteWorkoutComparisonResponse.self)
    }
}

private struct ActiveEnrollmentsResponse: Codable, Equatable, Sendable {
    let items: [ActiveEnrollmentProgressResponse]

    init(items: [ActiveEnrollmentProgressResponse]) {
        self.items = items
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let list = try? container.decode([ActiveEnrollmentProgressResponse].self)
        {
            items = list
            return
        }

        if let container = try? decoder.singleValueContainer(),
           let single = try? container.decode(ActiveEnrollmentProgressResponse.self)
        {
            items = [single]
            return
        }

        let wrapped = try ActiveEnrollmentsContainer(from: decoder)
        items = wrapped.allItems
    }
}

private struct ActiveEnrollmentsContainer: Codable, Equatable, Sendable {
    let items: [ActiveEnrollmentProgressResponse]?
    let content: [ActiveEnrollmentProgressResponse]?
    let enrollments: [ActiveEnrollmentProgressResponse]?
    let active: [ActiveEnrollmentProgressResponse]?
    let data: [ActiveEnrollmentProgressResponse]?
    let value: [ActiveEnrollmentProgressResponse]?

    var allItems: [ActiveEnrollmentProgressResponse] {
        if let enrollments, !enrollments.isEmpty {
            return enrollments
        }
        if let active, !active.isEmpty {
            return active
        }
        if let items, !items.isEmpty {
            return items
        }
        if let content, !content.isEmpty {
            return content
        }
        if let data, !data.isEmpty {
            return data
        }
        if let value, !value.isEmpty {
            return value
        }
        return []
    }
}

private struct CalendarContainer: Codable, Equatable, Sendable {
    let items: [AthleteWorkoutInstance]?
    let content: [AthleteWorkoutInstance]?
    let workouts: [AthleteWorkoutInstance]?
    let sessions: [AthleteWorkoutInstance]?
    let data: [AthleteWorkoutInstance]?
    let value: [AthleteWorkoutInstance]?
    let days: [CalendarDayContainer]?

    var allWorkouts: [AthleteWorkoutInstance] {
        if let workouts, !workouts.isEmpty {
            return workouts
        }
        if let sessions, !sessions.isEmpty {
            return sessions
        }
        if let items, !items.isEmpty {
            return items
        }
        if let content, !content.isEmpty {
            return content
        }
        if let data, !data.isEmpty {
            return data
        }
        if let value, !value.isEmpty {
            return value
        }
        if let days {
            let flattened = days.flatMap(\.allWorkouts)
            if !flattened.isEmpty {
                return flattened
            }
        }
        return []
    }
}

private struct CalendarDayContainer: Codable, Equatable, Sendable {
    let workouts: [AthleteWorkoutInstance]?
    let sessions: [AthleteWorkoutInstance]?
    let items: [AthleteWorkoutInstance]?

    var allWorkouts: [AthleteWorkoutInstance] {
        if let workouts, !workouts.isEmpty {
            return workouts
        }
        if let sessions, !sessions.isEmpty {
            return sessions
        }
        if let items, !items.isEmpty {
            return items
        }
        return []
    }
}

private struct EnrollmentScheduleContainer: Codable, Equatable, Sendable {
    let enrollmentId: String?
    let workouts: [AthleteWorkoutInstance]?
    let sessions: [AthleteWorkoutInstance]?
    let items: [AthleteWorkoutInstance]?
    let content: [AthleteWorkoutInstance]?
    let data: [AthleteWorkoutInstance]?
    let value: [AthleteWorkoutInstance]?

    var allWorkouts: [AthleteWorkoutInstance] {
        if let workouts, !workouts.isEmpty {
            return workouts
        }
        if let sessions, !sessions.isEmpty {
            return sessions
        }
        if let items, !items.isEmpty {
            return items
        }
        if let content, !content.isEmpty {
            return content
        }
        if let data, !data.isEmpty {
            return data
        }
        if let value, !value.isEmpty {
            return value
        }
        return []
    }
}

private struct ExerciseHistoryContainer: Codable, Equatable, Sendable {
    let exerciseId: String?
    let entries: [AthleteExerciseHistoryEntry]?
    let records: [AthleteExerciseHistoryEntry]?
    let items: [AthleteExerciseHistoryEntry]?
    let content: [AthleteExerciseHistoryEntry]?
    let data: [AthleteExerciseHistoryEntry]?
    let value: [AthleteExerciseHistoryEntry]?

    var allEntries: [AthleteExerciseHistoryEntry] {
        if let entries, !entries.isEmpty {
            return entries
        }
        if let records, !records.isEmpty {
            return records
        }
        if let items, !items.isEmpty {
            return items
        }
        if let content, !content.isEmpty {
            return content
        }
        if let data, !data.isEmpty {
            return data
        }
        if let value, !value.isEmpty {
            return value
        }
        return []
    }
}

private struct PersonalRecordsContainer: Codable, Equatable, Sendable {
    let records: [AthletePersonalRecord]?
    let items: [AthletePersonalRecord]?
    let content: [AthletePersonalRecord]?
    let data: [AthletePersonalRecord]?
    let value: [AthletePersonalRecord]?

    var allRecords: [AthletePersonalRecord] {
        if let records, !records.isEmpty {
            return records
        }
        if let items, !items.isEmpty {
            return items
        }
        if let content, !content.isEmpty {
            return content
        }
        if let data, !data.isEmpty {
            return data
        }
        if let value, !value.isEmpty {
            return value
        }
        return []
    }
}

private struct WorkoutCompleteContainer: Codable, Equatable, Sendable {
    let workout: AthleteWorkoutInstance?
    let item: AthleteWorkoutInstance?
    let data: AthleteWorkoutInstance?
    let value: AthleteWorkoutInstance?
}

private struct SetExecutionUpdateContainer: Codable, Equatable, Sendable {
    let set: AthleteSetExecution?
    let item: AthleteSetExecution?
    let data: AthleteSetExecution?
    let value: AthleteSetExecution?
}

private struct LastPerformanceWrappedContainer: Codable, Equatable, Sendable {
    let lastPerformance: AthleteExerciseLastPerformanceResponse?
    let data: AthleteExerciseLastPerformanceResponse?
    let value: AthleteExerciseLastPerformanceResponse?
}

private extension KeyedDecodingContainer {
    func decodeLossySummary(forKeys keys: [Key]) -> AthleteStatsSummaryPayload? {
        for key in keys {
            if let value = try? decodeIfPresent(AthleteStatsSummaryPayload.self, forKey: key) {
                return value
            }
        }
        return nil
    }

    func decodeLossyString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(UUID.self, forKey: key) {
            return value.uuidString
        }
        return nil
    }

    func decodeLossyString(forKeys keys: [Key]) -> String? {
        for key in keys {
            if let value = decodeLossyString(forKey: key) {
                return value
            }
        }
        return nil
    }

    func decodeLossyInt(forKeys keys: [Key]) -> Int? {
        for key in keys {
            if let value = try? decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            if let value = try? decodeIfPresent(String.self, forKey: key),
               let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                return intValue
            }
            if let value = try? decodeIfPresent(Double.self, forKey: key) {
                return Int(value)
            }
        }
        return nil
    }

    func decodeLossyDouble(forKeys keys: [Key]) -> Double? {
        for key in keys {
            if let value = try? decodeIfPresent(Double.self, forKey: key) {
                return value
            }
            if let value = try? decodeIfPresent(Int.self, forKey: key) {
                return Double(value)
            }
            if let value = try? decodeIfPresent(String.self, forKey: key),
               let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                return parsed
            }
        }
        return nil
    }

    func decodeLossyBool(forKeys keys: [Key]) -> Bool? {
        for key in keys {
            if let value = try? decodeIfPresent(Bool.self, forKey: key) {
                return value
            }
            if let value = try? decodeIfPresent(Int.self, forKey: key) {
                return value != 0
            }
            if let value = try? decodeIfPresent(String.self, forKey: key) {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["true", "1", "yes"].contains(normalized) {
                    return true
                }
                if ["false", "0", "no"].contains(normalized) {
                    return false
                }
            }
        }
        return nil
    }

    func decodeLossyArray<T: Decodable>(forKeys keys: [Key]) -> [T]? {
        for key in keys {
            if let value = try? decodeIfPresent([T].self, forKey: key) {
                return value
            }
        }
        return nil
    }
}
