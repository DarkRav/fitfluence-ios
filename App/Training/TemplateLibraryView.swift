import Observation
import SwiftUI

@Observable
@MainActor
final class TemplateLibraryViewModel {
    private let userSub: String
    private let templateRepository: any WorkoutTemplateRepository

    var templates: [WorkoutTemplateDraft] = []
    var isSaving = false
    var templateName = ""
    var selectedExercises: [TemplateExerciseDraft] = []
    var errorMessage: String?

    init(
        userSub: String,
        templateRepository: any WorkoutTemplateRepository = LocalWorkoutTemplateRepository(),
    ) {
        self.userSub = userSub
        self.templateRepository = templateRepository
    }

    var currentUserSub: String {
        userSub
    }

    func onAppear() async {
        await reload()
    }

    func reload() async {
        templates = await templateRepository.templates(userSub: userSub)
    }

    func toggleExercise(_ exercise: TemplateExerciseDraft) {
        if let index = selectedExercises.firstIndex(where: { $0.id == exercise.id }) {
            selectedExercises.remove(at: index)
        } else {
            selectedExercises.append(exercise)
        }
    }

    func updateSelectedExercise(_ exercise: TemplateExerciseDraft) {
        guard let index = selectedExercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        selectedExercises[index] = exercise
    }

    func removeSelectedExercise(id: String) {
        selectedExercises.removeAll { $0.id == id }
    }

    func saveTemplate() async {
        guard !templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !selectedExercises.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let template = WorkoutTemplateDraft(
            id: "new-\(UUID().uuidString)",
            userSub: userSub,
            name: templateName.trimmingCharacters(in: .whitespacesAndNewlines),
            exercises: selectedExercises,
            updatedAt: Date(),
        )
        do {
            _ = try await templateRepository.saveTemplate(template)
            templateName = ""
            selectedExercises = []
            await reload()
        } catch {
            errorMessage = error.userFacingTemplateLibraryMessage
        }
    }

    func saveTemplate(_ template: WorkoutTemplateDraft) async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            _ = try await templateRepository.saveTemplate(template)
            await reload()
        } catch {
            errorMessage = error.userFacingTemplateLibraryMessage
        }
    }

    func savePreset(_ template: WorkoutTemplateDraft) async {
        let userTemplate = WorkoutTemplateDraft(
            id: "new-\(UUID().uuidString)",
            userSub: userSub,
            name: template.name,
            exercises: template.exercises,
            updatedAt: Date(),
        )
        errorMessage = nil
        do {
            _ = try await templateRepository.saveTemplate(userTemplate)
            await reload()
        } catch {
            errorMessage = error.userFacingTemplateLibraryMessage
        }
    }

    func updateTemplate(id: String, name: String, exercises: [TemplateExerciseDraft]) async {
        let updated = WorkoutTemplateDraft(
            id: id,
            userSub: userSub,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            exercises: exercises,
            updatedAt: Date(),
        )
        errorMessage = nil
        do {
            _ = try await templateRepository.saveTemplate(updated)
            await reload()
        } catch {
            errorMessage = error.userFacingTemplateLibraryMessage
        }
    }

    func deleteTemplate(_ id: String) async {
        errorMessage = nil
        do {
            try await templateRepository.deleteTemplate(userSub: userSub, templateId: id)
            await reload()
        } catch {
            errorMessage = error.userFacingTemplateLibraryMessage
        }
    }

    func workout(for template: WorkoutTemplateDraft) -> WorkoutDetailsModel {
        let exercises = template.exercises.enumerated().map { index, item in
            WorkoutExercise(
                id: item.id,
                name: item.name,
                sets: item.sets,
                repsMin: item.repsMin,
                repsMax: item.repsMax,
                targetRpe: item.targetRpe,
                restSeconds: item.restSeconds,
                notes: item.notes,
                orderIndex: index,
            )
        }

        return WorkoutDetailsModel.quickWorkout(
            title: template.name,
            exercises: exercises,
        )
    }
}

private extension Error {
    var userFacingTemplateLibraryMessage: String {
        if let apiError = self as? APIError {
            switch apiError {
            case .offline:
                return "Нет сети. Не удалось синхронизировать шаблон с backend."
            case .unauthorized:
                return "Сессия истекла. Не удалось синхронизировать шаблон."
            case .forbidden:
                return "Backend отклонил доступ к athlete templates."
            case let .httpError(statusCode, _):
                return "Backend athlete templates вернул ошибку \(statusCode)."
            case let .serverError(statusCode, _):
                return "Backend athlete templates временно недоступен (\(statusCode))."
            case .decodingError:
                return "Не удалось прочитать ответ athlete templates."
            default:
                return "Не удалось синхронизировать шаблон."
            }
        }
        return "Не удалось синхронизировать шаблон."
    }
}

private struct TemplateDetailsRoute: Identifiable {
    let template: WorkoutTemplateDraft
    let isMine: Bool

    var id: String {
        "\(template.id)::\(isMine)"
    }
}

private struct TemplateBuilderRoute: Identifiable {
    let template: WorkoutTemplateDraft?
    let isMine: Bool

    var id: String {
        if let template {
            return "\(template.id)::\(isMine)"
        }
        return "new"
    }
}

private struct EditableTemplateExercise: Identifiable, Equatable {
    let id: String
    var name: String
    var sets: Int
    var repsMin: Int
    var repsMax: Int
    var restSeconds: Int
    var targetRpe: Int?
    var notes: String?

    init(_ draft: TemplateExerciseDraft) {
        id = draft.id
        name = draft.name
        sets = max(1, draft.sets)
        repsMin = max(1, draft.repsMin ?? 8)
        repsMax = max(repsMin, draft.repsMax ?? max(repsMin, 10))
        restSeconds = max(0, draft.restSeconds ?? 90)
        targetRpe = draft.targetRpe
        notes = draft.notes
    }

    var asDraft: TemplateExerciseDraft {
        TemplateExerciseDraft(
            id: id,
            name: name,
            sets: sets,
            repsMin: repsMin,
            repsMax: repsMax,
            restSeconds: restSeconds,
            targetRpe: targetRpe,
            notes: notes,
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
    @State private var detailsRoute: TemplateDetailsRoute?
    @State private var templateBuilderRoute: TemplateBuilderRoute?
    private let exerciseCatalogRepository: any ExerciseCatalogRepository
    private let exercisePickerSuggestionsProvider: any ExercisePickerSuggestionsProviding
    let onStartTemplate: (WorkoutDetailsModel) -> Void

    init(
        viewModel: TemplateLibraryViewModel,
        exerciseCatalogRepository: any ExerciseCatalogRepository = BackendExerciseCatalogRepository(
            apiClient: nil,
            userSub: nil,
        ),
        exercisePickerSuggestionsProvider: any ExercisePickerSuggestionsProviding = EmptyExercisePickerSuggestionsProvider(),
        onStartTemplate: @escaping (WorkoutDetailsModel) -> Void,
    ) {
        _viewModel = State(initialValue: viewModel)
        self.exerciseCatalogRepository = exerciseCatalogRepository
        self.exercisePickerSuggestionsProvider = exercisePickerSuggestionsProvider
        self.onStartTemplate = onStartTemplate
    }

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
                            Text("Откройте шаблон, настройте параметры упражнений и запустите тренировку.")
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        FFCard {
                            Text(errorMessage)
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                        createTemplateBuilderSection
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
        .fullScreenCover(item: $templateBuilderRoute) { route in
            NavigationStack {
                QuickWorkoutBuilderView(
                    template: route.template,
                    userSub: viewModel.currentUserSub,
                    submitTitle: route.template == nil ? "Сохранить шаблон" : "Сохранить изменения",
                    exerciseCatalogRepository: exerciseCatalogRepository,
                    exercisePickerSuggestionsProvider: exercisePickerSuggestionsProvider,
                ) { template in
                    Task {
                        if route.isMine {
                            await viewModel.saveTemplate(template)
                        } else {
                            await viewModel.savePreset(template)
                        }
                    }
                }
            }
        }
        .navigationDestination(item: $detailsRoute) { route in
            TemplateDetailsView(
                template: route.template,
                isMine: route.isMine,
                onEdit: route.isMine ? { template in
                    detailsRoute = nil
                    templateBuilderRoute = TemplateBuilderRoute(template: template, isMine: true)
                } : nil,
                onStart: { editedTemplate in
                    onStartTemplate(viewModel.workout(for: editedTemplate))
                    dismiss()
                },
                onSaveMine: { editedTemplate in
                    await viewModel.updateTemplate(
                        id: editedTemplate.id,
                        name: editedTemplate.name,
                        exercises: editedTemplate.exercises,
                    )
                },
                onSaveAsMine: { editedTemplate in
                    await viewModel.savePreset(editedTemplate)
                },
            )
        }
        .task {
            await viewModel.onAppear()
        }
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
                            Button {
                                detailsRoute = TemplateDetailsRoute(template: template, isMine: true)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                        Text(template.name)
                                            .font(FFTypography.body.weight(.semibold))
                                            .foregroundStyle(FFColors.textPrimary)
                                        Text(summaryText(for: template.exercises))
                                            .font(FFTypography.caption)
                                            .foregroundStyle(FFColors.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(FFColors.textSecondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            HStack(spacing: FFSpacing.sm) {
                                FFButton(title: "Старт", variant: .primary) {
                                    onStartTemplate(viewModel.workout(for: template))
                                    dismiss()
                                }
                                FFButton(title: "Удалить", variant: .destructive) {
                                    Task { await viewModel.deleteTemplate(template.id) }
                                }
                            }
                        }
                        if template.id != viewModel.templates.last?.id {
                            Divider().background(FFColors.gray700)
                        }
                    }
                }
            }
        }
    }

    private var createTemplateBuilderSection: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Создать шаблон")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Text("Новый конструктор использует тот же сценарий сборки, что и быстрая тренировка: название, порядок, редактирование параметров и выбор упражнений через каталог.")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)

                FFButton(title: "Собрать шаблон", variant: .secondary) {
                    templateBuilderRoute = TemplateBuilderRoute(template: nil, isMine: true)
                }
            }
        }
    }

    private var readyTemplatesSection: some View {
        return FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Готовые пресеты")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Text("Готовая библиотека шаблонов для спортсмена пока не описана в текущем серверном контракте, поэтому раздел оставлен без локальных демо-шаблонов.")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
            }
        }
    }

    private func editableSelectedExerciseRow(_ exercise: TemplateExerciseDraft, index: Int) -> some View {
        let normalized = normalize(exercise)
        return VStack(alignment: .leading, spacing: FFSpacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text("\(index + 1). \(normalized.name)")
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                    Text(exerciseDescription(normalized.asDraft))
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
                Spacer()
                reorderHandle(id: normalized.id)
                Button(role: .destructive) {
                    viewModel.removeSelectedExercise(id: normalized.id)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 32, height: 32)
                        .foregroundStyle(FFColors.danger)
                }
                .buttonStyle(.plain)
            }

            controlRow(title: "Подходы", value: normalized.sets) {
                mutateSelectedExercise(normalized.id) { $0.sets = max(1, $0.sets - 1) }
            } onIncrement: {
                mutateSelectedExercise(normalized.id) { $0.sets = min(12, $0.sets + 1) }
            }

            controlRow(title: "Повторы (мин)", value: normalized.repsMin) {
                mutateSelectedExercise(normalized.id) {
                    $0.repsMin = max(1, ($0.repsMin ?? 8) - 1)
                    let maxReps = $0.repsMax ?? $0.repsMin ?? 8
                    if maxReps < ($0.repsMin ?? 8) { $0.repsMax = $0.repsMin }
                }
            } onIncrement: {
                mutateSelectedExercise(normalized.id) {
                    $0.repsMin = min(30, ($0.repsMin ?? 8) + 1)
                    let maxReps = $0.repsMax ?? $0.repsMin ?? 8
                    if maxReps < ($0.repsMin ?? 8) { $0.repsMax = $0.repsMin }
                }
            }

            controlRow(title: "Повторы (макс)", value: normalized.repsMax) {
                mutateSelectedExercise(normalized.id) {
                    let minReps = $0.repsMin ?? 8
                    $0.repsMax = max(minReps, ($0.repsMax ?? minReps) - 1)
                }
            } onIncrement: {
                mutateSelectedExercise(normalized.id) {
                    $0.repsMax = min(40, ($0.repsMax ?? max(10, $0.repsMin ?? 8)) + 1)
                }
            }

            controlRow(title: "Отдых (сек)", value: normalized.restSeconds) {
                mutateSelectedExercise(normalized.id) { $0.restSeconds = max(0, ($0.restSeconds ?? 90) - 15) }
            } onIncrement: {
                mutateSelectedExercise(normalized.id) { $0.restSeconds = min(600, ($0.restSeconds ?? 90) + 15) }
            }
        }
        .padding(.vertical, FFSpacing.xs)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FFColors.gray700.opacity(0.5)).frame(height: 1)
        }
    }

    private func reorderSelectedExercises(draggedId: String, targetId: String) -> Bool {
        guard draggedId != targetId,
              let from = viewModel.selectedExercises.firstIndex(where: { $0.id == draggedId }),
              let to = viewModel.selectedExercises.firstIndex(where: { $0.id == targetId })
        else { return false }

        var items = viewModel.selectedExercises
        let item = items.remove(at: from)
        let destination = from < to ? to - 1 : to
        items.insert(item, at: destination)
        viewModel.selectedExercises = items
        return true
    }

    private func mutateSelectedExercise(_ id: String, transform: (inout TemplateExerciseDraft) -> Void) {
        guard let exercise = viewModel.selectedExercises.first(where: { $0.id == id }) else { return }
        var mutable = exercise
        transform(&mutable)
        viewModel.updateSelectedExercise(mutable)
    }

    private var selectedExerciseIDs: Set<String> {
        Set(viewModel.selectedExercises.map(\.id))
    }

    private func addTemplateExercise(_ exercise: ExerciseCatalogItem) {
        let draft = TemplateExerciseDraft(catalogItem: exercise)
        guard !viewModel.selectedExercises.contains(where: { $0.id == draft.id }) else { return }
        viewModel.selectedExercises.append(draft)
    }

    private func controlRow(
        title: String,
        value: Int,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void,
    )
        -> some View
    {
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

    private func reorderHandle(id: String) -> some View {
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
            .draggable(id)
            .accessibilityLabel("Перетащите, чтобы изменить порядок упражнения")
    }

    private func normalize(_ exercise: TemplateExerciseDraft) -> EditableTemplateExercise {
        EditableTemplateExercise(exercise)
    }

    private func exerciseDescription(_ exercise: TemplateExerciseDraft) -> String {
        let normalized = normalize(exercise)
        return "\(normalized.sets) подхода • \(normalized.repsMin)-\(normalized.repsMax) повторов • отдых \(normalized.restSeconds) сек"
    }

    private func summaryText(for exercises: [TemplateExerciseDraft]) -> String {
        let normalized = exercises.map(normalize)
        let estimatedDuration = max(15, normalized.reduce(0) { $0 + max(1, $1.sets) * 2 })
        return "\(normalized.count) упражнений • ~\(estimatedDuration) мин"
    }
}

private struct TemplateDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    let template: WorkoutTemplateDraft
    let isMine: Bool
    let onEdit: ((WorkoutTemplateDraft) -> Void)?
    let onStart: (WorkoutTemplateDraft) -> Void
    let onSaveMine: (WorkoutTemplateDraft) async -> Void
    let onSaveAsMine: (WorkoutTemplateDraft) async -> Void

    @State private var name: String
    @State private var exercises: [EditableTemplateExercise]
    @State private var isSaving = false

    init(
        template: WorkoutTemplateDraft,
        isMine: Bool,
        onEdit: ((WorkoutTemplateDraft) -> Void)? = nil,
        onStart: @escaping (WorkoutTemplateDraft) -> Void,
        onSaveMine: @escaping (WorkoutTemplateDraft) async -> Void,
        onSaveAsMine: @escaping (WorkoutTemplateDraft) async -> Void,
    ) {
        self.template = template
        self.isMine = isMine
        self.onEdit = onEdit
        self.onStart = onStart
        self.onSaveMine = onSaveMine
        self.onSaveAsMine = onSaveAsMine
        _name = State(initialValue: template.name)
        _exercises = State(initialValue: template.exercises.map(EditableTemplateExercise.init))
    }

    var body: some View {
        ZStack {
            FFColors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: FFSpacing.md) {
                    FFCard {
                        FFTextField(
                            label: "Название шаблона",
                            placeholder: "Введите название",
                            text: $name,
                            helperText: isMine ? "Изменения сохранятся в вашем шаблоне" : "Можно сохранить копию в " +
                                "Мои",
                        )
                    }

                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.sm) {
                            Text("Упражнения")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)

                            if exercises.isEmpty {
                                Text("В этом шаблоне нет упражнений.")
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.textSecondary)
                            } else {
                                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                                    exerciseRow(index: index, exercise: exercise)
                                        .dropDestination(for: String.self) { items, _ in
                                            guard let draggedId = items.first else { return false }
                                            return reorderExercises(draggedId: draggedId, targetId: exercise.id)
                                        }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.md)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: FFSpacing.xs) {
                    FFButton(title: "Запустить", variant: .primary) {
                        onStart(currentTemplate)
                    }

                    if isMine {
                        FFButton(title: isSaving ? "Сохраняем..." : "Сохранить изменения", variant: .secondary) {
                            Task {
                                isSaving = true
                                await onSaveMine(currentTemplate)
                                isSaving = false
                            }
                        }
                        .disabled(isSaving)
                    } else {
                        FFButton(title: isSaving ? "Сохраняем..." : "Сохранить в мои", variant: .secondary) {
                            Task {
                                isSaving = true
                                await onSaveAsMine(currentTemplate)
                                isSaving = false
                            }
                        }
                        .disabled(isSaving)
                    }
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.top, FFSpacing.xs)
                .padding(.bottom, FFSpacing.sm)
                .background(FFColors.background.opacity(0.96))
                .overlay(alignment: .top) {
                    Rectangle().fill(FFColors.gray700.opacity(0.6)).frame(height: 1)
                }
            }
        }
        .navigationTitle(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Шаблон" : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Назад") {
                    dismiss()
                }
                .foregroundStyle(FFColors.textSecondary)
            }
            if let onEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Конструктор") {
                        onEdit(currentTemplate)
                    }
                    .foregroundStyle(FFColors.accent)
                }
            }
        }
    }

    private var currentTemplate: WorkoutTemplateDraft {
        WorkoutTemplateDraft(
            id: template.id,
            userSub: template.userSub,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? template.name : name,
            exercises: exercises.map(\.asDraft),
            updatedAt: Date(),
        )
    }

    private func exerciseRow(index: Int, exercise: EditableTemplateExercise) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            HStack {
                Text("\(index + 1). \(exercise.name)")
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)
                Spacer()
                detailsReorderHandle(id: exercise.id)
            }

            detailsControlRow(title: "Подходы", value: exercise.sets) {
                updateExercise(exercise.id) { $0.sets = max(1, $0.sets - 1) }
            } onIncrement: {
                updateExercise(exercise.id) { $0.sets = min(12, $0.sets + 1) }
            }

            detailsControlRow(title: "Повторы (мин)", value: exercise.repsMin) {
                updateExercise(exercise.id) {
                    $0.repsMin = max(1, $0.repsMin - 1)
                    if $0.repsMax < $0.repsMin { $0.repsMax = $0.repsMin }
                }
            } onIncrement: {
                updateExercise(exercise.id) {
                    $0.repsMin = min(30, $0.repsMin + 1)
                    if $0.repsMax < $0.repsMin { $0.repsMax = $0.repsMin }
                }
            }

            detailsControlRow(title: "Повторы (макс)", value: exercise.repsMax) {
                updateExercise(exercise.id) { $0.repsMax = max($0.repsMin, $0.repsMax - 1) }
            } onIncrement: {
                updateExercise(exercise.id) { $0.repsMax = min(40, $0.repsMax + 1) }
            }

            detailsControlRow(title: "Отдых (сек)", value: exercise.restSeconds) {
                updateExercise(exercise.id) { $0.restSeconds = max(0, $0.restSeconds - 15) }
            } onIncrement: {
                updateExercise(exercise.id) { $0.restSeconds = min(600, $0.restSeconds + 15) }
            }
        }
        .padding(.vertical, FFSpacing.xs)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FFColors.gray700.opacity(0.5)).frame(height: 1)
        }
    }

    private func detailsControlRow(
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
            detailsIconButton(systemName: "minus", action: onDecrement)
            Text("\(value)")
                .font(FFTypography.body.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .frame(minWidth: 40)
                .multilineTextAlignment(.center)
            detailsIconButton(systemName: "plus", action: onIncrement)
        }
    }

    private func detailsIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(FFColors.textSecondary)
                .background(FFColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                        .stroke(FFColors.gray700, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func detailsReorderHandle(id: String) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 32, height: 32)
            .foregroundStyle(FFColors.textSecondary)
            .background(FFColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                    .stroke(FFColors.gray700, lineWidth: 1)
            }
            .draggable(id)
            .accessibilityLabel("Перетащите, чтобы изменить порядок упражнения")
    }

    private func updateExercise(_ id: String, mutate: (inout EditableTemplateExercise) -> Void) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        var item = exercises[index]
        mutate(&item)
        exercises[index] = item
    }

    private func reorderExercises(draggedId: String, targetId: String) -> Bool {
        guard draggedId != targetId,
              let from = exercises.firstIndex(where: { $0.id == draggedId }),
              let to = exercises.firstIndex(where: { $0.id == targetId })
        else { return false }

        let item = exercises.remove(at: from)
        let destination = from < to ? to - 1 : to
        exercises.insert(item, at: destination)
        return true
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

private extension TemplateExerciseDraft {
    init(catalogItem: ExerciseCatalogItem) {
        let defaults = catalogItem.draftDefaults ?? .standard
        self.init(
            id: catalogItem.id,
            name: catalogItem.name,
            sets: max(1, defaults.sets),
            repsMin: defaults.repsMin,
            repsMax: defaults.repsMax,
            restSeconds: defaults.restSeconds,
            targetRpe: defaults.targetRpe,
            notes: defaults.notes,
        )
    }
}
