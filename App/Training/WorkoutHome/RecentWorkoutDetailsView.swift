import SwiftUI

struct RecentWorkoutDetailsView: View {
    let record: CompletedWorkoutRecord
    let onRepeat: () -> Void
    private let progressStore: WorkoutProgressStore

    @State private var snapshot: WorkoutProgressSnapshot?
    @State private var isLoadingDetails = false

    init(
        record: CompletedWorkoutRecord,
        onRepeat: @escaping () -> Void,
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
    ) {
        self.record = record
        self.onRepeat = onRepeat
        self.progressStore = progressStore
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

                        metricRow(title: "Длительность", value: formattedDuration(record.durationSeconds))
                        metricRow(title: "Подходы", value: "\(record.completedSets) из \(max(record.totalSets, record.completedSets))")
                        metricRow(title: "Общий объём", value: "\(formattedVolume(record.volume)) кг")

                        if let overallRPE = record.overallRPE {
                            metricRow(title: "Субъективная нагрузка", value: "\(overallRPE)")
                        }
                    }
                }

                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Подходы и веса")
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
                        } else if !hasAccurateSnapshot {
                            Text("Подробные подходы доступны только для последнего сохранённого выполнения этой тренировки")
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
                        onRepeat()
                    }
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
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

    private var detailedExercises: [ExerciseSetDetails] {
        guard hasAccurateSnapshot, let workoutDetails = snapshot?.workoutDetails else { return [] }
        let stored = snapshot?.exercises ?? [:]

        return workoutDetails.exercises
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .compactMap { exercise in
                let sets = (stored[exercise.id]?.sets ?? [])
                    .enumerated()
                    .compactMap { index, set -> SetLine? in
                        let reps = trimmed(set.repsText)
                        let weight = trimmed(set.weightText)
                        let rpe = trimmed(set.rpeText)
                        let hasData = set.isCompleted || reps != nil || weight != nil || rpe != nil
                        guard hasData else { return nil }

                        let repsLabel = reps ?? "—"
                        let weightLabel = weight ?? "—"
                        let rpeSuffix = rpe.map { " • нагрузка \($0)" } ?? ""
                        let line = "\(repsLabel) повт • \(weightLabel) кг\(rpeSuffix)"
                        return SetLine(index: index + 1, valueLine: line)
                    }

                guard !sets.isEmpty else { return nil }
                return ExerciseSetDetails(id: exercise.id, name: exercise.name, sets: sets)
            }
    }

    private func loadSnapshot() async {
        isLoadingDetails = true
        snapshot = await progressStore.load(
            userSub: record.userSub,
            programId: record.programId,
            workoutId: record.workoutId,
        )
        isLoadingDetails = false
    }

    private var hasAccurateSnapshot: Bool {
        guard let snapshot else { return false }
        let delta = abs(snapshot.lastUpdated.timeIntervalSince(record.finishedAt))
        return delta <= 60 * 60 * 6
    }

    private func trimmed(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private var canRepeatWorkout: Bool {
        record.source != .program
    }
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
                notes: "Отличное самочувствие",
                overallRPE: 7,
            ),
            onRepeat: {},
        )
    }
}
