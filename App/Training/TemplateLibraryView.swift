import Observation
import SwiftUI

@Observable
@MainActor
final class TemplateLibraryViewModel {
    private let userSub: String
    private let trainingStore: TrainingStore

    var templates: [WorkoutTemplateDraft] = []
    var isSaving = false
    var templateName = ""
    var selectedExercises: [TemplateExerciseDraft] = []

    init(userSub: String, trainingStore: TrainingStore = LocalTrainingStore()) {
        self.userSub = userSub
        self.trainingStore = trainingStore
    }

    func onAppear() async {
        await reload()
    }

    func reload() async {
        templates = await trainingStore.templates(userSub: userSub)
    }

    func toggleExercise(_ exercise: TemplateExerciseDraft) {
        if let index = selectedExercises.firstIndex(where: { $0.id == exercise.id }) {
            selectedExercises.remove(at: index)
        } else {
            selectedExercises.append(exercise)
        }
    }

    func saveTemplate() async {
        guard !templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !selectedExercises.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        let template = WorkoutTemplateDraft(
            id: UUID().uuidString,
            userSub: userSub,
            name: templateName.trimmingCharacters(in: .whitespacesAndNewlines),
            exercises: selectedExercises,
            updatedAt: Date(),
        )
        await trainingStore.saveTemplate(template)
        templateName = ""
        selectedExercises = []
        await reload()
    }

    func deleteTemplate(_ id: String) async {
        await trainingStore.deleteTemplate(userSub: userSub, templateId: id)
        await reload()
    }

    func workout(for template: WorkoutTemplateDraft) -> WorkoutDetailsModel {
        let exercises = template.exercises.enumerated().map { index, item in
            WorkoutExercise(
                id: "template-\(template.id)-\(item.id)-\(index)",
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

        return WorkoutDetailsModel.quickWorkout(
            title: "Шаблон: \(template.name)",
            exercises: exercises,
        )
    }
}

struct TemplateLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: TemplateLibraryViewModel
    let onStartTemplate: (WorkoutDetailsModel) -> Void

    private let library: [TemplateExerciseDraft] = [
        .init(id: "sq", name: "Присед со штангой", sets: 4, repsMin: 5, repsMax: 8, restSeconds: 120),
        .init(id: "dl", name: "Становая тяга", sets: 3, repsMin: 4, repsMax: 6, restSeconds: 150),
        .init(id: "bp", name: "Жим лёжа", sets: 4, repsMin: 5, repsMax: 8, restSeconds: 120),
        .init(id: "ohp", name: "Жим стоя", sets: 3, repsMin: 6, repsMax: 10, restSeconds: 90),
        .init(id: "row", name: "Тяга в наклоне", sets: 4, repsMin: 8, repsMax: 12, restSeconds: 90),
        .init(id: "pull", name: "Подтягивания", sets: 4, repsMin: 6, repsMax: 12, restSeconds: 90),
    ]

    var body: some View {
        List {
            Section("Мои шаблоны") {
                if viewModel.templates.isEmpty {
                    Text("Шаблонов пока нет")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }

                ForEach(viewModel.templates) { template in
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text(template.name)
                            .font(FFTypography.body.weight(.semibold))
                        Text("\(template.exercises.count) упражнений")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)

                        HStack(spacing: FFSpacing.sm) {
                            Button("Запустить") {
                                onStartTemplate(viewModel.workout(for: template))
                                dismiss()
                            }
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.accent)

                            Button("Удалить", role: .destructive) {
                                Task { await viewModel.deleteTemplate(template.id) }
                            }
                            .font(FFTypography.caption.weight(.semibold))
                        }
                    }
                    .padding(.vertical, FFSpacing.xs)
                }
            }

            Section("Создать шаблон") {
                FFTextField(
                    label: "Название",
                    placeholder: "Upper A / Push",
                    text: $viewModel.templateName,
                    helperText: "Короткое и понятное имя",
                )

                ForEach(library) { exercise in
                    Button {
                        viewModel.toggleExercise(exercise)
                    } label: {
                        HStack {
                            Text(exercise.name)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textPrimary)
                            Spacer()
                            Image(systemName: viewModel.selectedExercises.contains(where: { $0.id == exercise.id })
                                ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(FFColors.accent)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .buttonStyle(.plain)
                }

                FFButton(title: viewModel.isSaving ? "Сохраняем..." : "Сохранить шаблон", variant: .primary) {
                    Task { await viewModel.saveTemplate() }
                }
                .disabled(viewModel.isSaving)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FFColors.background)
        .navigationTitle("Шаблоны")
        .task { await viewModel.onAppear() }
    }
}

#Preview {
    NavigationStack {
        TemplateLibraryView(
            viewModel: TemplateLibraryViewModel(userSub: "preview"),
            onStartTemplate: { _ in },
        )
    }
}
