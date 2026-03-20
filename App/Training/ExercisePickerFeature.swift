import Foundation
import Observation
import SwiftUI

enum ExercisePickerSectionKind: String, Equatable, Sendable {
    case recent
    case templates
    case localMatches
    case catalogResults
}

struct ExercisePickerSection: Equatable, Sendable, Identifiable {
    let kind: ExercisePickerSectionKind
    let title: String
    let subtitle: String?
    let items: [ExerciseCatalogItem]

    var id: String {
        kind.rawValue
    }
}

struct ExercisePickerSuggestionsSnapshot: Equatable, Sendable {
    let sections: [ExercisePickerSection]
    let contractGaps: [String]

    static let empty = ExercisePickerSuggestionsSnapshot(
        sections: [],
        contractGaps: [],
    )
}

protocol ExercisePickerSuggestionsProviding: Sendable {
    func loadSuggestions() async -> ExercisePickerSuggestionsSnapshot
}

struct EmptyExercisePickerSuggestionsProvider: ExercisePickerSuggestionsProviding {
    func loadSuggestions() async -> ExercisePickerSuggestionsSnapshot {
        .empty
    }
}

struct TrainingStoreExercisePickerSuggestionsProvider: ExercisePickerSuggestionsProviding {
    let userSub: String
    let athleteTrainingClient: (any AthleteTrainingClientProtocol)?
    let templateRepository: any WorkoutTemplateRepository
    let trainingStore: any TrainingStore
    let calendar: Calendar

    init(
        userSub: String,
        athleteTrainingClient: (any AthleteTrainingClientProtocol)? = nil,
        templateRepository: any WorkoutTemplateRepository = LocalWorkoutTemplateRepository(),
        trainingStore: any TrainingStore = LocalTrainingStore(),
        calendar: Calendar = .current,
    ) {
        self.userSub = userSub.trimmingCharacters(in: .whitespacesAndNewlines)
        self.athleteTrainingClient = athleteTrainingClient
        self.templateRepository = templateRepository
        self.trainingStore = trainingStore
        self.calendar = calendar
    }

    init(
        userSub: String,
        trainingStore: any TrainingStore,
        calendar: Calendar = .current,
    ) {
        self.init(
            userSub: userSub,
            templateRepository: LocalWorkoutTemplateRepository(trainingStore: trainingStore),
            trainingStore: trainingStore,
            calendar: calendar,
        )
    }

    func loadSuggestions() async -> ExercisePickerSuggestionsSnapshot {
        guard !userSub.isEmpty else {
            return .empty
        }

        async let templateList = templateRepository.templates(userSub: userSub)
        async let recentItems = loadRecentItems()

        let templates = await templateList
        let recentItemsValue = await recentItems
        let templateItems = buildTemplateItems(from: templates, excluding: Set(recentItemsValue.map(\.id)))

        var sections: [ExercisePickerSection] = []
        if !recentItemsValue.isEmpty {
            sections.append(
                ExercisePickerSection(
                    kind: .recent,
                    title: "Недавние",
                    subtitle: "Из ваших последних выполненных тренировок",
                    items: recentItemsValue,
                ),
            )
        }
        if !templateItems.isEmpty {
            sections.append(
                ExercisePickerSection(
                    kind: .templates,
                    title: "Из шаблонов",
                    subtitle: "Упражнения из вашей template library",
                    items: templateItems,
                ),
            )
        }

        return ExercisePickerSuggestionsSnapshot(
            sections: sections,
            contractGaps: [],
        )
    }

    private func loadRecentItems() async -> [ExerciseCatalogItem] {
        if let athleteTrainingClient {
            switch await athleteTrainingClient.recentExercises(limit: 8) {
            case let .success(response):
                let items = response.entries
                    .map(\.exercise)
                    .map(asCatalogItem)
                    .uniqueByCatalogID()
                if !items.isEmpty {
                    return items
                }
            case .failure:
                break
            }
        }

        let plans = await loadRecentPlans()
        return buildRecentItems(from: plans)
    }

    private func loadRecentPlans() async -> [TrainingDayPlan] {
        let anchor = calendar.startOfDay(for: Date())
        let months = [0, -1, -2].compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: anchor)
        }

        var items: [TrainingDayPlan] = []
        for month in months {
            items.append(contentsOf: await trainingStore.plans(userSub: userSub, month: month))
        }

        return items
    }

    private func buildRecentItems(from plans: [TrainingDayPlan]) -> [ExerciseCatalogItem] {
        let now = calendar.startOfDay(for: Date())
        let datedItems = plans
            .filter { calendar.startOfDay(for: $0.day) <= now }
            .sorted { $0.day > $1.day }
            .flatMap { plan in
                (plan.workoutDetails?.exercises ?? [])
                    .sorted(by: { $0.orderIndex < $1.orderIndex })
                    .map { DatedCatalogItem(date: plan.day, item: $0.asCatalogItem) }
            }

        return datedItems
            .sorted { $0.date > $1.date }
            .map(\.item)
            .uniqueByCatalogID()
            .prefix(8)
            .map { $0 }
    }

    private func buildTemplateItems(from templates: [WorkoutTemplateDraft], excluding excludedIDs: Set<String>) -> [ExerciseCatalogItem] {
        templates
            .sorted { $0.updatedAt > $1.updatedAt }
            .flatMap(\.exercises)
            .map(asCatalogItem)
            .filter { !excludedIDs.contains($0.id) }
            .uniqueByCatalogID()
            .prefix(12)
            .map { $0 }
    }

    private func asCatalogItem(_ draft: TemplateExerciseDraft) -> ExerciseCatalogItem {
        ExerciseCatalogItem(
            id: draft.id,
            code: nil,
            name: draft.name,
            description: nil,
            movementPattern: nil,
            difficultyLevel: nil,
            isBodyweight: nil,
            muscles: [],
            equipment: [],
            media: [],
            source: .savedTemplate,
            draftDefaults: ExerciseCatalogDraftDefaults(
                sets: max(1, draft.sets),
                repsMin: draft.repsMin,
                repsMax: draft.repsMax,
                restSeconds: draft.restSeconds,
                targetRpe: draft.targetRpe,
                notes: draft.notes,
            ),
        )
    }

    private func asCatalogItem(_ exercise: AthleteExerciseBrief) -> ExerciseCatalogItem {
        ExerciseCatalogItem(
            id: exercise.id,
            code: exercise.code,
            name: exercise.name,
            description: exercise.description,
            movementPattern: nil,
            difficultyLevel: nil,
            isBodyweight: exercise.isBodyweight,
            muscles: [],
            equipment: [],
            media: exercise.media ?? [],
            source: .athleteCatalog,
            draftDefaults: nil,
        )
    }
}

@Observable
@MainActor
final class ExercisePickerViewModel {
    struct Context: Equatable, Sendable {
        var title: String?
        var muscleGroups: [ExerciseCatalogMuscleGroup] = []
        var equipmentIDs: [String] = []
        var equipmentNames: [String] = []

        var isActive: Bool {
            !muscleGroups.isEmpty || !equipmentIDs.isEmpty
        }

        var chips: [String] {
            let muscleChips = muscleGroups
                .sorted(by: { $0.sortOrder < $1.sortOrder })
                .map(\.label)
            return muscleChips + equipmentNames
        }
    }

    struct FilterState: Equatable, Sendable {
        var muscleGroup: ExerciseCatalogMuscleGroup?
        var equipment: ExerciseCatalogEquipment?
        var movementPattern: ExerciseCatalogMovementPattern?
        var difficultyLevel: ExerciseCatalogDifficultyLevel?

        var isActive: Bool {
            muscleGroup != nil || equipment != nil || movementPattern != nil || difficultyLevel != nil
        }
    }

    private let repository: any ExerciseCatalogRepository
    private let suggestionsProvider: any ExercisePickerSuggestionsProviding
    private let context: Context
    private var searchTask: Task<Void, Never>?
    private var suggestionsSnapshot: ExercisePickerSuggestionsSnapshot = .empty
    private(set) var catalogMetadata: ExerciseCatalogMetadata = .empty
    private(set) var hasLoaded = false

    var searchText = ""
    var filters = FilterState()
    var catalogItems: [ExerciseCatalogItem] = []
    var catalogState: ExerciseCatalogResultState = .content
    var note: String?
    var contractGaps: [String] = []
    var isLoadingCatalog = false
    var isLoadingSuggestions = false

    init(
        repository: any ExerciseCatalogRepository,
        suggestionsProvider: any ExercisePickerSuggestionsProviding = EmptyExercisePickerSuggestionsProvider(),
        context: Context = .init(),
    ) {
        self.repository = repository
        self.suggestionsProvider = suggestionsProvider
        self.context = context
    }

    func onAppear() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reloadAll()
    }

    func searchQueryChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.reloadCatalog()
        }
    }

    func retry() async {
        await reloadAll()
    }

    func refreshCatalog() async {
        await reloadCatalog()
    }

    func clearFilters() async {
        filters = FilterState()
        await reloadCatalog()
    }

    func selectMuscleGroup(_ value: ExerciseCatalogMuscleGroup?) async {
        filters.muscleGroup = value
        await reloadCatalog()
    }

    func selectEquipment(_ value: ExerciseCatalogEquipment?) async {
        filters.equipment = value
        await reloadCatalog()
    }

    func selectMovementPattern(_ value: ExerciseCatalogMovementPattern?) async {
        filters.movementPattern = value
        await reloadCatalog()
    }

    func selectDifficulty(_ value: ExerciseCatalogDifficultyLevel?) async {
        filters.difficultyLevel = value
        await reloadCatalog()
    }

    var hasActiveQuery: Bool {
        trimmedSearch != nil || filters.isActive || context.isActive
    }

    var contextTitle: String? {
        context.title
    }

    var contextChips: [String] {
        context.chips
    }

    var isContextualBrowsing: Bool {
        context.isActive && trimmedSearch == nil && !filters.isActive
    }

    var muscleGroupOptions: [ExerciseCatalogMuscleGroup] {
        if !catalogMetadata.muscleGroups.isEmpty {
            return catalogMetadata.muscleGroups
        }
        return ExerciseCatalogMuscleGroup.pickerOptions
    }

    var equipmentOptions: [ExerciseCatalogEquipment] {
        catalogMetadata.equipment
    }

    var movementPatternOptions: [ExerciseCatalogMovementPattern] {
        if !catalogMetadata.movementPatterns.isEmpty {
            return catalogMetadata.movementPatterns
        }
        return ExerciseCatalogMovementPattern.pickerOptions
    }

    var difficultyOptions: [ExerciseCatalogDifficultyLevel] {
        if !catalogMetadata.difficultyLevels.isEmpty {
            return catalogMetadata.difficultyLevels
        }
        return ExerciseCatalogDifficultyLevel.pickerOptions
    }

    var visibleSections: [ExercisePickerSection] {
        let localMatches = filteredLocalMatches
        var sections: [ExercisePickerSection] = []

        if hasActiveQuery {
            if !localMatches.isEmpty {
                sections.append(
                    ExercisePickerSection(
                        kind: .localMatches,
                        title: "Локальные совпадения",
                        subtitle: "Из недавних тренировок и шаблонов",
                        items: localMatches,
                    ),
                )
            }
            if !catalogItems.isEmpty {
                sections.append(
                    ExercisePickerSection(
                        kind: .catalogResults,
                        title: "Результаты каталога",
                        subtitle: catalogSectionSubtitle,
                        items: catalogItems,
                    ),
                )
            }
            return sections
        }

        sections.append(contentsOf: suggestionsSnapshot.sections.filter { !$0.items.isEmpty })

        if !catalogItems.isEmpty {
            sections.append(
                ExercisePickerSection(
                    kind: .catalogResults,
                    title: "Все упражнения",
                    subtitle: catalogSectionSubtitle,
                    items: catalogItems,
                ),
            )
        }

        return sections
    }

    var statusMessage: String? {
        switch catalogState {
        case .content:
            return note
        case let .empty(message):
            if visibleSections.isEmpty {
                return message
            }
            return note ?? message
        case let .unavailable(message):
            if visibleSections.isEmpty {
                return message
            }
            return note ?? message
        }
    }

    private var catalogSectionSubtitle: String? {
        if trimmedSearch == nil, !filters.isActive, context.isActive {
            return "Каталог уже сужен под выбранную тренировку."
        }
        switch catalogState {
        case .content:
            return note
        case .empty:
            return note
        case let .unavailable(message):
            return note ?? message
        }
    }

    private var trimmedSearch: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var currentQuery: ExerciseCatalogQuery {
        ExerciseCatalogQuery(
            search: trimmedSearch,
            movementPattern: filters.movementPattern,
            difficultyLevel: filters.difficultyLevel,
            muscleGroups: filters.muscleGroup.map { [$0] } ?? context.muscleGroups,
            equipmentIds: filters.equipment.map { [$0.id] } ?? context.equipmentIDs,
        )
    }

    private var filteredLocalMatches: [ExerciseCatalogItem] {
        suggestionsSnapshot.sections
            .flatMap(\.items)
            .filter(matchesActiveQuery)
            .uniqueByCatalogID()
            .prefix(10)
            .map { $0 }
    }

    private func matchesActiveQuery(_ item: ExerciseCatalogItem) -> Bool {
        if let search = trimmedSearch {
            let haystack = [
                item.name,
                item.description,
                item.muscles.map(\.name).joined(separator: " "),
                item.equipment.map(\.name).joined(separator: " "),
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

            if !haystack.contains(search.lowercased()) {
                return false
            }
        }

        if let movementPattern = filters.movementPattern, item.movementPattern != movementPattern {
            return false
        }
        if let difficultyLevel = filters.difficultyLevel, item.difficultyLevel != difficultyLevel {
            return false
        }
        if let muscleGroup = filters.muscleGroup {
            guard item.muscles.contains(where: { $0.muscleGroup == muscleGroup }) else {
                return false
            }
        }
        if let equipment = filters.equipment {
            guard item.equipment.contains(where: { $0.id == equipment.id }) else {
                return false
            }
        }

        return true
    }

    private func reloadAll() async {
        let query = currentQuery
        isLoadingCatalog = true
        isLoadingSuggestions = true

        async let suggestions = suggestionsProvider.loadSuggestions()
        async let metadata = repository.metadata()
        async let catalog = repository.search(query: query)

        let snapshot = await suggestions
        suggestionsSnapshot = snapshot
        isLoadingSuggestions = false
        catalogMetadata = await metadata

        applyCatalogResult(await catalog)
    }

    private func reloadCatalog() async {
        isLoadingCatalog = true
        applyCatalogResult(await repository.search(query: currentQuery))
    }

    private func applyCatalogResult(_ result: ExerciseCatalogResult) {
        catalogItems = result.items
        catalogState = result.state
        note = result.note
        contractGaps = (suggestionsSnapshot.contractGaps + result.contractGaps).removingDuplicateStrings()
        isLoadingCatalog = false
    }
}

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ExercisePickerViewModel

    let selectedExerciseIDs: Set<String>
    let onAdd: (ExerciseCatalogItem) -> Void

    init(
        repository: any ExerciseCatalogRepository = BackendExerciseCatalogRepository(
            apiClient: nil,
            userSub: nil,
        ),
        suggestionsProvider: any ExercisePickerSuggestionsProviding = EmptyExercisePickerSuggestionsProvider(),
        context: ExercisePickerViewModel.Context = .init(),
        selectedExerciseIDs: Set<String> = [],
        onAdd: @escaping (ExerciseCatalogItem) -> Void,
    ) {
        _viewModel = State(
            initialValue: ExercisePickerViewModel(
                repository: repository,
                suggestionsProvider: suggestionsProvider,
                context: context,
            ),
        )
        self.selectedExerciseIDs = selectedExerciseIDs
        self.onAdd = onAdd
    }

    var body: some View {
        ZStack {
            FFColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: FFSpacing.md) {
                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.sm) {
                            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                Text("CATALOG")
                                    .font(FFTypography.caption.weight(.semibold))
                                    .foregroundStyle(FFColors.accent)
                                Text(viewModel.hasActiveQuery ? "Подбор упражнений" : "Выбор упражнения")
                                    .font(FFTypography.h2)
                                    .foregroundStyle(FFColors.textPrimary)
                                Text(searchCardSubtitle)
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.textSecondary)
                            }

                            if !viewModel.contextChips.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: FFSpacing.xs) {
                                        if let title = viewModel.contextTitle {
                                            contextChip(title, accent: true)
                                        }
                                        ForEach(viewModel.contextChips, id: \.self) { chip in
                                            contextChip(chip)
                                        }
                                    }
                                }
                            }

                            FFTextField(
                                label: "Поиск упражнения",
                                placeholder: "Например, присед, жим или тяга",
                                text: $viewModel.searchText,
                                helperText: searchFieldHelperText,
                            )

                            filterRow
                        }
                        .padding(.top, FFSpacing.xs)
                        .background(
                            LinearGradient(
                                colors: [FFColors.accent.opacity(0.1), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }

                    if let statusMessage = viewModel.statusMessage {
                        statusCard(message: statusMessage)
                    }

                    if viewModel.isLoadingCatalog, viewModel.visibleSections.isEmpty {
                        loadingCard
                    } else if viewModel.visibleSections.isEmpty {
                        emptyCard
                    } else {
                        ForEach(viewModel.visibleSections) { section in
                            sectionCard(section)
                        }
                    }

                    if !viewModel.contractGaps.isEmpty {
                        contractGapCard
                    }
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.md)
            }
        }
        .navigationTitle("Выбор упражнения")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Закрыть") {
                    dismiss()
                }
                .foregroundStyle(FFColors.textSecondary)
            }

            if viewModel.filters.isActive {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сбросить") {
                        Task { await viewModel.clearFilters() }
                    }
                    .foregroundStyle(FFColors.accent)
                }
            }
        }
        .task {
            await viewModel.onAppear()
        }
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.searchQueryChanged()
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FFSpacing.xs) {
                filterMenu(
                    title: "Группа мышц",
                    value: viewModel.filters.muscleGroup?.label ?? "Все",
                ) {
                    Button("Все") {
                        Task { await viewModel.selectMuscleGroup(nil) }
                    }

                    ForEach(viewModel.muscleGroupOptions, id: \.rawValue) { item in
                        Button(item.label) {
                            Task { await viewModel.selectMuscleGroup(item) }
                        }
                    }
                }

                if !viewModel.equipmentOptions.isEmpty || viewModel.filters.equipment != nil {
                    filterMenu(
                        title: "Оборудование",
                        value: viewModel.filters.equipment?.name ?? "Все",
                    ) {
                        Button("Все") {
                            Task { await viewModel.selectEquipment(nil) }
                        }

                        ForEach(viewModel.equipmentOptions) { item in
                            Button(item.name) {
                                Task { await viewModel.selectEquipment(item) }
                            }
                        }
                    }
                }

                filterMenu(
                    title: "Паттерн",
                    value: viewModel.filters.movementPattern?.label ?? "Все",
                ) {
                    Button("Все") {
                        Task { await viewModel.selectMovementPattern(nil) }
                    }

                    ForEach(viewModel.movementPatternOptions, id: \.rawValue) { item in
                        Button(item.label) {
                            Task { await viewModel.selectMovementPattern(item) }
                        }
                    }
                }

                filterMenu(
                    title: "Сложность",
                    value: viewModel.filters.difficultyLevel?.label ?? "Все",
                ) {
                    Button("Все") {
                        Task { await viewModel.selectDifficulty(nil) }
                    }

                    ForEach(viewModel.difficultyOptions, id: \.rawValue) { item in
                        Button(item.label) {
                            Task { await viewModel.selectDifficulty(item) }
                        }
                    }
                }
            }
            .padding(.vertical, FFSpacing.xxs)
        }
    }

    private var searchCardSubtitle: String {
        if viewModel.isContextualBrowsing {
            return "Каталог уже сужен под выбранные мышцы и доступное оборудование. Ниже можно только уточнить выбор."
        }
        return "Сначала ищите по каталогу, а ниже доступны честные локальные подсказки из ваших данных."
    }

    private var searchFieldHelperText: String {
        if viewModel.isContextualBrowsing {
            return "Контекст тренировки уже применён к catalog search."
        }
        return "Поиск работает через athlete exercise catalog"
    }

    private func contextChip(_ title: String, accent: Bool = false) -> some View {
        Text(title)
            .font(FFTypography.caption.weight(.semibold))
            .foregroundStyle(accent ? FFColors.background : FFColors.textSecondary)
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xs)
            .background(accent ? FFColors.accent : FFColors.surface)
            .clipShape(Capsule())
    }

    private func filterMenu<Content: View>(
        title: String,
        value: String,
        @ViewBuilder content: () -> Content,
    ) -> some View {
        Menu {
            content()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                Text(value)
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)
            }
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xs)
            .background(FFColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                    .stroke(FFColors.gray700, lineWidth: 1)
            }
        }
    }

    private var loadingCard: some View {
        FFCard {
            HStack(spacing: FFSpacing.sm) {
                ProgressView()
                Text("Загружаем каталог упражнений...")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
            }
        }
    }

    private var emptyCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Ничего не найдено")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Text(viewModel.statusMessage ?? "Попробуйте другой запрос или снимите фильтры.")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)

                FFButton(title: "Повторить", variant: .secondary) {
                    Task { await viewModel.retry() }
                }
            }
        }
    }

    private func statusCard(message: String) -> some View {
        FFCard {
            HStack(alignment: .top, spacing: FFSpacing.sm) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FFColors.textSecondary)
                Text(message)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                Spacer(minLength: 0)
            }
        }
    }

    private func sectionCard(_ section: ExercisePickerSection) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text(sectionEyebrow(for: section))
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(sectionAccent(for: section))
                    Text(section.title)
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    if let subtitle = section.subtitle {
                        Text(subtitle)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }

                ForEach(section.items) { item in
                    exerciseRow(item)
                }
            }
        }
    }

    private func exerciseRow(_ exercise: ExerciseCatalogItem) -> some View {
        let isSelected = selectedExerciseIDs.contains(exercise.id)

        return HStack(alignment: .top, spacing: FFSpacing.sm) {
            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                Text(exercise.name)
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)

                Text(exercisePickerSummary(for: exercise))
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)

                if let sourceLabel = exercisePickerSourceLabel(for: exercise) {
                    Text(sourceLabel)
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(FFColors.primary)
                        .padding(.horizontal, FFSpacing.xs)
                        .padding(.vertical, FFSpacing.xxs)
                        .background(FFColors.primary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Spacer(minLength: FFSpacing.sm)

            Button {
                guard !isSelected else { return }
                onAdd(exercise)
            } label: {
                Text(isSelected ? "Добавлено" : "Добавить")
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? FFColors.textSecondary : FFColors.accent)
                    .padding(.horizontal, FFSpacing.sm)
                    .padding(.vertical, FFSpacing.xs)
                    .background(FFColors.surface)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(isSelected ? FFColors.gray700 : FFColors.accent.opacity(0.4), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isSelected)
            .accessibilityLabel("\(exercise.name), \(isSelected ? "уже добавлено" : "добавить")")
        }
        .padding(.vertical, FFSpacing.xxs)
        .padding(.horizontal, FFSpacing.xs)
        .padding(.vertical, FFSpacing.sm)
        .background(FFColors.surface.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
    }

    private func sectionEyebrow(for section: ExercisePickerSection) -> String {
        switch section.kind {
        case .recent:
            return "RECENT"
        case .templates:
            return "TEMPLATES"
        case .localMatches:
            return "MATCHES"
        case .catalogResults:
            return "CATALOG"
        }
    }

    private func sectionAccent(for section: ExercisePickerSection) -> Color {
        switch section.kind {
        case .recent:
            return FFColors.primary
        case .templates:
            return FFColors.accent
        case .localMatches:
            return FFColors.primary
        case .catalogResults:
            return FFColors.textSecondary
        }
    }

    private var contractGapCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Ограничения контракта")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                ForEach(viewModel.contractGaps.prefix(3), id: \.self) { gap in
                    Text("• \(gap)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }
}

private struct DatedCatalogItem: Sendable {
    let date: Date
    let item: ExerciseCatalogItem
}

private extension ExerciseCatalogItem {
    var pickerSummaryText: String {
        if let defaults = draftDefaults {
            let minReps = max(1, defaults.repsMin ?? 8)
            let maxReps = max(minReps, defaults.repsMax ?? max(minReps, 10))
            let rest = max(0, defaults.restSeconds ?? 90)
            return "\(max(1, defaults.sets)) подхода • \(minReps)-\(maxReps) повторов • отдых \(rest) сек"
        }

        var parts: [String] = []
        if let movementPattern {
            parts.append(movementPattern.label)
        }
        if let difficultyLevel {
            parts.append(difficultyLevel.label)
        }
        let muscleText = muscles.compactMap { $0.muscleGroup?.label }.uniqueStrings().joined(separator: ", ")
        if !muscleText.isEmpty {
            parts.append(muscleText)
        }
        if !equipment.isEmpty {
            parts.append(equipment.map(\.name).joined(separator: ", "))
        } else if isBodyweight == true {
            parts.append("С собственным весом")
        }
        return parts.isEmpty ? "Параметры задаются после добавления." : parts.joined(separator: " • ")
    }
}

private func exercisePickerSummary(for exercise: ExerciseCatalogItem) -> String {
    exercise.pickerSummaryText
}

private func exercisePickerSourceLabel(for exercise: ExerciseCatalogItem) -> String? {
    switch exercise.source {
    case .athleteCatalog:
        return nil
    case .savedTemplate:
        return "Шаблон"
    case .workoutPayload:
        return "Недавнее"
    }
}

private extension Array where Element == ExerciseCatalogItem {
    func uniqueByCatalogID() -> [ExerciseCatalogItem] {
        var seen = Set<String>()
        var result: [ExerciseCatalogItem] = []

        for item in self {
            guard seen.insert(item.id).inserted else { continue }
            result.append(item)
        }

        return result
    }
}

private extension Array where Element == String {
    func removingDuplicateStrings() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }

    func uniqueStrings() -> [String] {
        removingDuplicateStrings()
    }
}

private extension ExerciseCatalogMovementPattern {
    var label: String {
        switch self {
        case .push:
            "Push"
        case .pull:
            "Pull"
        case .squat:
            "Squat"
        case .hinge:
            "Hinge"
        case .other:
            "Other"
        }
    }
}

private extension ExerciseCatalogDifficultyLevel {
    var label: String {
        switch self {
        case .beginner:
            "Beginner"
        case .intermediate:
            "Intermediate"
        case .advanced:
            "Advanced"
        }
    }
}

private extension ExerciseCatalogMuscleGroup {
    static let pickerOptions: [ExerciseCatalogMuscleGroup] = [
        .back,
        .chest,
        .legs,
        .shoulders,
        .arms,
        .abs,
    ]

    var label: String {
        switch self {
        case .back:
            "Спина"
        case .chest:
            "Грудь"
        case .legs:
            "Ноги"
        case .shoulders:
            "Плечи"
        case .arms:
            "Руки"
        case .abs:
            "Пресс"
        }
    }
}

private extension ExerciseCatalogMovementPattern {
    static let pickerOptions: [ExerciseCatalogMovementPattern] = [
        .push,
        .pull,
        .squat,
        .hinge,
        .other,
    ]
}

private extension ExerciseCatalogDifficultyLevel {
    static let pickerOptions: [ExerciseCatalogDifficultyLevel] = [
        .beginner,
        .intermediate,
        .advanced,
    ]
}
