import Observation
import SwiftUI

enum TodayWorkoutPlanningFocus: String, Codable, CaseIterable, Equatable, Sendable {
    case strength
    case hypertrophy
    case conditioning

    var title: String {
        switch self {
        case .strength:
            "Сила"
        case .hypertrophy:
            "Масса"
        case .conditioning:
            "Выносливость"
        }
    }

    var subtitle: String {
        switch self {
        case .strength:
            "меньше повторов, больше отдых"
        case .hypertrophy:
            "рабочий базовый объём"
        case .conditioning:
            "плотнее темп, меньше отдых"
        }
    }
}

struct TodayWorkoutPlanningRequest: Equatable, Sendable {
    var targetMuscleGroups: Set<ExerciseCatalogMuscleGroup> = []
    var availableEquipmentIDs: Set<String> = []
    var desiredDurationMinutes: Int?
    var focus: TodayWorkoutPlanningFocus?

    var canBuild: Bool {
        !targetMuscleGroups.isEmpty && desiredDurationMinutes != nil
    }

    var suggestedExerciseCount: Int {
        switch desiredDurationMinutes ?? 0 {
        case ..<35:
            3
        case ..<50:
            4
        case ..<70:
            5
        default:
            6
        }
    }

    mutating func toggleMuscleGroup(_ muscleGroup: ExerciseCatalogMuscleGroup) {
        if targetMuscleGroups.contains(muscleGroup) {
            targetMuscleGroups.remove(muscleGroup)
        } else {
            targetMuscleGroups.insert(muscleGroup)
        }
    }

    mutating func toggleEquipment(id: String) {
        if availableEquipmentIDs.contains(id) {
            availableEquipmentIDs.remove(id)
        } else {
            availableEquipmentIDs.insert(id)
        }
    }
}

struct TodayWorkoutPlanningEquipmentOption: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let category: ExerciseCatalogEquipmentCategory?

    var title: String {
        name
    }
}

struct TodayWorkoutPlanningCatalogSnapshot: Equatable, Sendable {
    let equipmentOptions: [TodayWorkoutPlanningEquipmentOption]
    let allEquipmentOptions: [TodayWorkoutPlanningEquipmentOption]
    let note: String?
    let contractGaps: [String]
    let isCatalogAvailable: Bool

    static let empty = TodayWorkoutPlanningCatalogSnapshot(
        equipmentOptions: [],
        allEquipmentOptions: [],
        note: nil,
        contractGaps: [],
        isCatalogAvailable: false,
    )
}

struct TodayWorkoutPlanningDraftSeed: Equatable, Sendable, Identifiable {
    let id = UUID()
    let request: TodayWorkoutPlanningRequest
    let equipmentOptions: [TodayWorkoutPlanningEquipmentOption]
    let exercises: [WorkoutCompositionExerciseDraft]
    let explanation: TodayWorkoutDraftExplanation
    let matchedMuscleGroups: [ExerciseCatalogMuscleGroup]
    let missingMuscleGroups: [ExerciseCatalogMuscleGroup]
    let coveredMovementPatterns: [ExerciseCatalogMovementPattern]
    let targetExerciseCount: Int
    let targetWorkingSets: Int
    let note: String?
    let contractGaps: [String]
    let isCatalogBacked: Bool
    let isDegraded: Bool

    var draft: WorkoutCompositionDraft {
        WorkoutCompositionDraft(
            title: suggestedTitle,
            exercises: exercises,
        )
    }

    var coachNote: String {
        "План на сегодня • \(summaryLine)"
    }

    var suggestedTitle: String {
        let muscles = request.targetMuscleGroups
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .prefix(2)
            .map(\.title)
            .joined(separator: " + ")

        if let duration = request.desiredDurationMinutes {
            return muscles.isEmpty ? "Тренировка на \(duration) мин" : "\(muscles) • \(duration) мин"
        }

        return muscles.isEmpty ? "Тренировка на сегодня" : muscles
    }

    var summaryLine: String {
        var parts: [String] = []
        let muscles = request.targetMuscleGroups
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .map(\.title)
        if !muscles.isEmpty {
            parts.append(muscles.joined(separator: ", "))
        }
        let equipment = selectedEquipmentNames
        if !equipment.isEmpty {
            parts.append(equipment.joined(separator: ", "))
        }
        if let duration = request.desiredDurationMinutes {
            parts.append("\(duration) мин")
        }
        if let focus = request.focus {
            parts.append(focus.title)
        }
        return parts.joined(separator: " • ")
    }

    var selectedEquipmentNames: [String] {
        equipmentOptions
            .filter { request.availableEquipmentIDs.contains($0.id) }
            .map(\.name)
            .sorted()
    }

    var generationSummary: String {
        if exercises.isEmpty {
            return explanation.summary
        }

        return explanation.summary
    }

    var generationWarnings: [String] {
        explanation.warnings
    }

    var generationAppliedRules: [String] {
        explanation.appliedRules
    }
}

protocol TodayWorkoutPlanningProviding: Sendable {
    func loadCatalogSnapshot(
        for request: TodayWorkoutPlanningRequest
    ) async -> TodayWorkoutPlanningCatalogSnapshot
    func buildDraftSeed(
        for request: TodayWorkoutPlanningRequest,
        snapshot: TodayWorkoutPlanningCatalogSnapshot
    ) async -> TodayWorkoutPlanningDraftSeed
}

struct TodayWorkoutPlanningService: TodayWorkoutPlanningProviding {
    private let repository: any ExerciseCatalogRepository
    private let generator: any TodayWorkoutDraftGenerating

    init(
        repository: any ExerciseCatalogRepository,
        generator: any TodayWorkoutDraftGenerating = TodayWorkoutDraftGenerator(),
    ) {
        self.repository = repository
        self.generator = generator
    }

    func loadCatalogSnapshot(
        for request: TodayWorkoutPlanningRequest
    ) async -> TodayWorkoutPlanningCatalogSnapshot {
        let metadata = await repository.metadata()
        let allEquipmentOptions = equipmentOptions(from: metadata.equipment)
        let contextualEquipmentOptions = await contextualEquipmentOptions(
            request: request,
            fallback: allEquipmentOptions,
        )

        return TodayWorkoutPlanningCatalogSnapshot(
            equipmentOptions: contextualEquipmentOptions,
            allEquipmentOptions: allEquipmentOptions,
            note: nil,
            contractGaps: [],
            isCatalogAvailable: !allEquipmentOptions.isEmpty,
        )
    }

    func buildDraftSeed(
        for request: TodayWorkoutPlanningRequest,
        snapshot: TodayWorkoutPlanningCatalogSnapshot
    ) async -> TodayWorkoutPlanningDraftSeed {
        let result = await repository.search(
            query: ExerciseCatalogQuery(
                page: 0,
                size: 60,
                muscleGroups: request.targetMuscleGroups.sorted(by: { $0.sortOrder < $1.sortOrder }),
                equipmentIds: Array(request.availableEquipmentIDs).sorted(),
            ),
        )
        let broaderItems: [ExerciseCatalogItem]
        if request.availableEquipmentIDs.isEmpty || !result.items.isEmpty {
            broaderItems = result.items
        } else {
            let broaderResult = await repository.search(
                query: ExerciseCatalogQuery(
                    page: 0,
                    size: 60,
                    muscleGroups: request.targetMuscleGroups.sorted(by: { $0.sortOrder < $1.sortOrder }),
                ),
            )
            broaderItems = broaderResult.items
        }

        let generatedDraft = generator.generate(
            request: request,
            catalogItems: result.items,
            broaderCatalogItems: broaderItems,
        )

        return TodayWorkoutPlanningDraftSeed(
            request: request,
            equipmentOptions: snapshot.allEquipmentOptions,
            exercises: generatedDraft.exercises,
            explanation: generatedDraft.explanation,
            matchedMuscleGroups: generatedDraft.matchedMuscleGroups,
            missingMuscleGroups: generatedDraft.missingMuscleGroups,
            coveredMovementPatterns: generatedDraft.coveredMovementPatterns,
            targetExerciseCount: generatedDraft.targetExerciseCount,
            targetWorkingSets: generatedDraft.targetWorkingSets,
            note: result.note ?? snapshot.note,
            contractGaps: Array(Set(snapshot.contractGaps + result.contractGaps)).sorted(),
            isCatalogBacked: !result.items.isEmpty,
            isDegraded: generatedDraft.isDegraded,
        )
    }

    private func contextualEquipmentOptions(
        request: TodayWorkoutPlanningRequest,
        fallback: [TodayWorkoutPlanningEquipmentOption]
    ) async -> [TodayWorkoutPlanningEquipmentOption] {
        guard !request.targetMuscleGroups.isEmpty else {
            return fallback
        }

        let result = await repository.search(
            query: ExerciseCatalogQuery(
                page: 0,
                size: 80,
                muscleGroups: request.targetMuscleGroups.sorted(by: { $0.sortOrder < $1.sortOrder }),
            ),
        )

        let relevantItems = result.items.filter {
            $0.matchesAnyMuscleGroup(request.targetMuscleGroups)
        }
        let options = equipmentOptions(from: relevantItems.flatMap(\.equipment))

        return options.isEmpty ? fallback : options
    }

    private func equipmentOptions(
        from equipment: [ExerciseCatalogEquipment]
    ) -> [TodayWorkoutPlanningEquipmentOption] {
        equipment
            .reduce(into: [String: TodayWorkoutPlanningEquipmentOption]()) { partial, equipment in
                partial[equipment.id] = TodayWorkoutPlanningEquipmentOption(
                    id: equipment.id,
                    name: equipment.name,
                    category: equipment.category,
                )
            }
            .values
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}

private extension ExerciseCatalogItem {
    func matchesAnyMuscleGroup(_ muscleGroups: Set<ExerciseCatalogMuscleGroup>) -> Bool {
        guard !muscleGroups.isEmpty else { return true }
        let itemGroups = Set(muscles.compactMap(\.muscleGroup))
        return !itemGroups.isDisjoint(with: muscleGroups)
    }
}

@Observable
@MainActor
final class TodayWorkoutPlanningViewModel {
    private let provider: any TodayWorkoutPlanningProviding
    private(set) var hasLoaded = false

    var request = TodayWorkoutPlanningRequest()
    var catalogSnapshot = TodayWorkoutPlanningCatalogSnapshot.empty
    var isLoading = false
    var isBuilding = false

    init(provider: any TodayWorkoutPlanningProviding) {
        self.provider = provider
    }

    var availableMuscleGroups: [ExerciseCatalogMuscleGroup] {
        ExerciseCatalogMuscleGroup.allCases
    }

    var availableDurations: [Int] {
        [25, 35, 45, 60, 75]
    }

    func onAppear() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reloadCatalog()
    }

    func reloadCatalog() async {
        isLoading = true
        defer { isLoading = false }
        catalogSnapshot = await provider.loadCatalogSnapshot(for: request)
        let visibleEquipmentIDs = Set(catalogSnapshot.equipmentOptions.map(\.id))
        request.availableEquipmentIDs.formIntersection(visibleEquipmentIDs)
    }

    func toggleMuscleGroup(_ muscleGroup: ExerciseCatalogMuscleGroup) {
        request.toggleMuscleGroup(muscleGroup)
        Task {
            await reloadCatalog()
        }
    }

    func toggleEquipment(id: String) {
        request.toggleEquipment(id: id)
    }

    func setDuration(_ minutes: Int) {
        request.desiredDurationMinutes = request.desiredDurationMinutes == minutes ? nil : minutes
    }

    func setFocus(_ focus: TodayWorkoutPlanningFocus) {
        request.focus = request.focus == focus ? nil : focus
    }

    func buildWorkout() async -> TodayWorkoutPlanningDraftSeed? {
        guard request.canBuild else { return nil }
        isBuilding = true
        defer { isBuilding = false }
        return await provider.buildDraftSeed(for: request, snapshot: catalogSnapshot)
    }
}

struct TodayWorkoutPlanningView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: TodayWorkoutPlanningViewModel
    let onBuild: (TodayWorkoutPlanningDraftSeed) -> Void

    init(
        provider: any TodayWorkoutPlanningProviding,
        onBuild: @escaping (TodayWorkoutPlanningDraftSeed) -> Void
    ) {
        _viewModel = State(
            initialValue: TodayWorkoutPlanningViewModel(provider: provider),
        )
        self.onBuild = onBuild
    }

    var body: some View {
        ZStack {
            FFColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: FFSpacing.md) {
                    introCard
                    muscleGroupCard
                    durationCard
                    focusCard
                    equipmentCard
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.md)
            }
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
        }
        .navigationTitle("Тренировка на сегодня")
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
        .task {
            await viewModel.onAppear()
        }
    }

    private var introCard: some View {
        TrainingBuilderHeroCard(
            eyebrow: "Сегодня",
            title: "Выберите мышцы и время",
            subtitle: "Остальное только уточняет старт.",
            badges: selectionSummary
        )
    }

    private var muscleGroupCard: some View {
        TrainingBuilderSectionCard(
            eyebrow: "Мышцы",
            title: "Что тренируем",
            helper: "Главный выбор перед стартом."
        ) {
            flowLayout(items: viewModel.availableMuscleGroups, id: \.rawValue) { muscleGroup in
                selectionChip(
                    title: muscleGroup.title,
                    subtitle: nil,
                    isSelected: viewModel.request.targetMuscleGroups.contains(muscleGroup),
                ) {
                    viewModel.toggleMuscleGroup(muscleGroup)
                }
            }
        }
    }

    private var durationCard: some View {
        TrainingBuilderSectionCard(
            eyebrow: "Время",
            title: "Сколько времени есть",
            helper: "От этого зависит объём."
        ) {
            flowLayout(items: viewModel.availableDurations, id: \.self) { duration in
                selectionChip(
                    title: "\(duration) мин",
                    subtitle: nil,
                    isSelected: viewModel.request.desiredDurationMinutes == duration,
                ) {
                    viewModel.setDuration(duration)
                }
            }
        }
    }

    private var focusCard: some View {
        TrainingBuilderSectionCard(
            eyebrow: "Акцент",
            title: "Какой акцент нужен",
            helper: "Необязательно."
        ) {
            flowLayout(items: TodayWorkoutPlanningFocus.allCases, id: \.rawValue) { focus in
                selectionChip(
                    title: focus.title,
                    subtitle: focus.subtitle,
                    isSelected: viewModel.request.focus == focus,
                ) {
                    viewModel.setFocus(focus)
                }
            }
        }
    }

    private var equipmentCard: some View {
        TrainingBuilderSectionCard(
            eyebrow: "Оборудование",
            title: "Доступное оборудование",
            helper: equipmentSectionHelperText
        ) {
            if viewModel.catalogSnapshot.equipmentOptions.isEmpty {
                Text("Сначала выберите мышечные группы, чтобы показать подходящее оборудование.")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
            } else {
                flowLayout(items: viewModel.catalogSnapshot.equipmentOptions, id: \.id) { option in
                    selectionChip(
                        title: option.title,
                        subtitle: option.category?.title,
                        isSelected: viewModel.request.availableEquipmentIDs.contains(option.id),
                    ) {
                        viewModel.toggleEquipment(id: option.id)
                    }
                }
            }
        }
    }

    private var bottomActionBar: some View {
        TrainingBuilderBottomBar(
            helper: bottomHelperText,
            title: "Открыть конструктор",
            summary: nil,
            buttonVariant: viewModel.request.canBuild ? .primary : .disabled,
            isLoading: viewModel.isBuilding
        ) {
            Task {
                guard let seed = await viewModel.buildWorkout() else { return }
                onBuild(seed)
            }
        }
    }

    private var bottomHelperText: String {
        if viewModel.request.canBuild {
            return "Откроем конструктор с вашей тренировкой."
        }
        return "Сначала выберите мышцы и время."
    }

    private var equipmentSectionHelperText: String {
        let muscles = viewModel.request.targetMuscleGroups
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .map(\.title)

        guard !muscles.isEmpty else {
            return "Покажем подходящие варианты."
        }

        return "Подборка под \(muscles.joined(separator: ", "))."
    }

    private func flowLayout<Item: RandomAccessCollection, ID: Hashable, Content: View>(
        items: Item,
        id: KeyPath<Item.Element, ID>,
        @ViewBuilder content: @escaping (Item.Element) -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            let rows = stride(from: 0, to: items.count, by: 2).map { offset in
                Array(items.dropFirst(offset).prefix(2))
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: FFSpacing.xs) {
                    ForEach(row, id: id) { item in
                        content(item)
                    }
                    if row.count == 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func selectionChip(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        action: @escaping () -> Void,
        isInteractive: Bool = true
    ) -> some View {
        TrainingBuilderChoiceTile(
            title: title,
            subtitle: subtitle,
            isSelected: isSelected,
            action: action
        )
        .allowsHitTesting(isInteractive)
        .opacity(isInteractive ? 1 : 0.92)
    }

    private var selectionSummary: [String] {
        var items: [String] = []
        items.append(
            contentsOf: viewModel.request.targetMuscleGroups
                .sorted(by: { $0.sortOrder < $1.sortOrder })
                .map(\.title)
        )
        if let duration = viewModel.request.desiredDurationMinutes {
            items.append("\(duration) мин")
        }
        if let focus = viewModel.request.focus {
            items.append(focus.title)
        }
        return items
    }

}

private extension ExerciseCatalogEquipmentCategory {
    var title: String {
        switch self {
        case .freeWeight:
            "свободный вес"
        case .machine:
            "тренажёр"
        case .bodyweight:
            "вес тела"
        case .band:
            "резина"
        case .cardio:
            "кардио"
        }
    }
}

private extension ExerciseCatalogMuscleGroup {
    static let allCases: [ExerciseCatalogMuscleGroup] = [
        .back,
        .chest,
        .legs,
        .shoulders,
        .arms,
        .abs,
    ]
}
