import SwiftUI

struct RecentWorkoutDetailsView: View {
    let record: CompletedWorkoutRecord
    let onRepeat: (WorkoutDetailsModel?) -> Void
    private let progressStore: WorkoutProgressStore
    private let athleteTrainingClient: AthleteTrainingClientProtocol?

    @State private var snapshot: WorkoutProgressSnapshot?
    @State private var isLoadingDetails = false

    init(
        record: CompletedWorkoutRecord,
        onRepeat: @escaping (WorkoutDetailsModel?) -> Void,
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
        athleteTrainingClient: AthleteTrainingClientProtocol? = nil,
    ) {
        self.record = record
        self.onRepeat = onRepeat
        self.progressStore = progressStore
        self.athleteTrainingClient = athleteTrainingClient
    }

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text(record.workoutTitle)
                            .font(FFTypography.h1)
                            .foregroundStyle(FFColors.textPrimary)
                            .lineLimit(3)

                        Text("\(formattedDate) • \(sourceTitle)")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }

                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Сводка")
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)

                        metricRow(title: "Длительность", value: formattedDuration(resolvedDurationSeconds))
                        metricRow(title: "Подходы", value: "\(resolvedSummary.completedSets) из \(resolvedSummary.totalSets)")
                        metricRow(title: "Общий объём", value: "\(formattedVolume(resolvedSummary.volume)) кг")

                        if let overallRPE = resolvedSummary.overallRPE {
                            metricRow(title: "Субъективная нагрузка", value: "\(overallRPE)")
                        }
                    }
                }

                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Подходы по упражнениям")
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)

                        if isLoadingDetails {
                            HStack(spacing: FFSpacing.xs) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(FFColors.accent)
                                Text("Загружаем детали тренировки")
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                        } else if !hasMatchingSnapshot {
                            Text("Подробные подходы не найдены для этого выполнения тренировки")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                        } else if detailedExercises.isEmpty {
                            Text("Детальные подходы не сохранены для этой тренировки")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                        } else {
                            ForEach(Array(detailedExercises.enumerated()), id: \.element.id) { sectionIndex, exercise in
                                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                                    Text(exercise.name)
                                        .font(FFTypography.body.weight(.semibold))
                                        .foregroundStyle(FFColors.textPrimary)

                                    ForEach(exercise.sets) { set in
                                        HStack(alignment: .firstTextBaseline, spacing: FFSpacing.xs) {
                                            Text("Подход \(set.index)")
                                                .font(FFTypography.caption)
                                                .foregroundStyle(FFColors.textSecondary)

                                            Spacer(minLength: FFSpacing.xs)

                                            Text(set.valueLine)
                                                .font(FFTypography.body.weight(.semibold))
                                                .foregroundStyle(FFColors.textPrimary)
                                        }
                                    }
                                }

                                if sectionIndex < detailedExercises.count - 1 {
                                    Rectangle()
                                        .fill(FFColors.gray700)
                                        .frame(height: 1)
                                        .padding(.vertical, FFSpacing.xxs)
                                }
                            }
                        }
                    }
                }

                if let notes = trimmedNotes {
                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text("Заметки")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)

                            Text(notes)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }
                }

                if canRepeatWorkout {
                    FFButton(title: "Повторить тренировку", variant: .secondary) {
                        onRepeat(snapshot?.workoutDetails)
                    }
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .ffScreenBackground()
        .navigationTitle("Тренировка")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: record.id) {
            await loadSnapshot()
        }
    }

    private var formattedDate: String {
        record.finishedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var sourceTitle: String {
        switch record.source {
        case .program:
            return "программа"
        case .freestyle:
            return "быстрая тренировка"
        case .template:
            return "шаблон"
        }
    }

    private var trimmedNotes: String? {
        guard let notes = record.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else {
            return nil
        }
        return notes
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FFSpacing.xs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)

            Spacer(minLength: FFSpacing.xs)

            Text(value)
                .font(FFTypography.body.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let totalSeconds = max(0, seconds)
        let minutes = totalSeconds / 60
        if minutes > 0 {
            return "\(minutes) мин"
        }
        return "\(totalSeconds) сек"
    }

    private func formattedVolume(_ volume: Double) -> String {
        if floor(volume) == volume {
            return "\(Int(volume))"
        }
        return String(format: "%.1f", volume)
    }

    private var resolvedDurationSeconds: Int {
        if record.durationSeconds > 0 {
            return record.durationSeconds
        }

        guard let snapshot, let startedAt = snapshot.startedAt else {
            return 0
        }
        return max(0, Int(snapshot.lastUpdated.timeIntervalSince(startedAt)))
    }

    private var resolvedSummary: SummaryMetrics {
        let fallback = SummaryMetrics(
            completedSets: record.completedSets,
            totalSets: max(record.totalSets, record.completedSets),
            volume: record.volume,
            overallRPE: record.overallRPE,
        )

        guard let derived = derivedSummary else {
            return fallback
        }

        return SummaryMetrics(
            completedSets: fallback.totalSets > 0 || fallback.completedSets > 0 ? fallback.completedSets : derived.completedSets,
            totalSets: fallback.totalSets > 0 || fallback.completedSets > 0 ? fallback.totalSets : derived.totalSets,
            volume: fallback.volume > 0 ? fallback.volume : derived.volume,
            overallRPE: fallback.overallRPE ?? derived.overallRPE,
        )
    }

    private var derivedSummary: SummaryMetrics? {
        guard hasMatchingSnapshot, let snapshot, !snapshot.exercises.isEmpty else { return nil }

        let completedSets = snapshot.exercises.values
            .flatMap(\.sets)
            .filter(\.isCompleted)
        let totalSets = snapshot.workoutDetails?.exercises.reduce(0) { partial, exercise in
            partial + max(1, exercise.sets)
        } ?? snapshot.exercises.values.reduce(0) { partial, exercise in
            partial + exercise.sets.count
        }
        let volume = completedSets.reduce(0.0) { partial, set in
            let reps = Double(set.repsText) ?? 0
            let weight = Double(set.weightText) ?? 0
            return partial + reps * weight
        }
        let rpeValues = completedSets.compactMap { Int($0.rpeText) }
        let overallRPE = rpeValues.isEmpty ? nil : Int(round(Double(rpeValues.reduce(0, +)) / Double(rpeValues.count)))

        return SummaryMetrics(
            completedSets: completedSets.count,
            totalSets: max(totalSets, completedSets.count),
            volume: volume,
            overallRPE: overallRPE,
        )
    }

    private var detailedExercises: [ExerciseSetDetails] {
        guard hasMatchingSnapshot, let workoutDetails = snapshot?.workoutDetails else { return [] }
        let stored = snapshot?.exercises ?? [:]

        return workoutDetails.exercises
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .compactMap { exercise in
                let isBodyweight = exercise.isBodyweight
                let sets = (stored[exercise.id]?.sets ?? [])
                    .enumerated()
                    .compactMap { index, set -> SetLine? in
                        let reps = trimmed(set.repsText)
                        let weight = trimmed(set.weightText)
                        let rpe = trimmed(set.rpeText)
                        let hasData = set.isCompleted || reps != nil || weight != nil || rpe != nil
                        guard hasData else { return nil }

                        let line = WorkoutExerciseDisplayFormatting.setLine(
                            repsText: reps,
                            weightText: weight,
                            rpeText: rpe,
                            isBodyweight: isBodyweight,
                        )
                        return SetLine(index: index + 1, valueLine: line)
                    }

                guard !sets.isEmpty else { return nil }
                return ExerciseSetDetails(id: exercise.id, name: exercise.name, sets: sets)
            }
    }

    private func loadSnapshot() async {
        isLoadingDetails = true
        defer { isLoadingDetails = false }

        if let loadedSnapshot = await progressStore.load(
            userSub: record.userSub,
            programId: record.programId,
            workoutId: record.workoutId,
        ) {
            snapshot = loadedSnapshot
            return
        }

        if record.source != .template,
           let athleteTrainingClient,
           case let .success(detailsResponse) = await athleteTrainingClient.getWorkoutDetails(workoutInstanceId: record.workoutId)
        {
            let remoteSnapshot = detailsResponse.asWorkoutProgressSnapshot(
                userSub: record.userSub,
                fallbackProgramId: record.programId,
                fallbackStartedAt: record.startedAt,
                fallbackFinishedAt: record.finishedAt,
            )
            snapshot = remoteSnapshot
            await progressStore.save(remoteSnapshot)
            return
        }

        if let workoutDetails = record.workoutDetails {
            snapshot = WorkoutProgressSnapshot(
                userSub: record.userSub,
                programId: record.programId,
                workoutId: record.workoutId,
                currentExerciseIndex: nil,
                startedAt: record.startedAt,
                source: record.source,
                workoutDetails: workoutDetails,
                hasLocalOnlyStructuralChanges: false,
                isFinished: true,
                lastUpdated: record.finishedAt,
                exercises: [:]
            )
            return
        }

        snapshot = nil
    }

    private var hasMatchingSnapshot: Bool {
        guard let snapshot else { return false }
        guard snapshot.isFinished else { return false }

        if let snapshotStartedAt = snapshot.startedAt {
            let startedDelta = abs(snapshotStartedAt.timeIntervalSince(record.startedAt))
            if startedDelta <= 60 * 10 {
                return true
            }
        }

        let finishedDelta = abs(snapshot.lastUpdated.timeIntervalSince(record.finishedAt))
        return finishedDelta <= 60 * 15
    }

    private func trimmed(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private var canRepeatWorkout: Bool {
        record.source != .program && (record.workoutDetails != nil || snapshot?.workoutDetails != nil)
    }
}

private struct SummaryMetrics {
    let completedSets: Int
    let totalSets: Int
    let volume: Double
    let overallRPE: Int?
}

private struct ExerciseSetDetails: Identifiable {
    let id: String
    let name: String
    let sets: [SetLine]
}

private struct SetLine: Identifiable {
    let index: Int
    let valueLine: String

    var id: Int { index }
}

#Preview("Детали завершенной") {
    NavigationStack {
        RecentWorkoutDetailsView(
            record: CompletedWorkoutRecord(
                id: "preview",
                userSub: "preview",
                programId: "program",
                workoutId: "workout",
                workoutTitle: "Домашняя силовая",
                source: .program,
                startedAt: Date().addingTimeInterval(-2_400),
                finishedAt: Date(),
                durationSeconds: 2_400,
                completedSets: 14,
                totalSets: 16,
                volume: 1_560,
                workoutDetails: nil,
                notes: "Отличное самочувствие",
                overallRPE: 7,
            ),
            onRepeat: { _ in },
        )
    }
}
