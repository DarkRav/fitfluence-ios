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
                    subtitle: "Упражнения из вашей библиотеки шаблонов",
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
        var muscleGroups: [ExerciseCatalogMuscleGroup] = []
        var equipment: [ExerciseCatalogEquipment] = []
        var movementPatterns: [ExerciseCatalogMovementPattern] = []
        var difficultyLevels: [ExerciseCatalogDifficultyLevel] = []

        var isActive: Bool {
            !muscleGroups.isEmpty || !equipment.isEmpty || !movementPatterns.isEmpty || !difficultyLevels.isEmpty
        }
    }

    struct ContextualFilterOptions: Equatable, Sendable {
        var equipment: [ExerciseCatalogEquipment]
        var movementPatterns: [ExerciseCatalogMovementPattern]
        var difficultyLevels: [ExerciseCatalogDifficultyLevel]
    }

    private enum FilterDimension: Hashable {
        case muscleGroups
        case equipment
        case movementPatterns
        case difficultyLevels
    }

    enum BrowseMode: String, CaseIterable, Sendable {
        case guided
        case catalog

        var title: String {
            switch self {
            case .guided:
                "Под вас"
            case .catalog:
                "Каталог"
            }
        }

        var subtitle: String {
            switch self {
            case .guided:
                "Недавние, шаблоны и локальные совпадения"
            case .catalog:
                "Все упражнения без лишнего шума"
            }
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
    var browseMode: BrowseMode = .guided
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

    func applyFilters(_ value: FilterState) async {
        filters = value
        await reloadCatalog()
    }

    func toggleMuscleGroup(_ value: ExerciseCatalogMuscleGroup) async {
        if filters.muscleGroups.contains(value) {
            filters.muscleGroups.removeAll { $0 == value }
        } else {
            filters.muscleGroups.append(value)
            filters.muscleGroups.sort(by: { $0.sortOrder < $1.sortOrder })
        }
        await reloadCatalog()
    }

    func removeMuscleGroup(_ value: ExerciseCatalogMuscleGroup) async {
        filters.muscleGroups.removeAll { $0 == value }
        await reloadCatalog()
    }

    func toggleEquipment(_ value: ExerciseCatalogEquipment) async {
        if filters.equipment.contains(where: { $0.id == value.id }) {
            filters.equipment.removeAll { $0.id == value.id }
        } else {
            filters.equipment.append(value)
            filters.equipment.sort(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
        await reloadCatalog()
    }

    func removeEquipment(_ value: ExerciseCatalogEquipment) async {
        filters.equipment.removeAll { $0.id == value.id }
        await reloadCatalog()
    }

    func toggleMovementPattern(_ value: ExerciseCatalogMovementPattern) async {
        if filters.movementPatterns.contains(value) {
            filters.movementPatterns.removeAll { $0 == value }
        } else {
            filters.movementPatterns.append(value)
            filters.movementPatterns.sort(by: { $0.pickerSortRank < $1.pickerSortRank })
        }
        await reloadCatalog()
    }

    func removeMovementPattern(_ value: ExerciseCatalogMovementPattern) async {
        filters.movementPatterns.removeAll { $0 == value }
        await reloadCatalog()
    }

    func toggleDifficulty(_ value: ExerciseCatalogDifficultyLevel) async {
        if filters.difficultyLevels.contains(value) {
            filters.difficultyLevels.removeAll { $0 == value }
        } else {
            filters.difficultyLevels.append(value)
            filters.difficultyLevels.sort(by: { $0.pickerSortRank < $1.pickerSortRank })
        }
        await reloadCatalog()
    }

    func removeDifficulty(_ value: ExerciseCatalogDifficultyLevel) async {
        filters.difficultyLevels.removeAll { $0 == value }
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

    var hasGuidedSuggestions: Bool {
        suggestionsSnapshot.sections.contains { !$0.items.isEmpty }
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

    func contextualFilterOptions(for filters: FilterState) async -> ContextualFilterOptions {
        let result = await repository.search(query: contextualFilterQuery(for: filters))
        let scopedItems = result.items

        let derivedEquipment = deriveEquipmentOptions(from: scopedItems, filters: filters)
        let derivedMovementPatterns = deriveMovementPatternOptions(from: scopedItems, filters: filters)
        let derivedDifficultyLevels = deriveDifficultyOptions(from: scopedItems, filters: filters)

        return ContextualFilterOptions(
            equipment: derivedEquipment.isEmpty ? equipmentOptions : derivedEquipment,
            movementPatterns: derivedMovementPatterns.isEmpty ? movementPatternOptions : derivedMovementPatterns,
            difficultyLevels: derivedDifficultyLevels.isEmpty ? difficultyOptions : derivedDifficultyLevels,
        )
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
            if !filteredCatalogItems.isEmpty {
                sections.append(
                    ExercisePickerSection(
                        kind: .catalogResults,
                        title: "Результаты каталога",
                        subtitle: catalogSectionSubtitle,
                        items: filteredCatalogItems,
                    ),
                )
            }
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
            return sections
        }

        if browseMode == .guided {
            sections.append(contentsOf: suggestionsSnapshot.sections.filter { !$0.items.isEmpty })
            return sections
        }

        if !filteredCatalogItems.isEmpty {
            sections.append(
                ExercisePickerSection(
                    kind: .catalogResults,
                    title: "Все упражнения",
                    subtitle: catalogSectionSubtitle,
                    items: filteredCatalogItems,
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
            movementPattern: filters.movementPatterns.count == 1 ? filters.movementPatterns.first : nil,
            difficultyLevel: filters.difficultyLevels.count == 1 ? filters.difficultyLevels.first : nil,
            muscleGroups: filters.muscleGroups.isEmpty ? context.muscleGroups : filters.muscleGroups,
            equipmentIds: filters.equipment.isEmpty ? context.equipmentIDs : filters.equipment.map(\.id),
        )
    }

    private var filteredCatalogItems: [ExerciseCatalogItem] {
        catalogItems.filter(matchesActiveQuery)
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
        matchesFilters(item, filters: filters)
    }

    private func matchesFilters(
        _ item: ExerciseCatalogItem,
        filters: FilterState,
        excluding excludedDimensions: Set<FilterDimension> = []
    ) -> Bool {
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

        let effectiveMuscleGroups = excludedDimensions.contains(.muscleGroups)
            ? []
            : (filters.muscleGroups.isEmpty ? context.muscleGroups : filters.muscleGroups)
        let effectiveEquipmentIDs = excludedDimensions.contains(.equipment)
            ? Set<String>()
            : Set((filters.equipment.isEmpty ? contextualEquipmentSeedIDs : filters.equipment.map(\.id)))

        if !excludedDimensions.contains(.movementPatterns),
           !filters.movementPatterns.isEmpty,
           !filters.movementPatterns.contains(where: { $0 == item.movementPattern })
        {
            return false
        }
        if !excludedDimensions.contains(.difficultyLevels),
           !filters.difficultyLevels.isEmpty,
           !filters.difficultyLevels.contains(where: { $0 == item.difficultyLevel })
        {
            return false
        }
        if !effectiveMuscleGroups.isEmpty {
            let itemGroups = Set(item.muscles.compactMap(\.muscleGroup))
            guard !itemGroups.isDisjoint(with: effectiveMuscleGroups) else {
                return false
            }
        }
        if !effectiveEquipmentIDs.isEmpty {
            let itemEquipmentIDs = Set(item.equipment.map(\.id))
            guard !itemEquipmentIDs.isDisjoint(with: effectiveEquipmentIDs) else {
                return false
            }
        }

        return true
    }

    private var contextualEquipmentSeedIDs: [String] {
        context.equipmentIDs
    }

    private func contextualFilterQuery(for filters: FilterState) -> ExerciseCatalogQuery {
        ExerciseCatalogQuery(
            search: trimmedSearch,
            page: 0,
            size: 80,
            muscleGroups: filters.muscleGroups.isEmpty ? context.muscleGroups : filters.muscleGroups,
            equipmentIds: contextualEquipmentSeedIDs
        )
    }

    private func deriveEquipmentOptions(from items: [ExerciseCatalogItem], filters: FilterState) -> [ExerciseCatalogEquipment] {
        items
            .filter { matchesFilters($0, filters: filters, excluding: [.equipment]) }
            .flatMap(\.equipment)
            .reduce(into: [String: ExerciseCatalogEquipment]()) { partial, equipment in
                partial[equipment.id] = equipment
            }
            .values
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func deriveMovementPatternOptions(from items: [ExerciseCatalogItem], filters: FilterState) -> [ExerciseCatalogMovementPattern] {
        let patterns = items
            .filter { matchesFilters($0, filters: filters, excluding: [.movementPatterns]) }
            .compactMap(\.movementPattern)

        return Array(Set(patterns))
            .sorted(by: { $0.pickerSortRank < $1.pickerSortRank })
    }

    private func deriveDifficultyOptions(from items: [ExerciseCatalogItem], filters: FilterState) -> [ExerciseCatalogDifficultyLevel] {
        let difficultyLevels = items
            .filter { matchesFilters($0, filters: filters, excluding: [.difficultyLevels]) }
            .compactMap(\.difficultyLevel)

        return Array(Set(difficultyLevels))
            .sorted(by: { $0.pickerSortRank < $1.pickerSortRank })
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
        if !hasGuidedSuggestions, browseMode == .guided {
            browseMode = .catalog
        }
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
    @State private var pendingSelectionOrder: [String] = []
    @State private var pendingSelectionByID: [String: ExerciseCatalogItem] = [:]
    @State private var isFilterStudioPresented = false
    @State private var presentedExercise: ExerciseCatalogItem?

    let selectedExerciseIDs: Set<String>
    let onSaveSelection: ([ExerciseCatalogItem]) -> Void

    init(
        repository: any ExerciseCatalogRepository = BackendExerciseCatalogRepository(
            apiClient: nil,
            userSub: nil,
        ),
        suggestionsProvider: any ExercisePickerSuggestionsProviding = EmptyExercisePickerSuggestionsProvider(),
        context: ExercisePickerViewModel.Context = .init(),
        selectedExerciseIDs: Set<String> = [],
        onSaveSelection: @escaping ([ExerciseCatalogItem]) -> Void,
    ) {
        _viewModel = State(
            initialValue: ExercisePickerViewModel(
                repository: repository,
                suggestionsProvider: suggestionsProvider,
                context: context,
            ),
        )
        self.selectedExerciseIDs = selectedExerciseIDs
        self.onSaveSelection = onSaveSelection
    }

    var body: some View {
        ZStack {
            FFColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: FFSpacing.md) {
                    TrainingBuilderSectionCard(
                        eyebrow: nil,
                        title: "Найдите упражнения",
                        helper: ""
                    ) {
                        VStack(alignment: .leading, spacing: FFSpacing.sm) {
                            if !viewModel.contextChips.isEmpty || viewModel.contextTitle != nil {
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

                            if availableBrowseModes.count > 1 {
                                browseModeControl
                            }

                            filterSummaryRow

                            if !activeSelectionChips.isEmpty {
                                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                                    HStack {
                                        Text("Активные фильтры")
                                            .font(FFTypography.caption.weight(.semibold))
                                            .foregroundStyle(FFColors.textSecondary)
                                        Spacer()
                                        Button("Очистить") {
                                            Task { await viewModel.clearFilters() }
                                        }
                                        .font(FFTypography.caption.weight(.semibold))
                                        .foregroundStyle(FFColors.accent)
                                    }
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: FFSpacing.xs) {
                                            ForEach(viewModel.filters.muscleGroups, id: \.rawValue) { muscleGroup in
                                                activeFilterChip(
                                                    title: muscleGroup.label,
                                                    action: { Task { await viewModel.removeMuscleGroup(muscleGroup) } }
                                                )
                                            }
                                            ForEach(viewModel.filters.equipment, id: \.id) { equipment in
                                                activeFilterChip(
                                                    title: equipment.name,
                                                    action: { Task { await viewModel.removeEquipment(equipment) } }
                                                )
                                            }
                                            ForEach(viewModel.filters.movementPatterns, id: \.rawValue) { movementPattern in
                                                activeFilterChip(
                                                    title: movementPattern.label,
                                                    action: { Task { await viewModel.removeMovementPattern(movementPattern) } }
                                                )
                                            }
                                            ForEach(viewModel.filters.difficultyLevels, id: \.rawValue) { difficultyLevel in
                                                activeFilterChip(
                                                    title: difficultyLevel.label,
                                                    action: { Task { await viewModel.removeDifficulty(difficultyLevel) } }
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !pendingSelectionOrder.isEmpty {
                        selectionPreviewCard
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
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.md)
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomSelectionBar
        }
        .navigationTitle("Каталог упражнений")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Закрыть") {
                    dismiss()
                }
                .foregroundStyle(FFColors.textSecondary)
            }
        }
        .fullScreenCover(isPresented: $isFilterStudioPresented) {
            ExercisePickerFilterStudio(
                filters: viewModel.filters,
                muscleGroupOptions: viewModel.muscleGroupOptions,
                equipmentOptions: viewModel.equipmentOptions,
                movementPatternOptions: viewModel.movementPatternOptions,
                difficultyOptions: viewModel.difficultyOptions,
                loadContextualOptions: { filters in
                    await viewModel.contextualFilterOptions(for: filters)
                },
                onApply: { filters in
                    Task { await viewModel.applyFilters(filters) }
                },
                onReset: {
                    Task { await viewModel.clearFilters() }
                }
            )
        }
        .task {
            await viewModel.onAppear()
        }
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.searchQueryChanged()
        }
        .sheet(item: $presentedExercise) { exercise in
            NavigationStack {
                ExerciseDetailsSheet(exercise: exercise)
            }
        }
    }

    private var browseModeControl: some View {
        HStack(spacing: FFSpacing.xs) {
            ForEach(availableBrowseModes, id: \.rawValue) { mode in
                TrainingBuilderChoiceTile(
                    title: mode.title,
                    subtitle: mode.subtitle,
                    isSelected: viewModel.browseMode == mode
                ) {
                    viewModel.browseMode = mode
                }
            }
        }
    }

    private var availableBrowseModes: [ExercisePickerViewModel.BrowseMode] {
        viewModel.hasGuidedSuggestions ? ExercisePickerViewModel.BrowseMode.allCases : [.catalog]
    }

    private var filterSummaryRow: some View {
        HStack(spacing: FFSpacing.xs) {
            Button {
                isFilterStudioPresented = true
            } label: {
                HStack(spacing: FFSpacing.xs) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(filterSummaryTitle)
                            .font(FFTypography.body.weight(.semibold))
                        Text(filterSummarySubtitle)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FFColors.textSecondary)
                }
                .padding(.horizontal, FFSpacing.sm)
                .padding(.vertical, FFSpacing.sm)
                .background(FFColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                        .stroke(FFColors.gray700, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var selectionPreviewCard: some View {
        TrainingBuilderSectionCard(
            eyebrow: "Выбрано",
            title: "\(pendingSelectionOrder.count) \(selectionNoun(for: pendingSelectionOrder.count))",
            helper: ""
        ) {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack(alignment: .top, spacing: FFSpacing.sm) {
                    Spacer()
                    Button("Очистить") {
                        pendingSelectionOrder.removeAll()
                        pendingSelectionByID.removeAll()
                    }
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.accent)
                }

                VStack(spacing: FFSpacing.xs) {
                    ForEach(pendingSelectionOrder, id: \.self) { id in
                        if let item = pendingSelectionByID[id] {
                            pendingSelectionRow(item)
                        }
                    }
                }
            }
        }
    }

    private var searchFieldHelperText: String {
        if viewModel.isContextualBrowsing {
            return "Учитываем текущую тренировку и оборудование."
        }
        return "Поиск по названию и быстрые фильтры."
    }

    private var filterSummaryTitle: String {
        viewModel.filters.isActive ? "Фильтры: \(activeSelectionChips.count)" : "Фильтры"
    }

    private var filterSummarySubtitle: String {
        if viewModel.filters.isActive {
            return activeSelectionChips.joined(separator: " • ")
        }
        return "Группы мышц, оборудование и сложность"
    }

    private func contextChip(_ title: String, accent: Bool = false) -> some View {
        TrainingBuilderBadge(title: title, isAccent: accent)
    }

    @ViewBuilder
    private func activeFilterChip(title: String?, action: @escaping () -> Void) -> some View {
        if let title {
            Button(action: action) {
                HStack(spacing: FFSpacing.xs) {
                    Text(title)
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.background)
                .padding(.horizontal, FFSpacing.sm)
                .padding(.vertical, FFSpacing.xs)
                .background(FFColors.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
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
        TrainingBuilderSectionCard(
            eyebrow: nil,
            title: "Ничего не найдено",
            helper: viewModel.statusMessage ?? "Попробуйте другой запрос или ослабьте фильтры."
        ) {
            HStack(spacing: FFSpacing.sm) {
                FFButton(title: "Повторить", variant: .secondary) {
                    Task { await viewModel.retry() }
                }
                if viewModel.filters.isActive {
                    FFButton(title: "Сбросить фильтры", variant: .secondary) {
                        Task { await viewModel.clearFilters() }
                    }
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

    @ViewBuilder
    private func sectionCard(_ section: ExercisePickerSection) -> some View {
        if section.kind == .catalogResults {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                sectionHeader(section)
                ForEach(section.items) { item in
                    exerciseRow(item)
                }
            }
        } else {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    sectionHeader(section)

                    ForEach(section.items) { item in
                        exerciseRow(item)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ section: ExercisePickerSection) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: FFSpacing.xs) {
                Text(section.title)
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Text("\(section.items.count)")
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.textSecondary)
            }
            if let subtitle = section.subtitle {
                Text(subtitle)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
            }
        }
    }

    private func exerciseRow(_ exercise: ExerciseCatalogItem) -> some View {
        let isAlreadyAdded = selectedExerciseIDs.contains(exercise.id)
        let isPending = pendingSelectionByID[exercise.id] != nil

        return VStack(alignment: .leading, spacing: FFSpacing.sm) {
            HStack(alignment: .top, spacing: FFSpacing.sm) {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    HStack(alignment: .top, spacing: FFSpacing.xs) {
                        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                            Text(exercise.name)
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
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
                            toggleSelection(for: exercise)
                        } label: {
                            selectionPill(
                                title: isAlreadyAdded ? "Уже в тренировке" : (isPending ? "Выбрано" : "Выбрать"),
                                isActive: isPending,
                                isDisabled: isAlreadyAdded,
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isAlreadyAdded)
                    }

                    if !exercisePickerTags(for: exercise).isEmpty {
                        exerciseTagRow(tags: exercisePickerTags(for: exercise))
                    }

                    Text(exercisePickerSummary(for: exercise))
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }

            HStack(spacing: FFSpacing.xs) {
                Label("Открыть детали", systemImage: "info.circle")
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.textSecondary)
                Spacer(minLength: 0)
            }
        }
        .padding(FFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackgroundColor(isAlreadyAdded: isAlreadyAdded, isPending: isPending))
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.card)
                .stroke(rowBorderColor(isAlreadyAdded: isAlreadyAdded, isPending: isPending), lineWidth: 1)
        }
        .shadow(color: FFTheme.Shadow.color.opacity(isPending ? 1 : 0.55), radius: FFTheme.Shadow.radius, y: FFTheme.Shadow.y)
        .contentShape(RoundedRectangle(cornerRadius: FFTheme.Radius.card))
        .onTapGesture {
            presentedExercise = exercise
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(exercise.name), \(isAlreadyAdded ? "уже добавлено" : (isPending ? "выбрано" : "не выбрано"))")
    }

    private var bottomSelectionBar: some View {
        TrainingBuilderBottomBar(
            helper: "Отметьте упражнения и добавьте их в тренировку.",
            title: addSelectionTitle,
            summary: pendingSelectionOrder.isEmpty ? nil : "Вернём их в тренировку",
            buttonVariant: pendingSelectionOrder.isEmpty ? .disabled : .primary
        ) {
            commitSelection()
        }
    }

    private var activeSelectionChips: [String] {
        viewModel.filters.muscleGroups.map(\.label)
            + viewModel.filters.equipment.map(\.name)
            + viewModel.filters.movementPatterns.map(\.label)
            + viewModel.filters.difficultyLevels.map(\.label)
    }

    private func selectionNoun(for count: Int) -> String {
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

    private var addSelectionTitle: String {
        let count = pendingSelectionOrder.count
        let noun: String
        let remainder10 = count % 10
        let remainder100 = count % 100
        if remainder10 == 1, remainder100 != 11 {
            noun = "упражнение"
        } else if (2 ... 4).contains(remainder10), !(12 ... 14).contains(remainder100) {
            noun = "упражнения"
        } else {
            noun = "упражнений"
        }
        return "Добавить \(count) \(noun) в тренировку"
    }

    private func toggleSelection(for exercise: ExerciseCatalogItem) {
        guard !selectedExerciseIDs.contains(exercise.id) else { return }
        if pendingSelectionByID[exercise.id] != nil {
            pendingSelectionByID.removeValue(forKey: exercise.id)
            pendingSelectionOrder.removeAll { $0 == exercise.id }
            return
        }
        pendingSelectionByID[exercise.id] = exercise
        pendingSelectionOrder.append(exercise.id)
    }

    private func commitSelection() {
        let items = pendingSelectionOrder.compactMap { pendingSelectionByID[$0] }
        guard !items.isEmpty else { return }
        onSaveSelection(items)
        dismiss()
    }

    private func rowBackgroundColor(isAlreadyAdded: Bool, isPending: Bool) -> Color {
        if isAlreadyAdded {
            return FFColors.surface.opacity(0.35)
        }
        if isPending {
            return FFColors.accent.opacity(0.12)
        }
        return FFColors.surface.opacity(0.62)
    }

    private func rowBorderColor(isAlreadyAdded: Bool, isPending: Bool) -> Color {
        if isAlreadyAdded {
            return FFColors.gray700.opacity(0.8)
        }
        if isPending {
            return FFColors.accent.opacity(0.55)
        }
        return FFColors.gray700.opacity(0.65)
    }

    private func selectionPill(title: String, isActive: Bool, isDisabled: Bool) -> some View {
        Text(title)
            .font(FFTypography.caption.weight(.semibold))
            .foregroundStyle(
                isDisabled ? FFColors.textSecondary : (isActive ? FFColors.background : FFColors.accent)
            )
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xs)
            .background(
                isDisabled ? FFColors.surface : (isActive ? FFColors.accent : FFColors.surface)
            )
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(
                        isDisabled ? FFColors.gray700 : (isActive ? FFColors.accent : FFColors.accent.opacity(0.4)),
                        lineWidth: 1
                    )
            }
    }

    private func pendingSelectionRow(_ exercise: ExerciseCatalogItem) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            HStack(alignment: .top, spacing: FFSpacing.xs) {
                Text(exercise.name)
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    pendingSelectionByID.removeValue(forKey: exercise.id)
                    pendingSelectionOrder.removeAll { $0 == exercise.id }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(FFColors.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(FFColors.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            let tags = exercisePickerTags(for: exercise)
            if !tags.isEmpty {
                exerciseTagRow(tags: tags)
            }
        }
        .padding(FFSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .stroke(FFColors.gray700, lineWidth: 1)
        }
    }

    private func exerciseTagRow(tags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FFSpacing.xs) {
                ForEach(tags, id: \.self) { tag in
                    contextChip(tag)
                }
            }
        }
    }
}

private struct ExercisePickerFilterStudio: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draftFilters: ExercisePickerViewModel.FilterState
    @State private var contextualEquipmentOptions: [ExerciseCatalogEquipment]
    @State private var contextualMovementPatternOptions: [ExerciseCatalogMovementPattern]
    @State private var contextualDifficultyOptions: [ExerciseCatalogDifficultyLevel]
    @State private var isLoadingEquipment = false

    let muscleGroupOptions: [ExerciseCatalogMuscleGroup]
    let loadContextualOptions: (ExercisePickerViewModel.FilterState) async -> ExercisePickerViewModel.ContextualFilterOptions
    let onApply: (ExercisePickerViewModel.FilterState) -> Void
    let onReset: () -> Void

    init(
        filters: ExercisePickerViewModel.FilterState,
        muscleGroupOptions: [ExerciseCatalogMuscleGroup],
        equipmentOptions: [ExerciseCatalogEquipment],
        movementPatternOptions: [ExerciseCatalogMovementPattern],
        difficultyOptions: [ExerciseCatalogDifficultyLevel],
        loadContextualOptions: @escaping (ExercisePickerViewModel.FilterState) async -> ExercisePickerViewModel.ContextualFilterOptions,
        onApply: @escaping (ExercisePickerViewModel.FilterState) -> Void,
        onReset: @escaping () -> Void,
    ) {
        _draftFilters = State(initialValue: filters)
        _contextualEquipmentOptions = State(initialValue: equipmentOptions)
        _contextualMovementPatternOptions = State(initialValue: movementPatternOptions)
        _contextualDifficultyOptions = State(initialValue: difficultyOptions)
        self.muscleGroupOptions = muscleGroupOptions
        self.loadContextualOptions = loadContextualOptions
        self.onApply = onApply
        self.onReset = onReset
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FFColors.background
                    .ignoresSafeArea()

                ScrollView { filterContent }
            }
            .task {
                await refreshEquipmentOptions()
            }
            .onChange(of: draftFilters) { _, _ in
                Task {
                    await refreshEquipmentOptions()
                }
            }
            .safeAreaInset(edge: .bottom) {
                TrainingBuilderBottomBar(
                    helper: "Примените фильтры или сбросьте всё.",
                    title: "Применить фильтры",
                    summary: activeFilterSummary,
                    buttonVariant: .primary
                ) {
                    onApply(draftFilters)
                    dismiss()
                }
            }
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        dismiss()
                    }
                    .foregroundStyle(FFColors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сбросить") {
                        draftFilters = .init()
                        onReset()
                        dismiss()
                    }
                    .foregroundStyle(FFColors.accent)
                }
            }
        }
    }

    private var filterContent: some View {
        VStack(alignment: .leading, spacing: FFSpacing.md) {
            muscleGroupSection

            if !contextualEquipmentOptions.isEmpty {
                equipmentSection
            }

            movementPatternSection
            difficultySection
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.vertical, FFSpacing.md)
    }

    private var muscleGroupSection: some View {
        filterCard(
            eyebrow: nil,
            title: "Группа мышц",
            helper: ""
        ) {
            chipGrid(items: muscleGroupOptions, id: \.rawValue) { item in
                filterChoiceChip(
                    title: item.label,
                    isSelected: draftFilters.muscleGroups.contains(item)
                ) {
                    toggleMuscleGroup(item)
                }
            }
        }
    }

    private var equipmentSection: some View {
        filterCard(
            eyebrow: nil,
            title: "Оборудование",
            helper: isLoadingEquipment ? "Обновляем доступное оборудование." : ""
        ) {
            chipGrid(items: contextualEquipmentOptions, id: \.id) { item in
                filterChoiceChip(
                    title: item.name,
                    isSelected: draftFilters.equipment.contains(where: { $0.id == item.id })
                ) {
                    toggleEquipment(item)
                }
            }
        }
    }

    private var movementPatternSection: some View {
        filterCard(
            eyebrow: nil,
            title: "Паттерн движения",
            helper: ""
        ) {
                            chipGrid(items: contextualMovementPatternOptions, id: \.rawValue) { item in
                filterChoiceChip(
                    title: item.label,
                    isSelected: draftFilters.movementPatterns.contains(item)
                ) {
                    toggleMovementPattern(item)
                }
            }
        }
    }

    private var difficultySection: some View {
        filterCard(
            eyebrow: nil,
            title: "Сложность",
            helper: ""
        ) {
                            chipGrid(items: contextualDifficultyOptions, id: \.rawValue) { item in
                filterChoiceChip(
                    title: item.label,
                    isSelected: draftFilters.difficultyLevels.contains(item)
                ) {
                    toggleDifficulty(item)
                }
            }
        }
    }

    private func filterCard<Content: View>(
        eyebrow: String?,
        title: String,
        helper: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        TrainingBuilderSectionCard(eyebrow: eyebrow, title: title, helper: helper) {
            content()
        }
    }

    private func chipGrid<Item, ID: Hashable, Content: View>(
        items: [Item],
        id: KeyPath<Item, ID>,
        @ViewBuilder content: @escaping (Item) -> Content,
    ) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: FFSpacing.xs)], spacing: FFSpacing.xs) {
            ForEach(items, id: id) { item in
                content(item)
            }
        }
    }

    private func filterChoiceChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FFTypography.caption.weight(.semibold))
                .padding(.horizontal, FFSpacing.sm)
                .padding(.vertical, FFSpacing.xs)
                .frame(maxWidth: .infinity)
                .ffSelectableSurface(isSelected: isSelected, emphasis: .primary)
        }
        .buttonStyle(.plain)
    }

    private var activeFilterSummary: String? {
        let parts = [
            normalizePickerText(draftFilters.muscleGroups.map(\.label).joined(separator: ", ")),
            normalizePickerText(draftFilters.equipment.map(\.name).joined(separator: ", ")),
            normalizePickerText(draftFilters.movementPatterns.map(\.label).joined(separator: ", ")),
            normalizePickerText(draftFilters.difficultyLevels.map(\.label).joined(separator: ", ")),
        ]
        .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func refreshEquipmentOptions() async {
        isLoadingEquipment = true
        let options = await loadContextualOptions(draftFilters)
        contextualEquipmentOptions = options.equipment
        contextualMovementPatternOptions = options.movementPatterns
        contextualDifficultyOptions = options.difficultyLevels
        let allowedIDs = Set(options.equipment.map(\.id))
        draftFilters.equipment.removeAll { !allowedIDs.contains($0.id) }
        let allowedPatterns = Set(options.movementPatterns)
        draftFilters.movementPatterns.removeAll { !allowedPatterns.contains($0) }
        let allowedDifficultyLevels = Set(options.difficultyLevels)
        draftFilters.difficultyLevels.removeAll { !allowedDifficultyLevels.contains($0) }
        isLoadingEquipment = false
    }

    private func toggleMuscleGroup(_ item: ExerciseCatalogMuscleGroup) {
        if draftFilters.muscleGroups.contains(item) {
            draftFilters.muscleGroups.removeAll { $0 == item }
        } else {
            draftFilters.muscleGroups.append(item)
            draftFilters.muscleGroups.sort(by: { $0.sortOrder < $1.sortOrder })
        }
    }

    private func toggleEquipment(_ item: ExerciseCatalogEquipment) {
        if draftFilters.equipment.contains(where: { $0.id == item.id }) {
            draftFilters.equipment.removeAll { $0.id == item.id }
        } else {
            draftFilters.equipment.append(item)
            draftFilters.equipment.sort(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    private func toggleMovementPattern(_ item: ExerciseCatalogMovementPattern) {
        if draftFilters.movementPatterns.contains(item) {
            draftFilters.movementPatterns.removeAll { $0 == item }
        } else {
            draftFilters.movementPatterns.append(item)
            draftFilters.movementPatterns.sort(by: { $0.pickerSortRank < $1.pickerSortRank })
        }
    }

    private func toggleDifficulty(_ item: ExerciseCatalogDifficultyLevel) {
        if draftFilters.difficultyLevels.contains(item) {
            draftFilters.difficultyLevels.removeAll { $0 == item }
        } else {
            draftFilters.difficultyLevels.append(item)
            draftFilters.difficultyLevels.sort(by: { $0.pickerSortRank < $1.pickerSortRank })
        }
    }
}

private struct ExerciseDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let exercise: ExerciseCatalogItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FFSpacing.md) {
                if let mediaURL = previewMediaURL {
                    AsyncImage(url: mediaURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            mediaFallback
                        case .empty:
                            ZStack {
                                FFColors.surface
                                ProgressView()
                            }
                        @unknown default:
                            mediaFallback
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.card))
                }

                TrainingBuilderSectionCard(
                    eyebrow: nil,
                    title: exercise.name,
                    helper: exercisePickerSummary(for: exercise)
                ) {
                    VStack(alignment: .leading, spacing: FFSpacing.sm) {
                        let tags = exercisePickerTags(for: exercise)
                        if !tags.isEmpty {
                            exerciseDetailsTagRow(tags: tags)
                        }

                        if let description = normalizePickerText(exercise.description) {
                            detailBlock(title: "Описание", text: description)
                        }

                        if !equipmentList.isEmpty {
                            detailBlock(title: "Оборудование", text: equipmentList)
                        }

                        if !muscleList.isEmpty {
                            detailBlock(title: "Группы мышц", text: muscleList)
                        }

                        if let sourceLabel = exercisePickerSourceLabel(for: exercise) {
                            detailBlock(title: "Источник", text: sourceLabel)
                        }
                    }
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background.ignoresSafeArea())
        .navigationTitle("Упражнение")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Закрыть") {
                    dismiss()
                }
                .foregroundStyle(FFColors.textSecondary)
            }
        }
    }

    private var previewMediaURL: URL? {
        exercise.media
            .compactMap { URL(string: $0.url) }
            .first
    }

    private var mediaFallback: some View {
        ZStack {
            FFColors.surface
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(FFColors.textSecondary)
        }
    }

    private var equipmentList: String {
        exercise.equipment.map(\.name).uniqueStrings().joined(separator: ", ")
    }

    private var muscleList: String {
        exercise.muscles.compactMap { $0.muscleGroup?.label }.uniqueStrings().joined(separator: ", ")
    }

    private func detailBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            Text(title)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textSecondary)
            Text(text)
                .font(FFTypography.body)
                .foregroundStyle(FFColors.textPrimary)
        }
    }

    private func exerciseDetailsTagRow(tags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FFSpacing.xs) {
                ForEach(tags, id: \.self) { tag in
                    TrainingBuilderBadge(title: tag)
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

private func exercisePickerTags(for exercise: ExerciseCatalogItem) -> [String] {
    var tags: [String] = []
    if let movementPattern = exercise.movementPattern?.label {
        tags.append(movementPattern)
    }
    if let difficulty = exercise.difficultyLevel?.label {
        tags.append(difficulty)
    }
    let muscleTags = exercise.muscles
        .compactMap { $0.muscleGroup?.label }
        .uniqueStrings()
    tags.append(contentsOf: muscleTags.prefix(2))
    let equipmentTags = exercise.equipment
        .map(\.name)
        .uniqueStrings()
    tags.append(contentsOf: equipmentTags.prefix(2))
    if tags.isEmpty, exercise.isBodyweight == true {
        tags.append("Свой вес")
    }
    return Array(tags.prefix(4))
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

private func normalizePickerText(_ text: String?) -> String? {
    guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
          !text.isEmpty
    else {
        return nil
    }
    return text
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
    var pickerSortRank: Int {
        switch self {
        case .push:
            0
        case .pull:
            1
        case .squat:
            2
        case .hinge:
            3
        case .other:
            4
        }
    }

    var label: String {
        switch self {
        case .push:
            "Жим"
        case .pull:
            "Тяга"
        case .squat:
            "Присед"
        case .hinge:
            "Наклон"
        case .other:
            "Другое"
        }
    }
}

private extension ExerciseCatalogDifficultyLevel {
    var pickerSortRank: Int {
        switch self {
        case .beginner:
            0
        case .intermediate:
            1
        case .advanced:
            2
        }
    }

    var label: String {
        switch self {
        case .beginner:
            "Начальный"
        case .intermediate:
            "Средний"
        case .advanced:
            "Продвинутый"
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
