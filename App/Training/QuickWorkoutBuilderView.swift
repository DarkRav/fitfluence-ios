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
                            Text("Выберите упражнения и запустите сессию без лишних шагов.")
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }

                    FFCard {
                        FFTextField(
                            label: "Поиск упражнения",
                            placeholder: "Например, присед или тяга",
                            text: $searchQuery,
                            helperText: "Поиск по встроенной базе",
                        )
                    }

                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.sm) {
                            Text("Выбранные упражнения")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)

                            if selected.isEmpty {
                                Text("Добавьте хотя бы одно упражнение, чтобы начать тренировку.")
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.textSecondary)
                            } else {
                                ForEach(Array(selected.enumerated()), id: \.element.id) { index, exercise in
                                    selectedExerciseRow(index: index, exercise: exercise)
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
                    Text(
                        "\(exercise.sets) подхода • \(exercise.repsMin)-\(exercise.repsMax) повт • отдых \(exercise.restSeconds) сек",
                    )
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
        HStack(spacing: FFSpacing.xs) {
            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                Text("\(index + 1). \(exercise.name)")
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)
                Text("\(exercise.sets)x\(exercise.repsMin)-\(exercise.repsMax) • отдых \(exercise.restSeconds) сек")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
            }
            Spacer()
            HStack(spacing: FFSpacing.xxs) {
                smallIconButton(systemName: "arrow.up") {
                    moveExercise(from: index, to: index - 1)
                }
                .disabled(index == 0)
                smallIconButton(systemName: "arrow.down") {
                    moveExercise(from: index, to: index + 1)
                }
                .disabled(index == selected.count - 1)
                smallIconButton(systemName: "trash", tint: FFColors.danger) {
                    selected.remove(at: index)
                }
            }
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

    private func moveExercise(from source: Int, to destination: Int) {
        guard selected.indices.contains(source), selected.indices.contains(destination),
              source != destination else { return }
        let item = selected.remove(at: source)
        selected.insert(item, at: destination)
    }

    private func toggleExercise(_ exercise: DraftExercise) {
        if let index = selected.firstIndex(where: { $0.id == exercise.id }) {
            selected.remove(at: index)
        } else {
            selected.append(exercise)
        }
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
