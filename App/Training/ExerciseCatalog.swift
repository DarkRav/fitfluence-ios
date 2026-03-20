import Foundation
import Observation

enum ExerciseCatalogMovementPattern: String, Codable, Equatable, Sendable {
    case push = "PUSH"
    case pull = "PULL"
    case squat = "SQUAT"
    case hinge = "HINGE"
    case other = "OTHER"
}

enum ExerciseCatalogDifficultyLevel: String, Codable, Equatable, Sendable {
    case beginner = "BEGINNER"
    case intermediate = "INTERMEDIATE"
    case advanced = "ADVANCED"
}

enum ExerciseCatalogMuscleGroup: String, Codable, Equatable, Sendable {
    case back = "BACK"
    case chest = "CHEST"
    case legs = "LEGS"
    case shoulders = "SHOULDERS"
    case arms = "ARMS"
    case abs = "ABS"
}

enum ExerciseCatalogEquipmentCategory: String, Codable, Equatable, Sendable {
    case freeWeight = "FREE_WEIGHT"
    case machine = "MACHINE"
    case bodyweight = "BODYWEIGHT"
    case band = "BAND"
    case cardio = "CARDIO"
}

enum ExerciseCatalogItemSource: String, Codable, Equatable, Sendable {
    case athleteCatalog
    case savedTemplate
    case workoutPayload
}

struct ExerciseCatalogDraftDefaults: Codable, Equatable, Sendable {
    let sets: Int
    let repsMin: Int?
    let repsMax: Int?
    let restSeconds: Int?
    let targetRpe: Int?
    let notes: String?

    init(
        sets: Int,
        repsMin: Int?,
        repsMax: Int?,
        restSeconds: Int?,
        targetRpe: Int? = nil,
        notes: String? = nil,
    ) {
        self.sets = sets
        self.repsMin = repsMin
        self.repsMax = repsMax
        self.restSeconds = restSeconds
        self.targetRpe = targetRpe
        self.notes = notes
    }

    static let standard = ExerciseCatalogDraftDefaults(
        sets: 3,
        repsMin: 8,
        repsMax: 12,
        restSeconds: 90,
    )
}

struct ExerciseCatalogMuscle: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let code: String
    let name: String
    let muscleGroup: ExerciseCatalogMuscleGroup?
    let description: String?
    let media: [ContentMedia]?
}

struct ExerciseCatalogEquipment: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let code: String
    let name: String
    let category: ExerciseCatalogEquipmentCategory?
    let description: String?
    let media: [ContentMedia]?
}

struct ExerciseCatalogItem: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let code: String?
    let name: String
    let description: String?
    let movementPattern: ExerciseCatalogMovementPattern?
    let difficultyLevel: ExerciseCatalogDifficultyLevel?
    let isBodyweight: Bool?
    let muscles: [ExerciseCatalogMuscle]
    let equipment: [ExerciseCatalogEquipment]
    let media: [ContentMedia]
    let source: ExerciseCatalogItemSource
    let draftDefaults: ExerciseCatalogDraftDefaults?
}

struct ExerciseCatalogMetadata: Equatable, Sendable {
    let muscles: [ExerciseCatalogMuscle]
    let equipment: [ExerciseCatalogEquipment]
    let muscleGroups: [ExerciseCatalogMuscleGroup]
    let equipmentCategories: [ExerciseCatalogEquipmentCategory]
    let movementPatterns: [ExerciseCatalogMovementPattern]
    let difficultyLevels: [ExerciseCatalogDifficultyLevel]

    static let empty = ExerciseCatalogMetadata(
        muscles: [],
        equipment: [],
        muscleGroups: [],
        equipmentCategories: [],
        movementPatterns: [],
        difficultyLevels: [],
    )

    static func derived(from items: [ExerciseCatalogItem]) -> ExerciseCatalogMetadata {
        let uniqueMuscles = items
            .flatMap(\.muscles)
            .uniqued(by: \.id)
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        let uniqueEquipment = items
            .flatMap(\.equipment)
            .uniqued(by: \.id)
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        let muscleGroups = Array(Set(uniqueMuscles.compactMap(\.muscleGroup)))
            .sorted(by: { $0.catalogSortOrder < $1.catalogSortOrder })
        let equipmentCategories = Array(Set(uniqueEquipment.compactMap(\.category)))
            .sorted(by: { $0.catalogSortOrder < $1.catalogSortOrder })
        let movementPatterns = Array(Set(items.compactMap(\.movementPattern)))
            .sorted(by: { $0.catalogSortOrder < $1.catalogSortOrder })
        let difficultyLevels = Array(Set(items.compactMap(\.difficultyLevel)))
            .sorted(by: { $0.catalogSortOrder < $1.catalogSortOrder })

        return ExerciseCatalogMetadata(
            muscles: uniqueMuscles,
            equipment: uniqueEquipment,
            muscleGroups: muscleGroups,
            equipmentCategories: equipmentCategories,
            movementPatterns: movementPatterns,
            difficultyLevels: difficultyLevels,
        )
    }
}

struct ExerciseCatalogQuery: Equatable, Sendable {
    let search: String?
    let page: Int
    let size: Int
    let movementPattern: ExerciseCatalogMovementPattern?
    let difficultyLevel: ExerciseCatalogDifficultyLevel?
    let muscleIds: [String]
    let muscleGroups: [ExerciseCatalogMuscleGroup]
    let mediaTags: [String]
    let equipmentIds: [String]

    init(
        search: String? = nil,
        page: Int = 0,
        size: Int = 20,
        movementPattern: ExerciseCatalogMovementPattern? = nil,
        difficultyLevel: ExerciseCatalogDifficultyLevel? = nil,
        muscleIds: [String] = [],
        muscleGroups: [ExerciseCatalogMuscleGroup] = [],
        mediaTags: [String] = [],
        equipmentIds: [String] = [],
    ) {
        self.search = search?.trimmedNilIfEmpty
        self.page = max(0, page)
        self.size = max(1, size)
        self.movementPattern = movementPattern
        self.difficultyLevel = difficultyLevel
        self.muscleIds = muscleIds
        self.muscleGroups = muscleGroups
        self.mediaTags = mediaTags
        self.equipmentIds = equipmentIds
    }
}

enum ExerciseCatalogResultState: Equatable, Sendable {
    case content
    case empty(message: String)
    case unavailable(message: String)
}

enum ExerciseCatalogResultSource: Equatable, Sendable {
    case athleteCatalog
    case savedTemplates
}

struct ExerciseCatalogResult: Equatable, Sendable {
    let items: [ExerciseCatalogItem]
    let metadata: PageMetadata?
    let state: ExerciseCatalogResultState
    let source: ExerciseCatalogResultSource
    let note: String?
    let contractGaps: [String]
}

protocol ExerciseCatalogRepository: Sendable {
    func search(query: ExerciseCatalogQuery) async -> ExerciseCatalogResult
    func metadata() async -> ExerciseCatalogMetadata
}

extension ExerciseCatalogRepository {
    func metadata() async -> ExerciseCatalogMetadata {
        .empty
    }
}

struct BackendExerciseCatalogRepository: ExerciseCatalogRepository {
    private static let athleteContractGaps = [
        "Recent/suggested exercise surfaces пока остаются client-side: athlete contract теперь закрывает catalog search и metadata, но не добавляет отдельный recommendation engine.",
    ]

    let apiClient: ExerciseCatalogAPIClientProtocol?
    let userSub: String?
    let templateRepository: any WorkoutTemplateRepository

    init(
        apiClient: ExerciseCatalogAPIClientProtocol?,
        userSub: String?,
        templateRepository: any WorkoutTemplateRepository = LocalWorkoutTemplateRepository(),
    ) {
        self.apiClient = apiClient
        self.userSub = userSub?.trimmedNilIfEmpty
        self.templateRepository = templateRepository
    }

    init(
        apiClient: ExerciseCatalogAPIClientProtocol?,
        userSub: String?,
        trainingStore: any TrainingStore,
    ) {
        self.init(
            apiClient: apiClient,
            userSub: userSub,
            templateRepository: LocalWorkoutTemplateRepository(trainingStore: trainingStore),
        )
    }

    func search(query: ExerciseCatalogQuery) async -> ExerciseCatalogResult {
        let fallbackItems = await savedTemplateItems(matching: query.search)

        guard let apiClient else {
            if !fallbackItems.isEmpty {
                return ExerciseCatalogResult(
                    items: fallbackItems,
                    metadata: nil,
                    state: .content,
                    source: .savedTemplates,
                    note: "Показаны упражнения из ваших сохранённых шаблонов. Основной каталог упражнений ещё не подключён в текущем сценарии.",
                    contractGaps: Self.athleteContractGaps,
                )
            }

            return ExerciseCatalogResult(
                items: [],
                metadata: nil,
                state: .unavailable(message: "Каталог упражнений пока недоступен. Можно редактировать уже добавленные упражнения и сохранять свои шаблоны."),
                source: .savedTemplates,
                note: nil,
                contractGaps: Self.athleteContractGaps,
            )
        }

        switch await apiClient.searchAthleteExercises(request: query.asAPIRequest) {
        case let .success(response):
            let items = response.content.map(\.asCatalogItem)
            if !items.isEmpty {
                return ExerciseCatalogResult(
                    items: items,
                    metadata: response.metadata,
                    state: .content,
                    source: .athleteCatalog,
                    note: nil,
                    contractGaps: Self.athleteContractGaps,
                )
            }

            let emptyMessage = if query.search == nil {
                "Каталог упражнений пока не вернул ни одного упражнения."
            } else {
                "По вашему запросу упражнения не найдены."
            }

            return ExerciseCatalogResult(
                items: [],
                metadata: response.metadata,
                state: .empty(message: emptyMessage),
                source: .athleteCatalog,
                note: nil,
                contractGaps: Self.athleteContractGaps,
            )

        case let .failure(error):
            if !fallbackItems.isEmpty {
                return ExerciseCatalogResult(
                    items: fallbackItems,
                    metadata: nil,
                    state: .content,
                    source: .savedTemplates,
                    note: fallbackNote(for: error),
                    contractGaps: Self.athleteContractGaps,
                )
            }

            return ExerciseCatalogResult(
                items: [],
                metadata: nil,
                state: .unavailable(message: unavailableMessage(for: error)),
                source: .savedTemplates,
                note: nil,
                contractGaps: Self.athleteContractGaps,
            )
        }
    }

    func metadata() async -> ExerciseCatalogMetadata {
        guard let apiClient else {
            return .empty
        }

        switch await apiClient.athleteExerciseCatalogMetadata() {
        case let .success(response):
            let metadata = response.asDomain
            if !metadata.equipment.isEmpty || !metadata.muscles.isEmpty {
                return metadata
            }
            return await derivedMetadataFromSearch(apiClient: apiClient)
        case .failure:
            return await derivedMetadataFromSearch(apiClient: apiClient)
        }
    }

    private func savedTemplateItems(matching search: String?) async -> [ExerciseCatalogItem] {
        guard let userSub else { return [] }

        let templates = await templateRepository.templates(userSub: userSub)
        let items = templates
            .flatMap(\.exercises)
            .map(ExerciseCatalogItem.init(templateExercise:))
            .uniqueCatalogItems()

        guard let search else {
            return items
        }

        return items.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private func fallbackNote(for error: APIError) -> String {
        switch error {
        case .offline:
            "Нет сети. Показаны упражнения из ваших сохранённых шаблонов."
        case .unauthorized:
            "Не удалось авторизовать каталог упражнений. Показаны упражнения из ваших сохранённых шаблонов."
        case .forbidden:
            "Текущая сессия не получила доступ к каталогу упражнений. Показаны упражнения из ваших сохранённых шаблонов."
        default:
            "Каталог упражнений временно недоступен. Показаны упражнения из ваших сохранённых шаблонов."
        }
    }

    private func unavailableMessage(for error: APIError) -> String {
        switch error {
        case .offline:
            "Нет подключения к интернету. Каталог упражнений недоступен."
        case .unauthorized:
            "Сессия истекла, поэтому каталог упражнений недоступен."
        case .forbidden:
            "Текущая сессия не может читать каталог упражнений."
        case let .httpError(statusCode, _):
            "Каталог упражнений недоступен. Сервер вернул статус \(statusCode)."
        case let .serverError(statusCode, _):
            "Каталог упражнений временно недоступен. Сервер вернул статус \(statusCode)."
        case .decodingError:
            "Не удалось прочитать ответ каталога упражнений."
        default:
            "Каталог упражнений временно недоступен."
        }
    }

    private func derivedMetadataFromSearch(apiClient: ExerciseCatalogAPIClientProtocol) async -> ExerciseCatalogMetadata {
        let request = APIExercisesSearchRequest(
            filter: nil,
            page: 0,
            size: 100,
        )

        switch await apiClient.searchAthleteExercises(request: request) {
        case let .success(response):
            return ExerciseCatalogMetadata.derived(from: response.content.map(\.asCatalogItem))
        case .failure:
            return .empty
        }
    }
}

@Observable
@MainActor
final class ExerciseCatalogViewModel {
    private let repository: any ExerciseCatalogRepository
    private var searchTask: Task<Void, Never>?
    private(set) var hasLoaded = false

    var items: [ExerciseCatalogItem] = []
    var isLoading = false
    var state: ExerciseCatalogResultState = .content
    var note: String?
    var contractGaps: [String] = []

    init(repository: any ExerciseCatalogRepository) {
        self.repository = repository
    }

    func onAppear(search: String) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload(search: search)
    }

    func searchQueryChanged(_ search: String) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.reload(search: search)
        }
    }

    func retry(search: String) async {
        await reload(search: search)
    }

    private func reload(search: String) async {
        isLoading = true
        defer { isLoading = false }

        let result = await repository.search(
            query: ExerciseCatalogQuery(search: search),
        )

        items = result.items
        state = result.state
        note = result.note
        contractGaps = result.contractGaps
    }
}

extension APIExercise {
    var asCatalogItem: ExerciseCatalogItem {
        ExerciseCatalogItem(
            id: id,
            code: code,
            name: name,
            description: description?.trimmedNilIfEmpty,
            movementPattern: movementPattern?.asDomain,
            difficultyLevel: difficultyLevel?.asDomain,
            isBodyweight: isBodyweight,
            muscles: (muscles ?? []).map(\.asDomain),
            equipment: (equipment ?? []).map(\.asDomain),
            media: media ?? [],
            source: .athleteCatalog,
            draftDefaults: nil,
        )
    }
}

extension APIAthleteExerciseCatalogMetadataResponse {
    var asDomain: ExerciseCatalogMetadata {
        ExerciseCatalogMetadata(
            muscles: muscles.map(\.asDomain),
            equipment: equipment.map(\.asDomain),
            muscleGroups: muscleGroups.compactMap(\.asDomainOptional),
            equipmentCategories: equipmentCategories.compactMap(\.asDomainOptional),
            movementPatterns: movementPatterns.compactMap(\.asDomainOptional),
            difficultyLevels: difficultyLevels.compactMap(\.asDomainOptional),
        )
    }
}

private extension Array {
    func uniqued<ID: Hashable>(by keyPath: KeyPath<Element, ID>) -> [Element] {
        var seen = Set<ID>()
        var result: [Element] = []
        result.reserveCapacity(count)

        for item in self {
            let id = item[keyPath: keyPath]
            guard seen.insert(id).inserted else { continue }
            result.append(item)
        }

        return result
    }
}

private extension ExerciseCatalogMuscleGroup {
    var catalogSortOrder: Int {
        switch self {
        case .back: 0
        case .chest: 1
        case .legs: 2
        case .shoulders: 3
        case .arms: 4
        case .abs: 5
        }
    }
}

private extension ExerciseCatalogEquipmentCategory {
    var catalogSortOrder: Int {
        switch self {
        case .freeWeight: 0
        case .machine: 1
        case .bodyweight: 2
        case .band: 3
        case .cardio: 4
        }
    }
}

private extension ExerciseCatalogMovementPattern {
    var catalogSortOrder: Int {
        switch self {
        case .push: 0
        case .pull: 1
        case .squat: 2
        case .hinge: 3
        case .other: 4
        }
    }
}

private extension ExerciseCatalogDifficultyLevel {
    var catalogSortOrder: Int {
        switch self {
        case .beginner: 0
        case .intermediate: 1
        case .advanced: 2
        }
    }
}

extension TemplateExerciseDraft {
    fileprivate var asCatalogDraftDefaults: ExerciseCatalogDraftDefaults {
        ExerciseCatalogDraftDefaults(
            sets: max(1, sets),
            repsMin: repsMin,
            repsMax: repsMax,
            restSeconds: restSeconds,
            targetRpe: targetRpe,
            notes: notes,
        )
    }
}

extension WorkoutExercise {
    var asCatalogItem: ExerciseCatalogItem {
        ExerciseCatalogItem(
            id: id,
            code: nil,
            name: name,
            description: description?.trimmedNilIfEmpty,
            movementPattern: nil,
            difficultyLevel: nil,
            isBodyweight: isBodyweight,
            muscles: [],
            equipment: [],
            media: media ?? [],
            source: .workoutPayload,
            draftDefaults: ExerciseCatalogDraftDefaults(
                sets: max(1, sets),
                repsMin: repsMin,
                repsMax: repsMax,
                restSeconds: restSeconds,
                targetRpe: targetRpe,
                notes: notes,
            ),
        )
    }
}

private extension ExerciseCatalogItem {
    init(templateExercise: TemplateExerciseDraft) {
        self.init(
            id: templateExercise.id,
            code: nil,
            name: templateExercise.name,
            description: nil,
            movementPattern: nil,
            difficultyLevel: nil,
            isBodyweight: nil,
            muscles: [],
            equipment: [],
            media: [],
            source: .savedTemplate,
            draftDefaults: templateExercise.asCatalogDraftDefaults,
        )
    }
}

private extension ExerciseCatalogQuery {
    var asAPIRequest: APIExercisesSearchRequest {
        let filter = APIExerciseFilter(
            search: search,
            movementPattern: movementPattern?.asAPI,
            difficultyLevel: difficultyLevel?.asAPI,
            muscleIds: muscleIds.isEmpty ? nil : muscleIds,
            muscleGroups: muscleGroups.isEmpty ? nil : muscleGroups.map(\.asAPI),
            mediaTags: mediaTags.isEmpty ? nil : mediaTags,
            equipmentIds: equipmentIds.isEmpty ? nil : equipmentIds,
        )

        let resolvedFilter: APIExerciseFilter? = if filter.search == nil,
            filter.movementPattern == nil,
            filter.difficultyLevel == nil,
            filter.muscleIds == nil,
            filter.muscleGroups == nil,
            filter.mediaTags == nil,
            filter.equipmentIds == nil
        {
            nil
        } else {
            filter
        }

        return APIExercisesSearchRequest(
            filter: resolvedFilter,
            page: page,
            size: size,
        )
    }
}

private extension APIExerciseMuscle {
    var asDomain: ExerciseCatalogMuscle {
        ExerciseCatalogMuscle(
            id: id,
            code: code,
            name: name,
            muscleGroup: muscleGroup?.asDomain,
            description: description?.trimmedNilIfEmpty,
            media: media,
        )
    }
}

private extension APIExerciseEquipment {
    var asDomain: ExerciseCatalogEquipment {
        ExerciseCatalogEquipment(
            id: id,
            code: code,
            name: name,
            category: category?.asDomain,
            description: description?.trimmedNilIfEmpty,
            media: media,
        )
    }
}

private extension APIExerciseMovementPattern {
    var asDomain: ExerciseCatalogMovementPattern {
        ExerciseCatalogMovementPattern(rawValue: rawValue) ?? .other
    }

    var asDomainOptional: ExerciseCatalogMovementPattern? {
        ExerciseCatalogMovementPattern(rawValue: rawValue)
    }
}

private extension ExerciseCatalogMovementPattern {
    var asAPI: APIExerciseMovementPattern {
        APIExerciseMovementPattern(rawValue: rawValue) ?? .other
    }
}

private extension APIExerciseDifficultyLevel {
    var asDomain: ExerciseCatalogDifficultyLevel {
        ExerciseCatalogDifficultyLevel(rawValue: rawValue) ?? .beginner
    }

    var asDomainOptional: ExerciseCatalogDifficultyLevel? {
        ExerciseCatalogDifficultyLevel(rawValue: rawValue)
    }
}

private extension ExerciseCatalogDifficultyLevel {
    var asAPI: APIExerciseDifficultyLevel {
        APIExerciseDifficultyLevel(rawValue: rawValue) ?? .beginner
    }
}

private extension APIMuscleGroup {
    var asDomain: ExerciseCatalogMuscleGroup {
        ExerciseCatalogMuscleGroup(rawValue: rawValue) ?? .back
    }

    var asDomainOptional: ExerciseCatalogMuscleGroup? {
        ExerciseCatalogMuscleGroup(rawValue: rawValue)
    }
}

private extension ExerciseCatalogMuscleGroup {
    var asAPI: APIMuscleGroup {
        APIMuscleGroup(rawValue: rawValue) ?? .back
    }
}

private extension APIEquipmentCategory {
    var asDomain: ExerciseCatalogEquipmentCategory {
        ExerciseCatalogEquipmentCategory(rawValue: rawValue) ?? .freeWeight
    }

    var asDomainOptional: ExerciseCatalogEquipmentCategory? {
        ExerciseCatalogEquipmentCategory(rawValue: rawValue)
    }
}

private extension Array where Element == ExerciseCatalogItem {
    func uniqueCatalogItems() -> [ExerciseCatalogItem] {
        var seen = Set<String>()
        var result: [ExerciseCatalogItem] = []

        for item in self {
            guard seen.insert(item.id).inserted else { continue }
            result.append(item)
        }

        return result
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
