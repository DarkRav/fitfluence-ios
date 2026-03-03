import SwiftUI

struct QuickWorkoutBuilderView: View {
    struct DraftExercise: Identifiable, Equatable {
        let id: String
        let name: String
        var sets: Int
        var repsMin: Int
        var repsMax: Int
        var restSeconds: Int
    }

    @Environment(\.dismiss) private var dismiss
    @State private var selected: [DraftExercise] = []
    @State private var searchQuery = ""

    let onStart: (WorkoutDetailsModel) -> Void

    private let library: [DraftExercise] = [
        .init(id: "sq", name: "Присед со штангой", sets: 4, repsMin: 5, repsMax: 8, restSeconds: 120),
        .init(id: "bp", name: "Жим лёжа", sets: 4, repsMin: 5, repsMax: 8, restSeconds: 120),
        .init(id: "dl", name: "Тяга штанги", sets: 3, repsMin: 6, repsMax: 10, restSeconds: 90),
        .init(id: "ohp", name: "Жим стоя", sets: 3, repsMin: 6, repsMax: 10, restSeconds: 90),
        .init(id: "pull", name: "Подтягивания", sets: 3, repsMin: 6, repsMax: 12, restSeconds: 90),
        .init(id: "legpress", name: "Жим ногами", sets: 3, repsMin: 10, repsMax: 15, restSeconds: 75),
    ]

    var body: some View {
        ZStack {
            FFColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: FFSpacing.md) {
                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text("Соберите тренировку за минуту")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)
                            Text("Добавьте упражнения, настройте параметры и запускайте тренировку.")
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }

                    FFCard {
                        FFTextField(
                            label: "Поиск упражнения",
                            placeholder: "Например, присед или тяга",
                            text: $searchQuery,
                            helperText: "Выберите упражнения для своей сессии",
                        )
                    }

                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.sm) {
                            Text("Выбранные упражнения")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)
                            Text("Порядок выполнения: сверху вниз")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)

                            if selected.isEmpty {
                                Text("Добавьте хотя бы одно упражнение, чтобы начать тренировку.")
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.textSecondary)
                            } else {
                                ForEach(Array(selected.enumerated()), id: \.element.id) { index, exercise in
                                    selectedExerciseRow(index: index, exercise: exercise)
                                        .dropDestination(for: String.self) { items, _ in
                                            guard let draggedId = items.first else { return false }
                                            return reorderSelected(draggedId: draggedId, targetId: exercise.id)
                                        }
                                }
                            }
                        }
                    }

                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.sm) {
                            Text("Каталог упражнений")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)

                            ForEach(filteredLibrary) { exercise in
                                libraryExerciseRow(exercise)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
        }
        .navigationTitle("Быстрая тренировка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Закрыть") {
                    dismiss()
                }
                .font(FFTypography.body.weight(.semibold))
                .foregroundStyle(FFColors.textSecondary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Старт") {
                    start()
                }
                .disabled(selected.isEmpty)
                .font(FFTypography.body.weight(.semibold))
                .foregroundStyle(selected.isEmpty ? FFColors.gray500 : FFColors.accent)
            }
        }
        .tint(FFColors.accent)
    }

    private var filteredLibrary: [DraftExercise] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return library }
        return library.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var bottomActionBar: some View {
        VStack(spacing: FFSpacing.xs) {
            FFButton(title: selected.isEmpty ? "Добавьте упражнение" : "Начать тренировку", variant: .primary) {
                start()
            }
            .disabled(selected.isEmpty)
            .accessibilityLabel("Начать быструю тренировку")
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.top, FFSpacing.xs)
        .padding(.bottom, FFSpacing.sm)
        .background(FFColors.background.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FFColors.gray700.opacity(0.6))
                .frame(height: 1)
        }
    }

    private func libraryExerciseRow(_ exercise: DraftExercise) -> some View {
        let isSelected = selected.contains(where: { $0.id == exercise.id })
        return Button {
            toggleExercise(exercise)
        } label: {
            HStack(spacing: FFSpacing.sm) {
                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text(exercise.name)
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                    Text(exerciseDescription(
                        sets: exercise.sets,
                        repsMin: exercise.repsMin,
                        repsMax: exercise.repsMax,
                        restSeconds: exercise.restSeconds,
                    ))
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                }
                Spacer(minLength: FFSpacing.sm)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? FFColors.accent : FFColors.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .padding(.vertical, FFSpacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(exercise.name), \(isSelected ? "добавлено" : "добавить")")
    }

    private func selectedExerciseRow(index: Int, exercise: DraftExercise) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            HStack(spacing: FFSpacing.xs) {
                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text("\(index + 1). \(exercise.name)")
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                    Text(exerciseDescription(
                        sets: exercise.sets,
                        repsMin: exercise.repsMin,
                        repsMax: exercise.repsMax,
                        restSeconds: exercise.restSeconds,
                    ))
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                }
                Spacer()
                HStack(spacing: FFSpacing.xxs) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FFColors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(FFColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                                .stroke(FFColors.gray700, lineWidth: 1)
                        }
                        .draggable(exercise.id)
                        .accessibilityLabel("Перетащите, чтобы изменить порядок упражнения")
                    smallIconButton(systemName: "trash", tint: FFColors.danger) {
                        selected.remove(at: index)
                    }
                }
            }

            VStack(spacing: FFSpacing.xs) {
                numericControlRow(
                    title: "Подходы",
                    value: exercise.sets,
                    onDecrement: { updateExercise(at: index) { $0.sets = max(1, $0.sets - 1) } },
                    onIncrement: { updateExercise(at: index) { $0.sets = min(12, $0.sets + 1) } },
                )
                numericControlRow(
                    title: "Повторы (мин)",
                    value: exercise.repsMin,
                    onDecrement: {
                        updateExercise(at: index) {
                            $0.repsMin = max(1, $0.repsMin - 1)
                            if $0.repsMax < $0.repsMin { $0.repsMax = $0.repsMin }
                        }
                    },
                    onIncrement: {
                        updateExercise(at: index) {
                            $0.repsMin = min(30, $0.repsMin + 1)
                            if $0.repsMax < $0.repsMin { $0.repsMax = $0.repsMin }
                        }
                    },
                )
                numericControlRow(
                    title: "Повторы (макс)",
                    value: exercise.repsMax,
                    onDecrement: {
                        updateExercise(at: index) {
                            $0.repsMax = max($0.repsMin, $0.repsMax - 1)
                        }
                    },
                    onIncrement: {
                        updateExercise(at: index) {
                            $0.repsMax = min(40, $0.repsMax + 1)
                        }
                    },
                )
                numericControlRow(
                    title: "Отдых (сек)",
                    value: exercise.restSeconds,
                    onDecrement: { updateExercise(at: index) { $0.restSeconds = max(0, $0.restSeconds - 15) } },
                    onIncrement: { updateExercise(at: index) { $0.restSeconds = min(600, $0.restSeconds + 15) } },
                )
            }
        }
        .padding(.vertical, FFSpacing.xs)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FFColors.gray700.opacity(0.5))
                .frame(height: 1)
                .offset(y: FFSpacing.xs)
        }
    }

    private func numericControlRow(
        title: String,
        value: Int,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void,
    ) -> some View {
        HStack(spacing: FFSpacing.xs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
            Spacer()
            smallIconButton(systemName: "minus", action: onDecrement)
            Text("\(value)")
                .font(FFTypography.body.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .frame(minWidth: 40)
                .multilineTextAlignment(.center)
            smallIconButton(systemName: "plus", action: onIncrement)
        }
    }

    private func smallIconButton(systemName: String, tint: Color = FFColors.textSecondary, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(tint)
                .background(FFColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                        .stroke(FFColors.gray700, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func reorderSelected(draggedId: String, targetId: String) -> Bool {
        guard draggedId != targetId,
              let from = selected.firstIndex(where: { $0.id == draggedId }),
              let to = selected.firstIndex(where: { $0.id == targetId })
        else { return false }

        let item = selected.remove(at: from)
        let destination = from < to ? to - 1 : to
        selected.insert(item, at: destination)
        return true
    }

    private func toggleExercise(_ exercise: DraftExercise) {
        if let index = selected.firstIndex(where: { $0.id == exercise.id }) {
            selected.remove(at: index)
        } else {
            selected.append(exercise)
        }
    }

    private func updateExercise(at index: Int, mutate: (inout DraftExercise) -> Void) {
        guard selected.indices.contains(index) else { return }
        var item = selected[index]
        mutate(&item)
        selected[index] = item
    }

    private func exerciseDescription(sets: Int, repsMin: Int, repsMax: Int, restSeconds: Int) -> String {
        "\(sets) подхода • \(repsMin)-\(repsMax) повторов • отдых \(restSeconds) сек"
    }

    private func start() {
        guard !selected.isEmpty else { return }
        let exercises = selected.enumerated().map { index, item in
            WorkoutExercise(
                id: "quick-\(item.id)-\(index)",
                name: item.name,
                sets: item.sets,
                repsMin: item.repsMin,
                repsMax: item.repsMax,
                targetRpe: nil,
                restSeconds: item.restSeconds,
                notes: nil,
                orderIndex: index,
            )
        }

        let workout = WorkoutDetailsModel.quickWorkout(
            title: "Quick workout • \(Date().formatted(date: .omitted, time: .shortened))",
            exercises: exercises,
        )
        onStart(workout)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        QuickWorkoutBuilderView(onStart: { _ in })
    }
}
