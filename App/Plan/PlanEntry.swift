import Foundation

enum PlanEntryOwnership: Equatable, Sendable {
    case remoteProgram
    case localProgramOverlay
    case remoteCustom
    case pendingCustom
    case localFreestyle
    case localTemplate

    var isProgram: Bool {
        switch self {
        case .remoteProgram, .localProgramOverlay:
            true
        case .remoteCustom, .pendingCustom, .localFreestyle, .localTemplate:
            false
        }
    }
}

enum PlanEntryDetailsState: Equatable, Sendable {
    case hydrated
    case placeholder
    case missing

    var isHydrated: Bool {
        self == .hydrated
    }

    static func resolve(
        workoutDetails: WorkoutDetailsModel?,
        source: WorkoutSource,
        fallbackTitle: String,
    ) -> Self {
        guard let workoutDetails else { return .missing }

        if !workoutDetails.exercises.isEmpty {
            return .hydrated
        }

        let trimmedCoachNote = workoutDetails.coachNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedCoachNote.isEmpty {
            return .hydrated
        }

        if source == .program, workoutDetails.dayOrder > 0 {
            return .hydrated
        }

        let normalizedTitle = workoutDetails.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFallbackTitle = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedTitle.isEmpty,
           normalizedTitle.caseInsensitiveCompare(normalizedFallbackTitle) != .orderedSame
        {
            return .hydrated
        }

        return .placeholder
    }
}

enum PlanEntrySyncState: Equatable, Sendable {
    case none
    case pendingCreateCustomWorkout(operationId: UUID?)

    var pendingOperationId: UUID? {
        switch self {
        case .none:
            nil
        case .pendingCreateCustomWorkout(let operationId):
            operationId
        }
    }

    var isPendingCreateCustomWorkout: Bool {
        switch self {
        case .none:
            false
        case .pendingCreateCustomWorkout:
            true
        }
    }
}

struct PlanEntryStatus: Equatable, Sendable {
    let canonical: TrainingDayStatus
    let display: TrainingDayStatus
}

struct PlanEntry: Equatable, Sendable, Identifiable {
    let id: String
    let day: Date
    let title: String
    let source: WorkoutSource
    let programId: String?
    let programTitle: String?
    let workoutId: String?
    let workoutDetails: WorkoutDetailsModel?
    let ownership: PlanEntryOwnership
    let detailsState: PlanEntryDetailsState
    let syncState: PlanEntrySyncState
    let status: PlanEntryStatus

    var canonicalStatus: TrainingDayStatus {
        status.canonical
    }

    var displayStatus: TrainingDayStatus {
        status.display
    }
}

extension TrainingDayPlan {
    func asPlanEntry(
        calendar: Calendar = .current,
        now: Date = Date(),
    ) -> PlanEntry {
        let ownership = PlanEntryOwnership.resolve(
            planId: id,
            source: source,
            workoutId: workoutId,
            pendingSyncState: pendingSyncState,
        )
        let syncState = PlanEntrySyncState.resolve(
            pendingSyncState: pendingSyncState,
            pendingSyncOperationId: pendingSyncOperationId,
        )
        let detailsState = PlanEntryDetailsState.resolve(
            workoutDetails: workoutDetails,
            source: source,
            fallbackTitle: title,
        )
        return PlanEntry(
            id: id,
            day: day,
            title: title,
            source: source,
            programId: programId,
            programTitle: programTitle,
            workoutId: workoutId,
            workoutDetails: workoutDetails,
            ownership: ownership,
            detailsState: detailsState,
            syncState: syncState,
            status: PlanEntryStatus(
                canonical: status,
                display: displayStatus(calendar: calendar, now: now)
            ),
        )
    }

    private func displayStatus(calendar: Calendar, now: Date) -> TrainingDayStatus {
        let normalizedDay = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: now)
        if normalizedDay >= today, status.isMissedLike {
            return .planned
        }
        return status
    }
}

private extension PlanEntryOwnership {
    static func resolve(
        planId: String,
        source: WorkoutSource,
        workoutId: String?,
        pendingSyncState: TrainingDayPendingSyncState?,
    ) -> PlanEntryOwnership {
        if pendingSyncState == .createCustomWorkout {
            return .pendingCustom
        }

        switch source {
        case .program:
            return planId.hasPrefix("remote-") ? .remoteProgram : .localProgramOverlay
        case .template:
            return .localTemplate
        case .freestyle:
            let hasWorkoutId = workoutId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            return planId.hasPrefix("remote-") && hasWorkoutId ? .remoteCustom : .localFreestyle
        }
    }
}

private extension PlanEntrySyncState {
    static func resolve(
        pendingSyncState: TrainingDayPendingSyncState?,
        pendingSyncOperationId: UUID?,
    ) -> PlanEntrySyncState {
        switch pendingSyncState {
        case .createCustomWorkout:
            return .pendingCreateCustomWorkout(operationId: pendingSyncOperationId)
        case nil:
            return .none
        }
    }
}
