import ComposableArchitecture
import SwiftUI

struct WorkoutPlayerView: View {
    let store: StoreOf<WorkoutPlayerFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ScrollView {
                VStack(spacing: FFSpacing.md) {
                    if viewStore.isLoading, viewStore.workout == nil {
                        FFLoadingState(title: "Открываем тренировку")
                    } else if let error = viewStore.error, viewStore.workout == nil {
                        FFErrorState(
                            title: error.title,
                            message: error.message,
                            retryTitle: "Повторить",
                        ) {
                            viewStore.send(.retry)
                        }
                    } else if let workout = viewStore.workout {
                        header(workout: workout, viewStore: viewStore)

                        if workout.exercises.isEmpty {
                            FFEmptyState(
                                title: "В тренировке нет упражнений",
                                message: "Добавьте упражнения в программу, чтобы начать тренировку.",
                            )
                        } else {
                            currentExerciseCard(workout: workout, viewStore: viewStore)
                            controls(workout: workout, viewStore: viewStore)
                        }
                    }
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.md)
            }
            .background(FFColors.background)
            .onAppear {
                viewStore.send(.onAppear)
            }
        }
    }

    private func header(
        workout: WorkoutDetailsModel,
        viewStore: ViewStore<WorkoutPlayerFeature.State, WorkoutPlayerFeature.Action>,
    ) -> some View {
        let total = max(1, workout.exercises.count)
        let current = min(total, viewStore.currentExerciseIndex + 1)

        return FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text(workout.title)
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                Text("Упражнение \(current) из \(total)")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)

                ProgressView(value: Double(current), total: Double(total))
                    .tint(FFColors.accent)

                if viewStore.progressStorageMode == .localOnly {
                    Text("Прогресс пока сохраняется на устройстве.")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    private func currentExerciseCard(
        workout: WorkoutDetailsModel,
        viewStore: ViewStore<WorkoutPlayerFeature.State, WorkoutPlayerFeature.Action>,
    ) -> some View {
        let exercise = workout.exercises[viewStore.currentExerciseIndex]

        return FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text(exercise.name)
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                Text(prescriptionText(for: exercise))
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)

                if let notes = exercise.notes, !notes.isEmpty {
                    Text(notes)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.gray300)
                }

                Divider()
                    .overlay(FFColors.gray700)

                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    Text("Подходы")
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)

                    let progress = viewStore.perExerciseState[exercise.id]
                    ForEach(Array((progress?.sets ?? []).enumerated()), id: \.offset) { index, setState in
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            HStack {
                                Text("Подход \(index + 1)")
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)

                                Spacer()

                                Button(setState.isCompleted ? "Выполнен" : "Отметить") {
                                    viewStore.send(.toggleSetComplete(exerciseId: exercise.id, setIndex: index))
                                }
                                .font(FFTypography.caption.weight(.semibold))
                                .foregroundStyle(setState.isCompleted ? FFColors.accent : FFColors.textSecondary)
                                .frame(minHeight: 44)
                            }

                            FFTextField(
                                label: "Вес (кг)",
                                placeholder: "Например: 40",
                                text: Binding(
                                    get: { setState.weightText },
                                    set: { value in
                                        viewStore.send(
                                            .updateSetWeight(exerciseId: exercise.id, setIndex: index, value: value),
                                        )
                                    },
                                ),
                            )

                            FFTextField(
                                label: "Повторы",
                                placeholder: "Например: 10",
                                text: Binding(
                                    get: { setState.repsText },
                                    set: { value in
                                        viewStore.send(
                                            .updateSetReps(exerciseId: exercise.id, setIndex: index, value: value),
                                        )
                                    },
                                ),
                            )

                            FFTextField(
                                label: "RPE",
                                placeholder: "Например: 8",
                                text: Binding(
                                    get: { setState.rpeText },
                                    set: { value in
                                        viewStore.send(
                                            .updateSetRPE(exerciseId: exercise.id, setIndex: index, value: value),
                                        )
                                    },
                                ),
                            )
                        }
                        .padding(.vertical, FFSpacing.xs)
                    }
                }
            }
        }
    }

    private func controls(
        workout: WorkoutDetailsModel,
        viewStore: ViewStore<WorkoutPlayerFeature.State, WorkoutPlayerFeature.Action>,
    ) -> some View {
        let isFirst = viewStore.currentExerciseIndex == 0
        let isLast = viewStore.currentExerciseIndex >= max(0, workout.exercises.count - 1)

        return VStack(spacing: FFSpacing.sm) {
            HStack(spacing: FFSpacing.sm) {
                FFButton(
                    title: "Назад",
                    variant: isFirst ? .disabled : .secondary,
                    action: { viewStore.send(.prevExerciseTapped) },
                )

                FFButton(
                    title: isLast ? "К завершению" : "Далее",
                    variant: .primary,
                    action: {
                        if isLast {
                            viewStore.send(.finishWorkoutTapped)
                        } else {
                            viewStore.send(.nextExerciseTapped)
                        }
                    },
                )
            }

            FFButton(title: "Завершить тренировку", variant: .destructive) {
                viewStore.send(.finishWorkoutTapped)
            }
        }
    }

    private func prescriptionText(for exercise: WorkoutExercise) -> String {
        let repsPart = if let min = exercise.repsMin, let max = exercise.repsMax {
            "\(min)-\(max) повторов"
        } else if let min = exercise.repsMin {
            "\(min) повторов"
        } else {
            "повторы не указаны"
        }

        let rpePart = exercise.targetRpe.map { "RPE \($0)" } ?? "RPE не указан"
        let restPart = exercise.restSeconds.map { "Отдых \($0) сек" } ?? "Отдых по самочувствию"
        return "\(exercise.sets) подходов • \(repsPart) • \(rpePart) • \(restPart)"
    }
}
