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
        List {
            Section("Выберите упражнения") {
                ForEach(library) { exercise in
                    Button {
                        toggleExercise(exercise)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.textPrimary)
                                Text("\(exercise.sets) подхода • \(exercise.repsMin)-\(exercise.repsMax) повт")
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: selected
                                .contains(where: { $0.id == exercise.id }) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(FFColors.accent)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if !selected.isEmpty {
                Section("Порядок тренировки") {
                    ForEach(Array(selected.enumerated()), id: \.element.id) { index, item in
                        HStack {
                            Text("\(index + 1). \(item.name)")
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textPrimary)
                            Spacer()
                            Text("\(item.sets)x\(item.repsMin)-\(item.repsMax)")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FFColors.background)
        .navigationTitle("Быстрая тренировка")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Старт") {
                    start()
                }
                .disabled(selected.isEmpty)
            }
        }
    }

    private func toggleExercise(_ exercise: DraftExercise) {
        if let index = selected.firstIndex(where: { $0.id == exercise.id }) {
            selected.remove(at: index)
        } else {
            selected.append(exercise)
        }
    }

    private func start() {
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
