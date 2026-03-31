import Observation
import SwiftUI
import UIKit

@Observable
@MainActor
private final class QuickWorkoutBuilderViewModel {
    enum Mode: Equatable {
        case todayPlanning
        case quickStart
        case plannedQuickWorkout
        case editWorkout
        case createTemplate
        case editTemplate

        var navigationTitle: String {
            switch self {
            case .todayPlanning:
                "Тренировка на сегодня"
            case .quickStart:
                "Быстрая тренировка"
            case .plannedQuickWorkout:
                "Запланировать тренировку"
            case .editWorkout:
                "Редактирование тренировки"
            case .createTemplate:
                "Новый шаблон"
            case .editTemplate:
                "Редактирование шаблона"
            }
        }

        var heroTitle: String {
            switch self {
            case .todayPlanning:
                "Тренировка на сегодня"
            case .quickStart:
                "Быстрая тренировка"
            case .plannedQuickWorkout:
                "Тренировка для плана"
            case .editWorkout:
                "Конструктор тренировки"
            case .createTemplate:
                "Конструктор шаблона"
            case .editTemplate:
                "Конструктор шаблона"
            }
        }

        var heroSubtitle: String {
            switch self {
            case .todayPlanning:
                "Контекст уже задан. Добавьте упражнения, поправьте детали и начинайте."
            case .quickStart:
                "Добавьте упражнения и начинайте без лишних шагов."
            case .plannedQuickWorkout:
                "Соберите тренировку и сохраните её в план."
            case .editWorkout:
                "Правьте состав и параметры без лишних экранов."
            case .createTemplate:
                "Соберите шаблон для повторного старта."
            case .editTemplate:
                "Обновите шаблон и сохраните изменения."
            }
        }

        var titleLabel: String {
            switch self {
            case .createTemplate, .editTemplate:
                "Название шаблона"
            default:
                "Название тренировки"
            }
        }

        var titlePlaceholder: String {
            switch self {
            case .createTemplate, .editTemplate:
                "Например, Верх тела A"
            case .todayPlanning:
                "Например, Спина + плечи"
            default:
                "Например, Силовая фуллбоди"
            }
        }

        var emptyTitle: String {
            switch self {
            case .createTemplate, .editTemplate:
                "Шаблон пока пуст"
            case .todayPlanning:
                "Стартовая заготовка пока пуста"
            default:
                "Тренировка пока пустая"
            }
        }

        var emptyMessage: String {
            switch self {
            case .createTemplate, .editTemplate:
                "Добавьте первое упражнение через каталог упражнений, чтобы собрать рабочую структуру шаблона."
            case .todayPlanning:
                "По текущим параметрам каталог не собрал стартовую структуру. Добавьте упражнения вручную и продолжайте без потери сценария."
            default:
                "Добавьте первое упражнение через каталог упражнений и затем настройте параметры прямо в списке."
            }
        }
    }

    let mode: Mode
    let primaryActionTitle: String

    var draft: WorkoutCompositionDraft

    init(
        mode: Mode,
        primaryActionTitle: String,
        draft: WorkoutCompositionDraft,
    ) {
        self.mode = mode
        self.primaryActionTitle = primaryActionTitle
        self.draft = draft
    }

    var canSubmit: Bool {
        !draft.exercises.isEmpty
    }

    var selectedExerciseIDs: Set<String> {
        Set(draft.exercises.map(\.id))
    }

    var exerciseCountText: String {
        "\(draft.exercises.count) \(exercisePluralForm(for: draft.exercises.count))"
    }

    var structureSummary: String {
        let totalSets = draft.exercises.reduce(0) { $0 + max(1, $1.sets) }
        if draft.exercises.isEmpty {
            return "Добавьте упражнения"
        }

        return "\(exerciseCountText) • \(totalSets) подходов"
    }

    var helperText: String? {
        switch mode {
        case .todayPlanning:
            nil
        case .createTemplate, .editTemplate:
            "Название используется в библиотеке шаблонов и планировании."
        default:
            nil
        }
    }

    func addExercise(_ exercise: ExerciseCatalogItem) {
        _ = draft.addExercise(exercise)
    }

    func removeExercise(id: String) {
        draft.removeExercise(id: id)
    }

    func reorderExercises(draggedId: String, targetId: String) -> Bool {
        draft.reorderExercise(draggedId: draggedId, targetId: targetId)
    }

    func updateExercise(id: String, mutate: (inout WorkoutCompositionExerciseDraft) -> Void) {
        draft.updateExercise(id: id, mutate: mutate)
    }

    private func exercisePluralForm(for count: Int) -> String {
        let remainder10 = count % 10
        let remainder100 = count % 100
        if remainder10 == 1, remainder100 != 11 {
            return "упражнение"
        }
        if (2 ... 4).contains(remainder10), !(12 ... 14).contains(remainder100) {
            return "упражнения"
        }
        return "упражнений"
    }
}

struct QuickWorkoutBuilderView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: QuickWorkoutBuilderViewModel
    @State private var isExercisePickerPresented = false

    private let initialWorkout: WorkoutDetailsModel?
    private let initialTemplate: WorkoutTemplateDraft?
    private let planningSeed: TodayWorkoutPlanningDraftSeed?
    private let templateUserSub: String?
    private let exerciseCatalogRepository: any ExerciseCatalogRepository
    private let exercisePickerSuggestionsProvider: any ExercisePickerSuggestionsProviding
    private let dismissOnSubmit: Bool
    private let onWorkoutSubmit: ((WorkoutDetailsModel) -> Void)?
    private let onTemplateSubmit: ((WorkoutTemplateDraft) -> Void)?

    init(
        initialWorkout: WorkoutDetailsModel? = nil,
        submitTitle: String = "Начать тренировку",
        exerciseCatalogRepository: any ExerciseCatalogRepository = BackendExerciseCatalogRepository(
            apiClient: nil,
            userSub: nil,
        ),
        exercisePickerSuggestionsProvider: any ExercisePickerSuggestionsProviding = EmptyExercisePickerSuggestionsProvider(),
        onStart: @escaping (WorkoutDetailsModel) -> Void,
    ) {
        let mode: QuickWorkoutBuilderViewModel.Mode = if initialWorkout != nil {
            .editWorkout
        } else if submitTitle == "Создать" {
            .plannedQuickWorkout
        } else {
            .quickStart
        }

        _viewModel = State(
            initialValue: QuickWorkoutBuilderViewModel(
                mode: mode,
                primaryActionTitle: submitTitle,
                draft: initialWorkout.map(WorkoutCompositionDraft.init(workout:)) ?? WorkoutCompositionDraft(),
            ),
        )
        self.initialWorkout = initialWorkout
        initialTemplate = nil
        planningSeed = nil
        templateUserSub = nil
        self.exerciseCatalogRepository = exerciseCatalogRepository
        self.exercisePickerSuggestionsProvider = exercisePickerSuggestionsProvider
        dismissOnSubmit = true
        onWorkoutSubmit = onStart
        onTemplateSubmit = nil
    }

    init(
        template: WorkoutTemplateDraft? = nil,
        userSub: String,
        submitTitle: String = "Сохранить шаблон",
        exerciseCatalogRepository: any ExerciseCatalogRepository = BackendExerciseCatalogRepository(
            apiClient: nil,
            userSub: nil,
        ),
        exercisePickerSuggestionsProvider: any ExercisePickerSuggestionsProviding = EmptyExercisePickerSuggestionsProvider(),
        onSaveTemplate: @escaping (WorkoutTemplateDraft) -> Void,
    ) {
        let mode: QuickWorkoutBuilderViewModel.Mode = if template == nil {
            .createTemplate
        } else {
            .editTemplate
        }

        _viewModel = State(
            initialValue: QuickWorkoutBuilderViewModel(
                mode: mode,
                primaryActionTitle: submitTitle,
                draft: template.map(WorkoutCompositionDraft.init(template:)) ?? WorkoutCompositionDraft(),
            ),
        )
        initialWorkout = nil
        initialTemplate = template
        planningSeed = nil
        templateUserSub = userSub
        self.exerciseCatalogRepository = exerciseCatalogRepository
        self.exercisePickerSuggestionsProvider = exercisePickerSuggestionsProvider
        dismissOnSubmit = true
        onWorkoutSubmit = nil
        onTemplateSubmit = onSaveTemplate
    }

    init(
        planningSeed: TodayWorkoutPlanningDraftSeed,
        dismissOnSubmit: Bool = true,
        exerciseCatalogRepository: any ExerciseCatalogRepository = BackendExerciseCatalogRepository(
            apiClient: nil,
            userSub: nil,
        ),
        exercisePickerSuggestionsProvider: any ExercisePickerSuggestionsProviding = EmptyExercisePickerSuggestionsProvider(),
        onStart: @escaping (WorkoutDetailsModel) -> Void,
    ) {
        _viewModel = State(
            initialValue: QuickWorkoutBuilderViewModel(
                mode: .todayPlanning,
                primaryActionTitle: "Начать тренировку",
                draft: planningSeed.draft,
            ),
        )
        initialWorkout = nil
        initialTemplate = nil
        self.planningSeed = planningSeed
        templateUserSub = nil
        self.exerciseCatalogRepository = exerciseCatalogRepository
        self.exercisePickerSuggestionsProvider = exercisePickerSuggestionsProvider
        self.dismissOnSubmit = dismissOnSubmit
        onWorkoutSubmit = onStart
        onTemplateSubmit = nil
    }

    var body: some View {
        ZStack {
            FFColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: FFSpacing.md) {
                    headerCard
                    titleCard
                    exercisesCard
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
        }
        .navigationTitle(viewModel.mode.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(FFColors.textSecondary)
                .accessibilityLabel("Закрыть")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(toolbarActionTitle) {
                    submit()
                }
                .disabled(!viewModel.canSubmit)
                .font(FFTypography.body.weight(.semibold))
                .foregroundStyle(viewModel.canSubmit ? FFColors.accent : FFColors.gray500)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") {
                    dismissKeyboard()
                }
                .font(FFTypography.body.weight(.semibold))
            }
        }
        .tint(FFColors.accent)
        .fullScreenCover(isPresented: $isExercisePickerPresented) {
            NavigationStack {
                ExercisePickerView(
                    repository: exerciseCatalogRepository,
                    suggestionsProvider: exercisePickerSuggestionsProvider,
                    context: exercisePickerContext,
                    selectedExerciseIDs: viewModel.selectedExerciseIDs,
                ) { exercises in
                    for exercise in exercises {
                        viewModel.addExercise(exercise)
                    }
                }
            }
        }
    }

    private var headerCard: some View {
        TrainingBuilderHeroCard(
            eyebrow: nil,
            title: builderHeroTitle,
            subtitle: headerSubtitle ?? "",
            badges: summaryBadges
        )
    }

    private var exercisesCard: some View {
        TrainingBuilderSectionCard(
            eyebrow: nil,
            title: "Упражнения",
            helper: viewModel.draft.exercises.isEmpty
                ? "Добавьте первое упражнение."
                : ""
        ) {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                if viewModel.draft.exercises.isEmpty {
                    emptyStateCard
                } else {
                    ForEach(Array(viewModel.draft.exercises.enumerated()), id: \.element.id) { index, exercise in
                        QuickWorkoutExerciseCard(
                            index: index,
                            exercise: exercise,
                            notes: notesBinding(for: exercise.id),
                            onRemove: {
                                viewModel.removeExercise(id: exercise.id)
                            },
                            onSetsDecrement: {
                                viewModel.updateExercise(id: exercise.id) {
                                    $0.sets = max(1, $0.sets - 1)
                                }
                            },
                            onSetsIncrement: {
                                viewModel.updateExercise(id: exercise.id) {
                                    $0.sets = min(12, $0.sets + 1)
                                }
                            },
                            onRepsMinDecrement: {
                                viewModel.updateExercise(id: exercise.id) {
                                    let current = max(1, $0.repsMin ?? 8)
                                    $0.repsMin = max(1, current - 1)
                                    if let repsMax = $0.repsMax, repsMax < ($0.repsMin ?? repsMax) {
                                        $0.repsMax = $0.repsMin
                                    }
                                }
                            },
                            onRepsMinIncrement: {
                                viewModel.updateExercise(id: exercise.id) {
                                    let current = $0.repsMin ?? min(8, $0.repsMax ?? 8)
                                    $0.repsMin = min(30, current + 1)
                                    if let repsMax = $0.repsMax, repsMax < ($0.repsMin ?? repsMax) {
                                        $0.repsMax = $0.repsMin
                                    }
                                }
                            },
                            onRepsMaxDecrement: {
                                viewModel.updateExercise(id: exercise.id) {
                                    let minimum = $0.repsMin ?? 1
                                    let current = $0.repsMax ?? max(minimum, 10)
                                    $0.repsMax = max(minimum, current - 1)
                                }
                            },
                            onRepsMaxIncrement: {
                                viewModel.updateExercise(id: exercise.id) {
                                    let minimum = $0.repsMin ?? 1
                                    let current = $0.repsMax ?? max(minimum, 10)
                                    $0.repsMax = min(40, current + 1)
                                }
                            },
                            onRestDecrement: {
                                viewModel.updateExercise(id: exercise.id) {
                                    $0.restSeconds = max(0, ($0.restSeconds ?? 90) - 15)
                                }
                            },
                            onRestIncrement: {
                                viewModel.updateExercise(id: exercise.id) {
                                    $0.restSeconds = min(600, ($0.restSeconds ?? 90) + 15)
                                }
                            },
                            onRpeDecrement: {
                                viewModel.updateExercise(id: exercise.id) {
                                    guard let current = $0.targetRpe else { return }
                                    $0.targetRpe = current > 1 ? current - 1 : nil
                                }
                            },
                            onRpeIncrement: {
                                viewModel.updateExercise(id: exercise.id) {
                                    $0.targetRpe = min(10, ($0.targetRpe ?? 6) + 1)
                                }
                            },
                        )
                        .dropDestination(for: String.self) { items, _ in
                            guard let draggedId = items.first else { return false }
                            return viewModel.reorderExercises(draggedId: draggedId, targetId: exercise.id)
                        }
                    }
                }

                if !viewModel.draft.exercises.isEmpty {
                    HStack(spacing: FFSpacing.xs) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(FFColors.accent)
                        Button("Добавить ещё упражнение") {
                            isExercisePickerPresented = true
                        }
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.accent)
                        Spacer()
                    }
                    .padding(.top, FFSpacing.xs)
                }
            }
        }
    }

    private var titleCard: some View {
        TrainingBuilderSectionCard(
            eyebrow: nil,
            title: viewModel.mode.titleLabel,
            helper: viewModel.helperText ?? ""
        ) {
            FFTextField(
                label: viewModel.mode.titleLabel,
                placeholder: viewModel.mode.titlePlaceholder,
                text: Binding(
                    get: { viewModel.draft.title },
                    set: { viewModel.draft.title = $0 }
                ),
                helperText: viewModel.helperText,
            )
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            Text(emptyStateTitle)
                .font(FFTypography.body.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
            Text(emptyStateMessage)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)

            FFButton(title: "Открыть каталог упражнений", variant: .secondary) {
                isExercisePickerPresented = true
            }
        }
        .padding(FFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    FFColors.accent.opacity(0.12),
                    FFColors.surface,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .stroke(FFColors.gray700, lineWidth: 1)
        }
    }

    private var bottomActionBar: some View {
        TrainingBuilderBottomBar(
            helper: viewModel.canSubmit ? "Проверьте структуру и подтвердите старт или сохранение." : "Сначала добавьте упражнения.",
            title: viewModel.primaryActionTitle,
            summary: viewModel.canSubmit ? viewModel.structureSummary : nil,
            buttonVariant: viewModel.canSubmit ? .primary : .disabled
        ) {
            submit()
        }
    }

    private var toolbarActionTitle: String {
        switch viewModel.primaryActionTitle {
        case "Начать тренировку":
            "Старт"
        case "Сохранить изменения":
            "Сохранить"
        case "Сохранить шаблон":
            "Сохранить"
        default:
            viewModel.primaryActionTitle
        }
    }

    private func notesBinding(for exerciseID: String) -> Binding<String> {
        Binding(
            get: {
                viewModel.draft.exercises.first(where: { $0.id == exerciseID })?.notes ?? ""
            },
            set: { newValue in
                viewModel.updateExercise(id: exerciseID) {
                    $0.notes = newValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                }
            },
        )
    }

    private func submit() {
        guard viewModel.canSubmit else { return }

        if let onWorkoutSubmit {
            let fallbackTitle = viewModel.mode == .editWorkout
                ? (initialWorkout?.title ?? "Тренировка")
                : planningSeed?.suggestedTitle
                    ?? "Быстрая тренировка • \(Date().formatted(date: .omitted, time: .shortened))"
            let workout = viewModel.draft.asWorkoutDetailsModel(
                workoutID: initialWorkout?.id ?? "quick-\(UUID().uuidString)",
                fallbackTitle: fallbackTitle,
                dayOrder: initialWorkout?.dayOrder ?? 0,
                coachNote: initialWorkout?.coachNote ?? planningSeed?.coachNote ?? "Быстрая тренировка",
            )
            onWorkoutSubmit(workout)
            if dismissOnSubmit {
                dismiss()
            }
            return
        }

        if let onTemplateSubmit, let templateUserSub {
            let template = viewModel.draft.asTemplateDraft(
                id: initialTemplate?.id ?? "new-\(UUID().uuidString)",
                userSub: templateUserSub,
                fallbackTitle: initialTemplate?.name ?? "Новый шаблон",
            )
            onTemplateSubmit(template)
            if dismissOnSubmit {
                dismiss()
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var headerSubtitle: String? {
        switch viewModel.mode {
        case .plannedQuickWorkout:
            return "Соберите тренировку и сохраните её в план."
        case .createTemplate, .editTemplate:
            return "Добавьте упражнения и сохраните шаблон."
        default:
            return "Добавьте упражнения и начинайте."
        }
    }

    private var emptyStateTitle: String {
        switch viewModel.mode {
        case .createTemplate, .editTemplate:
            return "Добавьте упражнения в шаблон"
        case .todayPlanning:
            return "Дополните структуру на сегодня"
        default:
            return "Добавьте упражнения в тренировку"
        }
    }

    private var emptyStateMessage: String {
        if planningSeed != nil {
            return "Добавьте недостающие упражнения и начинайте."
        }
        return "После выбора они сразу появятся в тренировке."
    }

    private func planningChips(for seed: TodayWorkoutPlanningDraftSeed) -> [String] {
        var chips: [String] = []
        let muscles = seed.request.targetMuscleGroups
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .prefix(2)
            .map(\.title)
            .joined(separator: " + ")
        if !muscles.isEmpty {
            chips.append(muscles)
        }
        if let duration = seed.request.desiredDurationMinutes {
            chips.append("\(duration) мин")
        }
        if let focus = seed.request.focus {
            chips.append(focus.title)
        }
        return chips
    }

    private var summaryBadges: [String] {
        var badges: [String] = []
        if viewModel.canSubmit {
            badges = [viewModel.structureSummary]
        }
        if let planningSeed {
            badges.append(contentsOf: planningChips(for: planningSeed))
        }
        return Array(badges.prefix(2))
    }

    private var builderHeroTitle: String {
        switch viewModel.mode {
        case .todayPlanning:
            return "Соберите тренировку"
        case .createTemplate, .editTemplate:
            return "Соберите шаблон"
        default:
            return "Соберите тренировку"
        }
    }

    private var exercisePickerContext: ExercisePickerViewModel.Context {
        guard let planningSeed else {
            return .init()
        }

        return ExercisePickerViewModel.Context(
            title: "Контекст тренировки",
            muscleGroups: planningSeed.request.targetMuscleGroups
                .sorted(by: { $0.sortOrder < $1.sortOrder }),
            equipmentIDs: planningSeed.request.availableEquipmentIDs.sorted(),
            equipmentNames: planningSeed.selectedEquipmentNames,
        )
    }
}

private struct QuickWorkoutExerciseCard: View {
    let index: Int
    let exercise: WorkoutCompositionExerciseDraft
    let notes: Binding<String>
    let onRemove: () -> Void
    let onSetsDecrement: () -> Void
    let onSetsIncrement: () -> Void
    let onRepsMinDecrement: () -> Void
    let onRepsMinIncrement: () -> Void
    let onRepsMaxDecrement: () -> Void
    let onRepsMaxIncrement: () -> Void
    let onRestDecrement: () -> Void
    let onRestIncrement: () -> Void
    let onRpeDecrement: () -> Void
    let onRpeIncrement: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            HStack(alignment: .top, spacing: FFSpacing.sm) {
                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    HStack(spacing: FFSpacing.xs) {
                        Text("Упр. \(index + 1)")
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.background)
                            .padding(.horizontal, FFSpacing.sm)
                            .padding(.vertical, 6)
                            .background(FFColors.accent)
                            .clipShape(Capsule())
                        Text(exercise.name)
                            .font(FFTypography.body.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                    }
                    if !exercise.catalogTags.isEmpty {
                        exerciseTagRow(tags: exercise.catalogTags)
                    }
                    Text(exercise.summaryText)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                    if let notesPreview = exercise.notesPreview {
                        Text(notesPreview)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                HStack(spacing: FFSpacing.xxs) {
                    reorderHandle(id: exercise.id)
                    iconButton(systemName: "trash", tint: FFColors.danger, action: onRemove)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: FFSpacing.xs),
                    GridItem(.flexible(), spacing: FFSpacing.xs),
                ],
                spacing: FFSpacing.xs
            ) {
                metricTile(
                    title: "Подходы",
                    value: "\(exercise.sets)",
                    accent: FFColors.primary,
                    onDecrement: onSetsDecrement,
                    onIncrement: onSetsIncrement,
                )
                metricTile(
                    title: "Повторы мин",
                    value: exercise.repsMin.map(String.init) ?? "—",
                    accent: FFColors.accent,
                    onDecrement: onRepsMinDecrement,
                    onIncrement: onRepsMinIncrement,
                )
                metricTile(
                    title: "Повторы макс",
                    value: exercise.repsMax.map(String.init) ?? "—",
                    accent: FFColors.accent,
                    onDecrement: onRepsMaxDecrement,
                    onIncrement: onRepsMaxIncrement,
                )
                metricTile(
                    title: "Отдых",
                    value: exercise.restSeconds.map { "\($0)с" } ?? "—",
                    accent: FFColors.primary,
                    onDecrement: onRestDecrement,
                    onIncrement: onRestIncrement,
                )
                metricTile(
                    title: "RPE",
                    value: exercise.targetRpe.map(String.init) ?? "—",
                    accent: FFColors.accent,
                    onDecrement: onRpeDecrement,
                    onIncrement: onRpeIncrement,
                )
            }

            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Заметки")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                TextField(
                    "",
                    text: notes,
                    prompt: Text("Техника, пауза, темп, акценты")
                        .foregroundStyle(FFColors.gray500),
                    axis: .vertical,
                )
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .lineLimit(1 ... 3)
                .font(FFTypography.body)
                .foregroundStyle(FFColors.textPrimary)
                .tint(FFColors.textPrimary)
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.sm)
                .background(FFColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                        .stroke(FFColors.gray300, lineWidth: 1)
                }
            }
        }
        .padding(FFSpacing.md)
        .background(
            LinearGradient(
                colors: [
                    FFColors.surface,
                    FFColors.surface.opacity(0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.card)
                .stroke(FFColors.gray700.opacity(0.9), lineWidth: 1)
        }
    }

    private func metricTile(
        title: String,
        value: String,
        accent: Color,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void,
    ) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(FFColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: FFSpacing.xs) {
                compactIconButton(systemName: "minus", tint: accent, action: onDecrement)
                compactIconButton(systemName: "plus", tint: accent, action: onIncrement)
                Spacer(minLength: 0)
            }
        }
        .padding(FFSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FFColors.background.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .stroke(accent.opacity(0.28), lineWidth: 1)
        }
    }

    private func exerciseTagRow(tags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FFSpacing.xs) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(FFColors.textSecondary)
                        .padding(.horizontal, FFSpacing.sm)
                        .padding(.vertical, FFSpacing.xs)
                        .background(FFColors.background.opacity(0.8))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(FFColors.gray700.opacity(0.8), lineWidth: 1)
                        }
                }
            }
        }
    }

    private func reorderHandle(id: String) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(FFColors.textSecondary)
            .frame(width: 32, height: 32)
            .background(FFColors.background)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                    .stroke(FFColors.gray700, lineWidth: 1)
            }
            .draggable(id)
            .accessibilityLabel("Перетащите, чтобы изменить порядок упражнения")
    }

    private func iconButton(
        systemName: String,
        tint: Color = FFColors.textSecondary,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(tint)
                .background(FFColors.background)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                        .stroke(FFColors.gray700, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func compactIconButton(
        systemName: String,
        tint: Color,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .foregroundStyle(tint)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        QuickWorkoutBuilderView(onStart: { _ in })
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
