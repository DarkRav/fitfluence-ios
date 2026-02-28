import ComposableArchitecture
import SwiftUI

struct WorkoutPlayerView: View {
    let store: StoreOf<WorkoutPlayerFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ScrollView {
                VStack(spacing: FFSpacing.md) {
                    if viewStore.isShowingCachedData {
                        offlineCard
                    }

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
                        topPanel(workout: workout, viewStore: viewStore)

                        if workout.exercises.isEmpty {
                            FFEmptyState(
                                title: "В тренировке нет упражнений",
                                message: "Состав тренировки пока пуст. Вернитесь к программе и выберите другую тренировку.",
                            )
                        } else {
                            exerciseCard(workout: workout, viewStore: viewStore)
                            setsBlock(workout: workout, viewStore: viewStore)
                        }
                    }
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.top, FFSpacing.md)
                .padding(.bottom, FFSpacing.xl)
            }
            .background(FFColors.background)
            .safeAreaInset(edge: .bottom) {
                if let workout = viewStore.workout, !workout.exercises.isEmpty {
                    stickyActions(workout: workout, viewStore: viewStore)
                        .padding(.horizontal, FFSpacing.md)
                        .padding(.top, FFSpacing.xs)
                        .background(FFColors.background.opacity(0.96))
                }
            }
            .navigationBarBackButtonHidden(true)
            .alert(
                "Завершить тренировку?",
                isPresented: viewStore.binding(
                    get: \.isExitConfirmationPresented,
                    send: { isPresented in
                        isPresented ? .exitTapped : .exitConfirmationDismissed
                    },
                ),
            ) {
                Button("Остаться", role: .cancel) {
                    viewStore.send(.exitConfirmationDismissed)
                }
                Button("Выйти", role: .destructive) {
                    viewStore.send(.exitConfirmed)
                }
            } message: {
                Text("Прогресс сохранится на устройстве.")
            }
            .onAppear {
                viewStore.send(.onAppear)
            }
        }
    }

    private var offlineCard: some View {
        FFCard {
            Text("Оффлайн: показаны сохранённые данные")
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.primary)
        }
    }

    private func topPanel(
        workout: WorkoutDetailsModel,
        viewStore: ViewStore<WorkoutPlayerFeature.State, WorkoutPlayerFeature.Action>,
    ) -> some View {
        let total = max(1, workout.exercises.count)
        let current = min(total, viewStore.currentExerciseIndex + 1)

        return FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack(alignment: .top, spacing: FFSpacing.sm) {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text(workout.title)
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)
                            .multilineTextAlignment(.leading)
                        Text("Упражнение \(current) из \(total)")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }

                    Spacer(minLength: FFSpacing.xs)

                    Button("Выйти") {
                        viewStore.send(.exitTapped)
                    }
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.danger)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Выйти из тренировки")
                }

                ProgressView(value: Double(current), total: Double(total))
                    .tint(FFColors.accent)

                Text("Отметьте выполненные подходы")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
            }
        }
    }

    private func exerciseCard(
        workout: WorkoutDetailsModel,
        viewStore: ViewStore<WorkoutPlayerFeature.State, WorkoutPlayerFeature.Action>,
    ) -> some View {
        let exercise = workout.exercises[viewStore.currentExerciseIndex]

        return FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text(exercise.name)
                    .font(FFTypography.h1)
                    .foregroundStyle(FFColors.textPrimary)
                    .multilineTextAlignment(.leading)

                Text(prescriptionText(for: exercise))
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
                    .multilineTextAlignment(.leading)

                if let notes = exercise.notes, !notes.isEmpty {
                    Text(notes)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.gray300)
                }

                if viewStore.progressStorageMode == .localOnly {
                    Text("Оффлайн: изменения сохраняются на устройстве")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.accent)
                }
            }
        }
    }

    private func setsBlock(
        workout: WorkoutDetailsModel,
        viewStore: ViewStore<WorkoutPlayerFeature.State, WorkoutPlayerFeature.Action>,
    ) -> some View {
        let exercise = workout.exercises[viewStore.currentExerciseIndex]
        let progress = viewStore.perExerciseState[exercise.id]

        return FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Подходы")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                ForEach(Array((progress?.sets ?? []).enumerated()), id: \.offset) { index, setState in
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        HStack(spacing: FFSpacing.sm) {
                            Text("Подход \(index + 1)")
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)

                            Spacer(minLength: FFSpacing.xs)

                            Button {
                                viewStore.send(.toggleSetComplete(exerciseId: exercise.id, setIndex: index))
                            } label: {
                                Label(
                                    setState.isCompleted ? "Выполнено" : "Отметить",
                                    systemImage: setState.isCompleted ? "checkmark.circle.fill" : "circle",
                                )
                                .font(FFTypography.caption.weight(.semibold))
                                .foregroundStyle(setState.isCompleted ? FFColors.accent : FFColors.textSecondary)
                            }
                            .frame(minHeight: 44)
                            .accessibilityLabel("Подход \(index + 1)")
                            .accessibilityValue(setState.isCompleted ? "Выполнено" : "Не выполнено")
                        }

                        FFTextField(
                            label: "Вес",
                            placeholder: "кг",
                            text: Binding(
                                get: { setState.weightText },
                                set: { value in
                                    viewStore.send(
                                        .updateSetWeight(exerciseId: exercise.id, setIndex: index, value: value),
                                    )
                                },
                            ),
                            helperText: "Например, 40",
                            keyboardType: .decimalPad,
                        )

                        FFTextField(
                            label: "Повторы",
                            placeholder: "количество",
                            text: Binding(
                                get: { setState.repsText },
                                set: { value in
                                    viewStore.send(
                                        .updateSetReps(exerciseId: exercise.id, setIndex: index, value: value),
                                    )
                                },
                            ),
                            helperText: "Например, 10",
                            keyboardType: .numberPad,
                        )

                        FFTextField(
                            label: "RPE",
                            placeholder: "уровень",
                            text: Binding(
                                get: { setState.rpeText },
                                set: { value in
                                    viewStore.send(
                                        .updateSetRPE(exerciseId: exercise.id, setIndex: index, value: value),
                                    )
                                },
                            ),
                            helperText: "Например, 8",
                            keyboardType: .decimalPad,
                        )
                    }
                    .padding(.vertical, FFSpacing.xs)

                    if index < (progress?.sets.count ?? 0) - 1 {
                        Divider()
                            .overlay(FFColors.gray700)
                    }
                }
            }
        }
    }

    private func stickyActions(
        workout: WorkoutDetailsModel,
        viewStore: ViewStore<WorkoutPlayerFeature.State, WorkoutPlayerFeature.Action>,
    ) -> some View {
        let isFirst = viewStore.currentExerciseIndex == 0
        let isLast = viewStore.currentExerciseIndex >= max(0, workout.exercises.count - 1)

        return FFCard(padding: FFSpacing.sm) {
            VStack(spacing: FFSpacing.sm) {
                HStack(spacing: FFSpacing.sm) {
                    FFButton(
                        title: "Назад",
                        variant: isFirst ? .disabled : .secondary,
                        action: { viewStore.send(.prevExerciseTapped) },
                    )

                    FFButton(
                        title: isLast ? "Завершить тренировку" : "Следующее упражнение",
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
