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

    func savePreset(_ template: WorkoutTemplateDraft) async {
        let userTemplate = WorkoutTemplateDraft(
            id: UUID().uuidString,
            userSub: userSub,
            name: template.name,
            exercises: template.exercises,
            updatedAt: Date(),
        )
        await trainingStore.saveTemplate(userTemplate)
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
    private enum SectionMode: String, CaseIterable, Identifiable {
        case mine = "Мои"
        case ready = "Готовые"

        var id: String {
            rawValue
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State var viewModel: TemplateLibraryViewModel
    @State private var sectionMode: SectionMode = .mine
    let onStartTemplate: (WorkoutDetailsModel) -> Void

    private let library: [TemplateExerciseDraft] = [
        .init(id: "sq", name: "Присед со штангой", sets: 4, repsMin: 5, repsMax: 8, restSeconds: 120),
        .init(id: "dl", name: "Становая тяга", sets: 3, repsMin: 4, repsMax: 6, restSeconds: 150),
        .init(id: "bp", name: "Жим лёжа", sets: 4, repsMin: 5, repsMax: 8, restSeconds: 120),
        .init(id: "ohp", name: "Жим стоя", sets: 3, repsMin: 6, repsMax: 10, restSeconds: 90),
        .init(id: "row", name: "Тяга в наклоне", sets: 4, repsMin: 8, repsMax: 12, restSeconds: 90),
        .init(id: "pull", name: "Подтягивания", sets: 4, repsMin: 6, repsMax: 12, restSeconds: 90),
        .init(id: "legpress", name: "Жим ногами", sets: 4, repsMin: 10, repsMax: 15, restSeconds: 75),
    ]

    var body: some View {
        ZStack {
            FFColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: FFSpacing.md) {
                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text("Шаблоны тренировок")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)
                            Text("Создавайте свои схемы и запускайте их одним касанием.")
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }

                    Picker("Раздел", selection: $sectionMode) {
                        ForEach(SectionMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, FFSpacing.xs)

                    if sectionMode == .mine {
                        myTemplatesSection
                        createTemplateSection
                    } else {
                        readyTemplatesSection
                    }
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.md)
            }
        }
        .navigationTitle("Шаблоны")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Закрыть") {
                    dismiss()
                }
                .font(FFTypography.body.weight(.semibold))
                .foregroundStyle(FFColors.textSecondary)
            }
        }
        .tint(FFColors.accent)
        .task { await viewModel.onAppear() }
    }

    private var myTemplatesSection: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Мои шаблоны")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                if viewModel.templates.isEmpty {
                    Text("У вас пока нет шаблонов. Создайте первый ниже.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                } else {
                    ForEach(viewModel.templates) { template in
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text(template.name)
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                            Text(summaryText(for: template.exercises))
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)

                            HStack(spacing: FFSpacing.sm) {
                                FFButton(title: "Старт", variant: .primary) {
                                    onStartTemplate(viewModel.workout(for: template))
                                    dismiss()
                                }
                                .accessibilityLabel("Запустить шаблон \(template.name)")

                                FFButton(title: "Удалить", variant: .destructive) {
                                    Task { await viewModel.deleteTemplate(template.id) }
                                }
                                .accessibilityLabel("Удалить шаблон \(template.name)")
                            }
                        }
                        if template.id != viewModel.templates.last?.id {
                            Divider()
                                .background(FFColors.gray700)
                        }
                    }
                }
            }
        }
    }

    private var createTemplateSection: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Создать шаблон")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                FFTextField(
                    label: "Название",
                    placeholder: "Upper A / Push",
                    text: $viewModel.templateName,
                    helperText: "Короткое и понятное имя",
                )

                ForEach(library) { exercise in
                    let isSelected = viewModel.selectedExercises.contains(where: { $0.id == exercise.id })
                    Button {
                        viewModel.toggleExercise(exercise)
                    } label: {
                        HStack(spacing: FFSpacing.sm) {
                            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                Text(exercise.name)
                                    .font(FFTypography.body.weight(.semibold))
                                    .foregroundStyle(FFColors.textPrimary)
                                Text(
                                    "\(exercise.sets)x\(exercise.repsMin)-\(exercise.repsMax) • отдых \(exercise.restSeconds) сек",
                                )
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                            }
                            Spacer()
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

                FFButton(title: viewModel.isSaving ? "Сохраняем..." : "Сохранить шаблон", variant: .primary) {
                    Task { await viewModel.saveTemplate() }
                }
                .disabled(viewModel.isSaving)
            }
        }
    }

    private var readyTemplatesSection: some View {
        let templates = builtInTemplates
        return FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Готовые пресеты")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                ForEach(templates) { template in
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text(template.name)
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                        Text(summaryText(for: template.exercises))
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)

                        HStack(spacing: FFSpacing.sm) {
                            FFButton(title: "Старт", variant: .primary) {
                                onStartTemplate(viewModel.workout(for: template))
                                dismiss()
                            }
                            .accessibilityLabel("Запустить пресет \(template.name)")

                            FFButton(title: "Сохранить в мои", variant: .secondary) {
                                Task { await viewModel.savePreset(template) }
                            }
                            .accessibilityLabel("Сохранить пресет \(template.name) в мои шаблоны")
                        }
                    }

                    if template.id != templates.last?.id {
                        Divider()
                            .background(FFColors.gray700)
                    }
                }
            }
        }
    }

    private var builtInTemplates: [WorkoutTemplateDraft] {
        [
            WorkoutTemplateDraft(
                id: "preset-upper-lower",
                userSub: "preset",
                name: "Upper / Lower",
                exercises: [
                    .init(id: "bp", name: "Жим лёжа", sets: 4, repsMin: 5, repsMax: 8, restSeconds: 120),
                    .init(id: "row", name: "Тяга в наклоне", sets: 4, repsMin: 8, repsMax: 12, restSeconds: 90),
                    .init(id: "sq", name: "Присед со штангой", sets: 4, repsMin: 5, repsMax: 8, restSeconds: 120),
                    .init(id: "dl", name: "Становая тяга", sets: 3, repsMin: 4, repsMax: 6, restSeconds: 150),
                ],
                updatedAt: Date(),
            ),
            WorkoutTemplateDraft(
                id: "preset-ppl",
                userSub: "preset",
                name: "Push / Pull / Legs",
                exercises: [
                    .init(id: "ohp", name: "Жим стоя", sets: 4, repsMin: 6, repsMax: 10, restSeconds: 90),
                    .init(id: "pull", name: "Подтягивания", sets: 4, repsMin: 6, repsMax: 12, restSeconds: 90),
                    .init(id: "legpress", name: "Жим ногами", sets: 4, repsMin: 10, repsMax: 15, restSeconds: 75),
                ],
                updatedAt: Date(),
            ),
        ]
    }

    private func summaryText(for exercises: [TemplateExerciseDraft]) -> String {
        let estimatedDuration = max(15, exercises.reduce(0) { $0 + max(1, $1.sets) * 2 })
        return "\(exercises.count) упражнений • ~\(estimatedDuration) мин"
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
