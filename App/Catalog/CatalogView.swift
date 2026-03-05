import Observation
import SwiftUI

@Observable
@MainActor
final class CatalogViewModel {
    enum Scope: String, CaseIterable, Identifiable {
        case all
        case featured

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .all:
                "Все программы"
            case .featured:
                "Подборка"
            }
        }
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case updated
        case duration
        case level
        case alphabet

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .updated:
                "Сначала актуальные"
            case .duration:
                "По длительности"
            case .level:
                "По уровню"
            case .alphabet:
                "По названию"
            }
        }
    }

    enum DurationFilter: String, CaseIterable, Identifiable {
        case all
        case short
        case medium
        case long

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .all:
                "Любая"
            case .short:
                "До 40 мин"
            case .medium:
                "40–60 мин"
            case .long:
                "60+ мин"
            }
        }
    }

    struct ProgramCard: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let description: String
        let influencerName: String?
        let goals: [String]
        let coverURL: String?
        let isPublished: Bool
        let isFeatured: Bool
        let level: String?
        let daysPerWeek: Int?
        let estimatedDurationMinutes: Int?
        let equipment: [String]
        let createdAt: String?
        let updatedAt: String?

        var levelTitle: String {
            CatalogViewModel.localizedLevel(level)
        }

        var frequencyTitle: String {
            if let daysPerWeek {
                return "\(daysPerWeek) дн/нед"
            }
            return "Частота не указана"
        }

        var durationTitle: String {
            if let estimatedDurationMinutes {
                return "~\(estimatedDurationMinutes) мин"
            }
            return "Длительность не указана"
        }

        var equipmentTitle: String {
            if equipment.isEmpty {
                return "Оборудование не указано"
            }
            if equipment.count <= 2 {
                return equipment.joined(separator: ", ")
            }
            return "\(equipment.prefix(2).joined(separator: ", ")) +\(equipment.count - 2)"
        }

        var updatedLabel: String? {
            guard let updatedAt,
                  let date = CatalogViewModel.parseISODate(updatedAt)
            else {
                return nil
            }
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    struct CachedCatalogPage: Codable, Equatable {
        let cards: [ProgramCard]
        let metadata: PageMetadata
    }

    private let programsClient: ProgramsClientProtocol?
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring
    private let userSub: String
    private let onUnauthorized: (() -> Void)?

    private var searchTask: Task<Void, Never>?

    var scope: Scope = .all
    var query = ""
    var programs: [ProgramCard] = []
    var featuredPrograms: [ProgramCard] = []
    var isLoading = false
    var isRefreshing = false
    var isShowingCachedData = false
    var error: UserFacingError?
    var currentPage = 0
    var totalPages = 0
    var sortOption: SortOption = .updated
    var selectedGoal: String?
    var selectedLevel: String?
    var selectedEquipment: String?
    var selectedDaysPerWeek: Int?
    var selectedDuration: DurationFilter = .all

    init(
        userSub: String,
        programsClient: ProgramsClientProtocol?,
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
        onUnauthorized: (() -> Void)? = nil,
    ) {
        self.userSub = userSub
        self.programsClient = programsClient
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
        self.onUnauthorized = onUnauthorized
    }

    func onAppear() async {
        guard programs.isEmpty, featuredPrograms.isEmpty else { return }
        isLoading = true
        error = nil
        currentPage = 0
        await loadAllPage(page: 0, append: false)
        await loadFeaturedIfNeeded(silent: true)
    }

    func refresh() async {
        isRefreshing = true
        error = nil
        if scope == .featured {
            await loadFeatured(silent: false)
        } else {
            currentPage = 0
            await loadAllPage(page: 0, append: false)
        }
        isRefreshing = false
    }

    func retry() async {
        isLoading = true
        error = nil
        if scope == .featured {
            await loadFeatured(silent: false)
        } else {
            await loadAllPage(page: currentPage, append: false)
        }
    }

    func selectScope(_ scope: Scope) async {
        guard self.scope != scope else { return }
        self.scope = scope
        error = nil

        if scope == .featured {
            await loadFeaturedIfNeeded(silent: false)
        } else if programs.isEmpty {
            isLoading = true
            currentPage = 0
            await loadAllPage(page: 0, append: false)
        }
    }

    func searchQueryChanged(_ value: String) {
        query = value
        error = nil
        if !value.isEmpty, scope != .all {
            scope = .all
        }

        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self.searchSubmit()
        }
    }

    func searchSubmit() async {
        if scope != .all {
            scope = .all
        }
        isLoading = true
        error = nil
        currentPage = 0
        await loadAllPage(page: 0, append: false)
    }

    func loadNextPageIfNeeded(lastID: String?) async {
        guard scope == .all else { return }
        guard !isLoading else { return }
        guard totalPages > 0 else { return }
        guard let lastID, lastID == visiblePrograms.last?.id else { return }
        let nextPage = currentPage + 1
        guard nextPage < totalPages else { return }

        isLoading = true
        await loadAllPage(page: nextPage, append: true)
    }

    var hasActiveFilters: Bool {
        selectedGoal != nil
            || selectedLevel != nil
            || selectedEquipment != nil
            || selectedDaysPerWeek != nil
            || selectedDuration != .all
    }

    var activePrograms: [ProgramCard] {
        scope == .featured ? featuredPrograms : programs
    }

    var visiblePrograms: [ProgramCard] {
        var items = activePrograms

        if let selectedGoal {
            items = items.filter { card in
                card.goals.contains(where: { $0.caseInsensitiveCompare(selectedGoal) == .orderedSame })
            }
        }
        if let selectedLevel {
            items = items.filter { Self.localizedLevel($0.level).caseInsensitiveCompare(selectedLevel) == .orderedSame }
        }
        if let selectedEquipment {
            items = items.filter { card in
                card.equipment.contains(where: { $0.caseInsensitiveCompare(selectedEquipment) == .orderedSame })
            }
        }
        if let selectedDaysPerWeek {
            items = items.filter { $0.daysPerWeek == selectedDaysPerWeek }
        }
        switch selectedDuration {
        case .all:
            break
        case .short:
            items = items.filter { ($0.estimatedDurationMinutes ?? .max) <= 40 }
        case .medium:
            items = items.filter { duration in
                guard let minutes = duration.estimatedDurationMinutes else { return false }
                return (41 ... 60).contains(minutes)
            }
        case .long:
            items = items.filter { ($0.estimatedDurationMinutes ?? 0) > 60 }
        }

        switch sortOption {
        case .updated:
            items.sort { lhs, rhs in
                let l = Self.parseISODate(lhs.updatedAt) ?? Self.parseISODate(lhs.createdAt) ?? .distantPast
                let r = Self.parseISODate(rhs.updatedAt) ?? Self.parseISODate(rhs.createdAt) ?? .distantPast
                return l > r
            }
        case .duration:
            items.sort {
                ($0.estimatedDurationMinutes ?? Int.max) < ($1.estimatedDurationMinutes ?? Int.max)
            }
        case .level:
            items.sort { levelRank($0.level) < levelRank($1.level) }
        case .alphabet:
            items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return items
    }

    var availableGoals: [String] {
        uniqueSorted(activePrograms.flatMap(\.goals))
    }

    var availableLevels: [String] {
        uniqueSorted(activePrograms.map { Self.localizedLevel($0.level) })
    }

    var availableEquipment: [String] {
        uniqueSorted(activePrograms.flatMap(\.equipment))
    }

    var availableDaysPerWeek: [Int] {
        Array(Set(activePrograms.compactMap(\.daysPerWeek))).sorted()
    }

    func resetFilters() {
        selectedGoal = nil
        selectedLevel = nil
        selectedEquipment = nil
        selectedDaysPerWeek = nil
        selectedDuration = .all
    }

    private func loadAllPage(page: Int, append: Bool) async {
        defer {
            isLoading = false
        }

        let key = allCacheKey(query: query, page: page)
        if let cached = await cacheStore.get(key, as: CachedCatalogPage.self, namespace: userSub) {
            if append {
                programs = merge(existing: programs, incoming: cached.cards, append: true)
            } else {
                programs = cached.cards
            }
            currentPage = cached.metadata.page
            totalPages = cached.metadata.totalPages
            isShowingCachedData = true
        }

        let result: Result<PagedProgramResponse, APIError> = if let programsClient {
            await programsClient.listPublishedPrograms(query: query, page: page, size: 20)
        } else {
            .failure(.invalidURL)
        }

        switch result {
        case let .success(response):
            let cards = mapCards(response.content)

            if append {
                programs = merge(existing: programs, incoming: cards, append: true)
            } else {
                programs = cards
            }
            currentPage = response.metadata.page
            totalPages = response.metadata.totalPages
            error = nil
            isShowingCachedData = false
            let payload = CachedCatalogPage(cards: cards, metadata: response.metadata)
            await cacheStore.set(key, value: payload, namespace: userSub, ttl: 60 * 30)

        case let .failure(apiError):
            if apiError == .unauthorized {
                onUnauthorized?()
                return
            }
            if apiError == .offline || !networkMonitor.currentStatus, !programs.isEmpty {
                error = nil
                isShowingCachedData = true
                return
            }

            error = apiError.userFacing(context: .catalog)
            if !append {
                programs = []
            }
        }
    }

    private func loadFeaturedIfNeeded(silent: Bool) async {
        guard featuredPrograms.isEmpty else { return }
        await loadFeatured(silent: silent)
    }

    private func loadFeatured(silent: Bool) async {
        if !silent {
            isLoading = true
        }
        defer {
            if !silent {
                isLoading = false
            }
        }

        let key = featuredCacheKey(page: 0)
        if let cached = await cacheStore.get(key, as: CachedCatalogPage.self, namespace: userSub) {
            featuredPrograms = cached.cards
            isShowingCachedData = scope == .featured
        }

        let result: Result<PagedProgramResponse, APIError> = if let programsClient {
            await programsClient.listFeaturedPrograms(page: 0, size: 20)
        } else {
            .failure(.invalidURL)
        }

        switch result {
        case let .success(response):
            let cards = mapCards(response.content)
            featuredPrograms = cards
            let payload = CachedCatalogPage(cards: cards, metadata: response.metadata)
            await cacheStore.set(key, value: payload, namespace: userSub, ttl: 60 * 30)
            if scope == .featured {
                error = nil
                isShowingCachedData = false
            }

        case let .failure(apiError):
            if apiError == .unauthorized {
                onUnauthorized?()
                return
            }
            if case let .httpError(statusCode, _) = apiError, statusCode == 404 {
                featuredPrograms = []
                if scope == .featured {
                    scope = .all
                    if programs.isEmpty {
                        isLoading = true
                        currentPage = 0
                        await loadAllPage(page: 0, append: false)
                    } else {
                        isLoading = false
                    }
                }
                return
            }
            if apiError == .offline || !networkMonitor.currentStatus, !featuredPrograms.isEmpty {
                if scope == .featured {
                    error = nil
                    isShowingCachedData = true
                }
                return
            }
            if scope == .featured {
                error = apiError.userFacing(context: .catalog)
            }
        }
    }

    private func mapCards(_ items: [ProgramListItem]) -> [ProgramCard] {
        items.map { item in
            let requirementsSummary = item.currentPublishedVersion?.requirements?.equipmentSummaryText
            let derivedEquipment = requirementsSummary?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != "Оборудование не указано" } ?? []
            let mergedEquipment = uniqueSorted((item.equipment ?? []) + derivedEquipment)

            return ProgramCard(
                id: item.id,
                title: item.title,
                description: item.description?.trimmedNilIfEmpty ?? "Описание пока не добавлено.",
                influencerName: item.influencer?.displayName,
                goals: item.goals ?? [],
                coverURL: item.cover?.url ?? item.media?.first?.url,
                isPublished: item.status == .published,
                isFeatured: item.isFeatured ?? false,
                level: item.level ?? item.currentPublishedVersion?.level,
                daysPerWeek: item.daysPerWeek ?? item.currentPublishedVersion?.frequencyPerWeek,
                estimatedDurationMinutes: item.estimatedDurationMinutes,
                equipment: mergedEquipment,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
            )
        }
    }

    private func merge(existing: [ProgramCard], incoming: [ProgramCard], append: Bool) -> [ProgramCard] {
        guard append else { return incoming }
        var result = existing
        var ids = Set(existing.map(\.id))
        for card in incoming where !ids.contains(card.id) {
            result.append(card)
            ids.insert(card.id)
        }
        return result
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func levelRank(_ value: String?) -> Int {
        let normalized = (value ?? "").lowercased()
        if normalized.contains("beginner") || normalized.contains("нович") {
            return 0
        }
        if normalized.contains("intermediate") || normalized.contains("сред") {
            return 1
        }
        if normalized.contains("advanced") || normalized.contains("продвин") {
            return 2
        }
        return 3
    }

    private func allCacheKey(query: String, page: Int) -> String {
        "programs.list?q=\(query)&page=\(page)"
    }

    private func featuredCacheKey(page: Int) -> String {
        "programs.featured?page=\(page)"
    }

    nonisolated static func parseISODate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let withFractions = ISO8601DateFormatter()
        withFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractions.date(from: value) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    nonisolated static func localizedLevel(_ value: String?) -> String {
        guard let value else { return "Базовый" }
        switch value.uppercased() {
        case "BEGINNER":
            return "Начальный"
        case "INTERMEDIATE":
            return "Средний"
        case "ADVANCED":
            return "Продвинутый"
        default:
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Базовый" : value.capitalized
        }
    }

}

enum CatalogHubSegment: String, CaseIterable, Identifiable {
    case programs
    case athletes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .programs:
            "Программы"
        case .athletes:
            "Атлеты"
        }
    }
}

enum AthletesHubSegment: String, CaseIterable, Identifiable {
    case showcase
    case following

    var id: String { rawValue }

    var title: String {
        switch self {
        case .showcase:
            "Витрина"
        case .following:
            "Подписки"
        }
    }
}

enum FollowButtonState: Equatable {
    case follow
    case following
    case loading
}

enum FollowMutationAction {
    case follow
    case unfollow
}

fileprivate enum FollowFeatureAvailability {
    case unknown
    case available
    case unavailable

    var isAvailable: Bool {
        self != .unavailable
    }
}

enum FollowStateMachine {
    static func apply(_ action: FollowMutationAction, to creator: InfluencerPublicCard) -> InfluencerPublicCard {
        switch action {
        case .follow:
            return InfluencerPublicCard(
                id: creator.id,
                displayName: creator.displayName,
                bio: creator.bio,
                avatar: creator.avatar,
                socialLinks: creator.socialLinks,
                followersCount: creator.followersCount + (creator.isFollowedByMe ? 0 : 1),
                programsCount: creator.programsCount,
                isFollowedByMe: true,
                directionTag: creator.directionTag,
                achievements: creator.achievements,
                trainingPhilosophy: creator.trainingPhilosophy,
            )
        case .unfollow:
            return InfluencerPublicCard(
                id: creator.id,
                displayName: creator.displayName,
                bio: creator.bio,
                avatar: creator.avatar,
                socialLinks: creator.socialLinks,
                followersCount: max(0, creator.followersCount - (creator.isFollowedByMe ? 1 : 0)),
                programsCount: creator.programsCount,
                isFollowedByMe: false,
                directionTag: creator.directionTag,
                achievements: creator.achievements,
                trainingPhilosophy: creator.trainingPhilosophy,
            )
        }
    }
}

private struct CachedCreatorsPage: Codable, Equatable {
    let content: [InfluencerPublicCard]
    let metadata: PageMetadata
}

private struct CachedCreatorProgramsPage: Codable, Equatable {
    let content: [ProgramListItem]
    let metadata: PageMetadata
}

private struct CachedAthleteShelf: Codable, Equatable {
    let content: [InfluencerPublicCard]
}

fileprivate enum AthleteShelfKind: String, CaseIterable, Identifiable {
    case recommended
    case strength
    case massGain
    case calisthenics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended:
            "Рекомендуемые атлеты"
        case .strength:
            "Сила"
        case .massGain:
            "Набор массы"
        case .calisthenics:
            "Калистеника"
        }
    }

    var searchTerm: String? {
        switch self {
        case .recommended:
            nil
        case .strength:
            "сила strength"
        case .massGain:
            "масса mass"
        case .calisthenics:
            "калистеника calisthenics"
        }
    }
}

fileprivate struct AthleteShelfState: Identifiable, Equatable {
    let kind: AthleteShelfKind
    var athletes: [InfluencerPublicCard] = []
    var isLoading = false
    var isShowingCachedData = false
    var error: UserFacingError?

    var id: String { kind.id }
}

private enum PendingFollowIntentStore {
    private static let key = "athletes.pending_follow_influencer_id"

    static func save(_ influencerID: UUID) {
        UserDefaults.standard.set(influencerID.uuidString, forKey: key)
    }

    static func take() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let uuid = UUID(uuidString: raw)
        else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        UserDefaults.standard.removeObject(forKey: key)
        return uuid
    }
}

@Observable
@MainActor
final class AthletesShowcaseViewModel {
    private let userSub: String
    private let programsClient: ProgramsClientProtocol?
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring
    private let onUnauthorized: (() -> Void)?

    private var followLoadingIDs: Set<UUID> = []
    private let cacheTTL: TimeInterval = 60 * 60 * 24
    private var didTrackOpenEvent = false
    private var didResolveFollowAvailability = false

    fileprivate var shelves: [AthleteShelfState] = AthleteShelfKind.allCases.map { AthleteShelfState(kind: $0) }
    var isLoading = false
    var isRefreshing = false
    var isShowingCachedData = false
    var error: UserFacingError?
    var infoMessage: String?
    fileprivate private(set) var followFeatureAvailability: FollowFeatureAvailability

    init(
        userSub: String,
        programsClient: ProgramsClientProtocol?,
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
        onUnauthorized: (() -> Void)? = nil,
    ) {
        self.userSub = userSub
        self.programsClient = programsClient
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
        self.onUnauthorized = onUnauthorized
        followFeatureAvailability = programsClient == nil ? .unavailable : .unknown
    }

    var isFollowFeatureAvailable: Bool {
        followFeatureAvailability.isAvailable && programsClient != nil
    }

    var isOnline: Bool {
        networkMonitor.currentStatus
    }

    var hasAnyAthletes: Bool {
        shelves.contains(where: { !$0.athletes.isEmpty })
    }

    func onAppear() async {
        if !didTrackOpenEvent {
            didTrackOpenEvent = true
            ClientAnalytics.track(.athletesScreenOpened)
        }

        await resolveFollowAvailabilityIfNeeded()

        guard !hasAnyAthletes else {
            await replayPendingFollowIfNeeded()
            return
        }
        isLoading = true
        error = nil
        await loadShelves(forceReload: false)
        await replayPendingFollowIfNeeded()
    }

    func refresh() async {
        isRefreshing = true
        error = nil
        infoMessage = nil
        await resolveFollowAvailabilityIfNeeded(force: true)
        isLoading = true
        await loadShelves(forceReload: true)
        await replayPendingFollowIfNeeded()
        isRefreshing = false
    }

    func retry() async {
        isLoading = true
        error = nil
        infoMessage = nil
        await loadShelves(forceReload: true)
        await replayPendingFollowIfNeeded()
    }

    func isFollowLoading(_ influencerID: UUID) -> Bool {
        followLoadingIDs.contains(influencerID)
    }

    func toggleFollow(influencerId: UUID) async -> InfluencerPublicCard? {
        guard isFollowFeatureAvailable else {
            return athlete(for: influencerId)
        }
        guard !followLoadingIDs.contains(influencerId) else {
            return athlete(for: influencerId)
        }
        guard let before = athlete(for: influencerId) else {
            return nil
        }
        guard networkMonitor.currentStatus else {
            infoMessage = "Нужен интернет"
            return before
        }
        guard isAuthenticated else {
            PendingFollowIntentStore.save(influencerId)
            onUnauthorized?()
            return before
        }

        let action: FollowMutationAction = before.isFollowedByMe ? .unfollow : .follow
        let optimistic = FollowStateMachine.apply(action, to: before)
        updateAthlete(optimistic)
        followLoadingIDs.insert(influencerId)
        error = nil
        infoMessage = nil

        let result: Result<Void, APIError> = if let programsClient {
            switch action {
            case .follow:
                await programsClient.followCreator(influencerId: influencerId)
            case .unfollow:
                await programsClient.unfollowCreator(influencerId: influencerId)
            }
        } else {
            .failure(.invalidURL)
        }

        followLoadingIDs.remove(influencerId)

        switch result {
        case .success:
            if optimistic.isFollowedByMe {
                ClientAnalytics.track(.athleteFollowed, properties: ["influencer_id": influencerId.uuidString])
            } else {
                ClientAnalytics.track(.athleteUnfollowed, properties: ["influencer_id": influencerId.uuidString])
            }
            return athlete(for: influencerId)

        case let .failure(apiError):
            updateAthlete(before)
            if isFollowFeatureNotSupported(apiError) {
                followFeatureAvailability = .unavailable
                infoMessage = "Подписки недоступны в текущей версии API."
                return before
            }
            if apiError == .unauthorized {
                PendingFollowIntentStore.save(influencerId)
                onUnauthorized?()
                return before
            }
            if isCreatorFollowForbidden(apiError) {
                infoMessage = "Создайте профиль атлета, чтобы подписываться."
            } else {
                error = apiError.userFacing(context: .catalog)
            }
            return before
        }
    }

    func applyExternalAthleteUpdate(_ athlete: InfluencerPublicCard) {
        updateAthlete(athlete)
    }

    private func loadShelves(forceReload: Bool) async {
        defer {
            isLoading = false
        }

        var hasCachedData = false
        var firstNonOfflineError: UserFacingError?
        var hasOfflineWithoutCache = false

        for index in shelves.indices {
            let kind = shelves[index].kind
            shelves[index].isLoading = true
            shelves[index].error = nil

            let key = cacheKey(shelf: kind)
            if let cached = await cacheStore.get(key, as: CachedAthleteShelf.self, namespace: userSub) {
                shelves[index].athletes = cached.content
                shelves[index].isShowingCachedData = true
                hasCachedData = true
            } else if forceReload {
                shelves[index].athletes = []
                shelves[index].isShowingCachedData = false
            }

            let request = InfluencersSearchRequest(
                filter: InfluencerSearchFilter(search: kind.searchTerm),
                page: 0,
                size: 6,
            )
            let result: Result<PagedInfluencerPublicCardResponse, APIError> = if let programsClient {
                await programsClient.influencersSearch(request: request)
            } else {
                .failure(.invalidURL)
            }

            switch result {
            case let .success(response):
                let normalized = Array(response.content.prefix(6))
                shelves[index].athletes = normalized
                shelves[index].isShowingCachedData = false
                shelves[index].error = nil
                await cacheStore.set(
                    key,
                    value: CachedAthleteShelf(content: normalized),
                    namespace: userSub,
                    ttl: cacheTTL,
                )

            case let .failure(apiError):
                if apiError == .unauthorized {
                    onUnauthorized?()
                    shelves[index].isLoading = false
                    continue
                }
                if apiError == .offline || !networkMonitor.currentStatus {
                    if shelves[index].athletes.isEmpty {
                        hasOfflineWithoutCache = true
                        shelves[index].error = UserFacingError(
                            kind: .offline,
                            title: "Витрина недоступна офлайн",
                            message: "Нет сети и нет сохранённых данных по этой подборке.",
                        )
                    } else {
                        shelves[index].error = nil
                        shelves[index].isShowingCachedData = true
                        hasCachedData = true
                    }
                } else {
                    let mapped = apiError.userFacing(context: .catalog)
                    shelves[index].error = mapped
                    if shelves[index].athletes.isEmpty, firstNonOfflineError == nil {
                        firstNonOfflineError = mapped
                    }
                }
            }

            shelves[index].isLoading = false
        }

        rebalanceShelvesIfNeeded()

        isShowingCachedData = hasCachedData && !networkMonitor.currentStatus
        if !hasAnyAthletes {
            if let firstNonOfflineError {
                error = firstNonOfflineError
            } else if hasOfflineWithoutCache {
                error = UserFacingError(
                    kind: .offline,
                    title: "Нет сети",
                    message: "Нет сети и нет сохранённых данных витрины. Подключитесь к интернету и обновите экран.",
                )
            } else {
                error = nil
            }
        } else {
            error = nil
        }
    }

    private func rebalanceShelvesIfNeeded() {
        guard let recommended = shelves.first(where: { $0.kind == .recommended })?.athletes,
              !recommended.isEmpty
        else {
            return
        }

        for index in shelves.indices where shelves[index].kind != .recommended {
            if shelves[index].athletes.count >= 3 {
                shelves[index].athletes = Array(shelves[index].athletes.prefix(6))
                continue
            }

            var merged = shelves[index].athletes
            var existing = Set(merged.map(\.id))
            for athlete in recommended where merged.count < 3 {
                if existing.contains(athlete.id) {
                    continue
                }
                merged.append(athlete)
                existing.insert(athlete.id)
            }
            shelves[index].athletes = Array(merged.prefix(6))
        }
    }

    private func cacheKey(shelf: AthleteShelfKind) -> String {
        let query = shelf.searchTerm?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? "recommended"
        return "athletes.shelf.\(shelf.rawValue).q=\(query)"
    }

    private func resolveFollowAvailabilityIfNeeded(force: Bool = false) async {
        guard programsClient != nil else {
            followFeatureAvailability = .unavailable
            return
        }
        guard force || !didResolveFollowAvailability else {
            return
        }
        didResolveFollowAvailability = true

        let probe = await programsClient?.getFollowingCreators(page: 0, size: 1, search: nil) ?? .failure(.invalidURL)
        switch probe {
        case .success:
            followFeatureAvailability = .available
        case let .failure(apiError):
            if isFollowFeatureNotSupported(apiError) {
                followFeatureAvailability = .unavailable
            } else {
                followFeatureAvailability = .available
            }
        }
    }

    private func replayPendingFollowIfNeeded() async {
        guard isAuthenticated, networkMonitor.currentStatus, isFollowFeatureAvailable else { return }
        guard let pendingID = PendingFollowIntentStore.take() else { return }
        guard athlete(for: pendingID) != nil else { return }
        _ = await toggleFollow(influencerId: pendingID)
    }

    private func athlete(for influencerID: UUID) -> InfluencerPublicCard? {
        for shelf in shelves {
            if let athlete = shelf.athletes.first(where: { $0.id == influencerID }) {
                return athlete
            }
        }
        return nil
    }

    private func updateAthlete(_ athlete: InfluencerPublicCard) {
        for shelfIndex in shelves.indices {
            if let athleteIndex = shelves[shelfIndex].athletes.firstIndex(where: { $0.id == athlete.id }) {
                shelves[shelfIndex].athletes[athleteIndex] = athlete
            }
        }
    }

    private var isAuthenticated: Bool {
        let normalized = userSub.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.isEmpty && normalized != "anonymous"
    }
}

@Observable
@MainActor
final class AthleteSearchViewModel {
    private let userSub: String
    private let programsClient: ProgramsClientProtocol?
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring
    private let onUnauthorized: (() -> Void)?

    private var searchTask: Task<Void, Never>?
    private var followLoadingIDs: Set<UUID> = []
    private let cacheTTL: TimeInterval = 60 * 60 * 24

    var query = ""
    var creators: [InfluencerPublicCard] = []
    var isLoading = false
    var isRefreshing = false
    var isShowingCachedData = false
    var error: UserFacingError?
    var infoMessage: String?
    var currentPage = 0
    var totalPages = 0
    private(set) var isFollowFeatureAvailable: Bool

    init(
        userSub: String,
        programsClient: ProgramsClientProtocol?,
        isFollowFeatureAvailable: Bool = true,
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
        onUnauthorized: (() -> Void)? = nil,
    ) {
        self.userSub = userSub
        self.programsClient = programsClient
        self.isFollowFeatureAvailable = isFollowFeatureAvailable
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
        self.onUnauthorized = onUnauthorized
    }

    var isOnline: Bool {
        networkMonitor.currentStatus
    }

    func setFollowFeatureAvailability(_ isAvailable: Bool) {
        isFollowFeatureAvailable = isAvailable
        if !isAvailable {
            followLoadingIDs.removeAll()
        }
    }

    func onAppear() async {
        guard creators.isEmpty else {
            await replayPendingFollowIfNeeded()
            return
        }
        isLoading = true
        await loadPage(page: 0, append: false)
        await replayPendingFollowIfNeeded()
    }

    func refresh() async {
        isRefreshing = true
        error = nil
        infoMessage = nil
        await loadPage(page: 0, append: false)
        await replayPendingFollowIfNeeded()
        isRefreshing = false
    }

    func retry() async {
        isLoading = true
        error = nil
        infoMessage = nil
        await loadPage(page: 0, append: false)
        await replayPendingFollowIfNeeded()
    }

    func searchQueryChanged(_ value: String) {
        query = value
        error = nil
        infoMessage = nil

        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await self.searchSubmit()
        }
    }

    func searchSubmit() async {
        isLoading = true
        await loadPage(page: 0, append: false)
    }

    func loadNextPageIfNeeded(lastID: UUID?) async {
        guard !isLoading else { return }
        guard let lastID, lastID == creators.last?.id else { return }
        let nextPage = currentPage + 1
        guard nextPage < totalPages else { return }

        isLoading = true
        await loadPage(page: nextPage, append: true)
    }

    func isFollowLoading(_ creatorID: UUID) -> Bool {
        followLoadingIDs.contains(creatorID)
    }

    func toggleFollow(influencerId: UUID) async -> InfluencerPublicCard? {
        guard isFollowFeatureAvailable else {
            return creators.first(where: { $0.id == influencerId })
        }
        guard let index = creators.firstIndex(where: { $0.id == influencerId }) else {
            return nil
        }
        guard !followLoadingIDs.contains(influencerId) else {
            return creators[index]
        }
        guard networkMonitor.currentStatus else {
            infoMessage = "Нужен интернет"
            return creators[index]
        }
        guard isAuthenticated else {
            PendingFollowIntentStore.save(influencerId)
            onUnauthorized?()
            return creators[index]
        }

        let before = creators[index]
        let action: FollowMutationAction = before.isFollowedByMe ? .unfollow : .follow
        creators[index] = FollowStateMachine.apply(action, to: before)
        followLoadingIDs.insert(influencerId)
        error = nil
        infoMessage = nil

        let result: Result<Void, APIError> = if let programsClient {
            switch action {
            case .follow:
                await programsClient.followCreator(influencerId: influencerId)
            case .unfollow:
                await programsClient.unfollowCreator(influencerId: influencerId)
            }
        } else {
            .failure(.invalidURL)
        }

        followLoadingIDs.remove(influencerId)

        switch result {
        case .success:
            let updated = creators.first(where: { $0.id == influencerId }) ?? before
            if updated.isFollowedByMe {
                ClientAnalytics.track(.athleteFollowed, properties: ["influencer_id": influencerId.uuidString])
            } else {
                ClientAnalytics.track(.athleteUnfollowed, properties: ["influencer_id": influencerId.uuidString])
            }
            return updated

        case let .failure(apiError):
            if let rollbackIndex = creators.firstIndex(where: { $0.id == influencerId }) {
                creators[rollbackIndex] = before
            }

            if isFollowFeatureNotSupported(apiError) {
                isFollowFeatureAvailable = false
                infoMessage = "Подписки недоступны в текущей версии API."
            } else if apiError == .unauthorized {
                PendingFollowIntentStore.save(influencerId)
                onUnauthorized?()
            } else if isCreatorFollowForbidden(apiError) {
                infoMessage = "Создайте профиль атлета, чтобы подписываться."
            } else {
                error = apiError.userFacing(context: .catalog)
            }
            return creators.first(where: { $0.id == influencerId }) ?? before
        }
    }

    func applyExternalAthleteUpdate(_ creator: InfluencerPublicCard) {
        guard let index = creators.firstIndex(where: { $0.id == creator.id }) else {
            return
        }
        creators[index] = creator
    }

    private func loadPage(page: Int, append: Bool) async {
        defer { isLoading = false }

        let key = cacheKey(query: query, page: page)
        if let cached = await cacheStore.get(key, as: CachedCreatorsPage.self, namespace: userSub) {
            if append {
                creators = merge(existing: creators, incoming: cached.content)
            } else {
                creators = cached.content
            }
            currentPage = cached.metadata.page
            totalPages = cached.metadata.totalPages
            isShowingCachedData = true
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = InfluencersSearchRequest(
            filter: InfluencerSearchFilter(search: trimmedQuery.isEmpty ? nil : trimmedQuery),
            page: page,
            size: 20,
        )

        let result: Result<PagedInfluencerPublicCardResponse, APIError> = if let programsClient {
            await programsClient.influencersSearch(request: request)
        } else {
            .failure(.invalidURL)
        }

        switch result {
        case let .success(response):
            if append {
                creators = merge(existing: creators, incoming: response.content)
            } else {
                creators = response.content
            }
            currentPage = response.metadata.page
            totalPages = response.metadata.totalPages
            error = nil
            infoMessage = nil
            isShowingCachedData = false
            await cacheStore.set(
                key,
                value: CachedCreatorsPage(content: response.content, metadata: response.metadata),
                namespace: userSub,
                ttl: cacheTTL,
            )

        case let .failure(apiError):
            if apiError == .unauthorized {
                onUnauthorized?()
                return
            }
            if apiError == .offline || !networkMonitor.currentStatus {
                if creators.isEmpty {
                    error = UserFacingError(
                        kind: .offline,
                        title: "Поиск атлетов недоступен офлайн",
                        message: "Нет кэша для этого запроса. Подключитесь к интернету и обновите экран.",
                    )
                } else {
                    error = nil
                    isShowingCachedData = true
                }
                return
            }
            error = apiError.userFacing(context: .catalog)
            if !append {
                creators = []
            }
        }
    }

    private func replayPendingFollowIfNeeded() async {
        guard isAuthenticated, networkMonitor.currentStatus, isFollowFeatureAvailable else { return }
        guard let pendingID = PendingFollowIntentStore.take() else { return }
        guard creators.contains(where: { $0.id == pendingID }) else { return }
        _ = await toggleFollow(influencerId: pendingID)
    }

    private func merge(existing: [InfluencerPublicCard], incoming: [InfluencerPublicCard]) -> [InfluencerPublicCard] {
        var result = existing
        var existingIDs = Set(existing.map(\.id))

        for card in incoming where !existingIDs.contains(card.id) {
            result.append(card)
            existingIDs.insert(card.id)
        }

        return result
    }

    private func cacheKey(query: String, page: Int) -> String {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "athletes.search.q=\(normalized)&page=\(page)"
    }

    private var isAuthenticated: Bool {
        let normalized = userSub.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.isEmpty && normalized != "anonymous"
    }
}

@Observable
@MainActor
final class FollowingAthletesViewModel {
    private let userSub: String
    private let programsClient: ProgramsClientProtocol?
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring
    private let onUnauthorized: (() -> Void)?

    private var searchTask: Task<Void, Never>?
    private var followLoadingIDs: Set<UUID> = []
    private var didTrackOpenEvent = false
    private let cacheTTL: TimeInterval = 60 * 60 * 24

    var query = ""
    var creators: [InfluencerPublicCard] = []
    var isLoading = false
    var isRefreshing = false
    var isShowingCachedData = false
    var error: UserFacingError?
    var infoMessage: String?
    var currentPage = 0
    var totalPages = 0
    private(set) var isFollowFeatureAvailable: Bool

    init(
        userSub: String,
        programsClient: ProgramsClientProtocol?,
        isFollowFeatureAvailable: Bool = true,
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
        onUnauthorized: (() -> Void)? = nil,
    ) {
        self.userSub = userSub
        self.programsClient = programsClient
        self.isFollowFeatureAvailable = isFollowFeatureAvailable
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
        self.onUnauthorized = onUnauthorized
    }

    var isOnline: Bool {
        networkMonitor.currentStatus
    }

    func setFollowFeatureAvailability(_ isAvailable: Bool) {
        isFollowFeatureAvailable = isAvailable
        if !isAvailable {
            creators = []
            followLoadingIDs.removeAll()
            error = nil
            infoMessage = nil
        }
    }

    func onAppear() async {
        if !didTrackOpenEvent {
            didTrackOpenEvent = true
            ClientAnalytics.track(.subscriptionsScreenOpened)
        }
        guard isFollowFeatureAvailable else { return }
        guard creators.isEmpty else {
            await replayPendingFollowIfNeeded()
            return
        }
        isLoading = true
        await loadPage(page: 0, append: false)
        await replayPendingFollowIfNeeded()
    }

    func refresh() async {
        guard isFollowFeatureAvailable else { return }
        isRefreshing = true
        error = nil
        infoMessage = nil
        await loadPage(page: 0, append: false)
        await replayPendingFollowIfNeeded()
        isRefreshing = false
    }

    func retry() async {
        guard isFollowFeatureAvailable else { return }
        isLoading = true
        error = nil
        infoMessage = nil
        await loadPage(page: 0, append: false)
        await replayPendingFollowIfNeeded()
    }

    func searchQueryChanged(_ value: String) {
        query = value
        error = nil
        infoMessage = nil

        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await self.searchSubmit()
        }
    }

    func searchSubmit() async {
        guard isFollowFeatureAvailable else { return }
        isLoading = true
        await loadPage(page: 0, append: false)
    }

    func loadNextPageIfNeeded(lastID: UUID?) async {
        guard isFollowFeatureAvailable else { return }
        guard !isLoading else { return }
        guard let lastID, lastID == creators.last?.id else { return }
        let nextPage = currentPage + 1
        guard nextPage < totalPages else { return }

        isLoading = true
        await loadPage(page: nextPage, append: true)
    }

    func isFollowLoading(_ creatorID: UUID) -> Bool {
        followLoadingIDs.contains(creatorID)
    }

    func toggleFollow(influencerId: UUID) async -> InfluencerPublicCard? {
        guard isFollowFeatureAvailable else {
            return creators.first(where: { $0.id == influencerId })
        }
        guard let index = creators.firstIndex(where: { $0.id == influencerId }) else {
            return nil
        }
        guard !followLoadingIDs.contains(influencerId) else {
            return creators[index]
        }
        guard networkMonitor.currentStatus else {
            infoMessage = "Нужен интернет"
            return creators[index]
        }
        guard isAuthenticated else {
            PendingFollowIntentStore.save(influencerId)
            onUnauthorized?()
            return creators[index]
        }

        let before = creators[index]
        let action: FollowMutationAction = before.isFollowedByMe ? .unfollow : .follow
        creators[index] = FollowStateMachine.apply(action, to: before)
        followLoadingIDs.insert(influencerId)
        error = nil
        infoMessage = nil

        let result: Result<Void, APIError> = if let programsClient {
            switch action {
            case .follow:
                await programsClient.followCreator(influencerId: influencerId)
            case .unfollow:
                await programsClient.unfollowCreator(influencerId: influencerId)
            }
        } else {
            .failure(.invalidURL)
        }

        followLoadingIDs.remove(influencerId)

        switch result {
        case .success:
            if action == .unfollow {
                creators.removeAll(where: { $0.id == influencerId })
                ClientAnalytics.track(.athleteUnfollowed, properties: ["influencer_id": influencerId.uuidString])
                return nil
            }
            let updated = creators.first(where: { $0.id == influencerId }) ?? before
            ClientAnalytics.track(.athleteFollowed, properties: ["influencer_id": influencerId.uuidString])
            return updated

        case let .failure(apiError):
            if let rollbackIndex = creators.firstIndex(where: { $0.id == influencerId }) {
                creators[rollbackIndex] = before
            }

            if isFollowFeatureNotSupported(apiError) {
                isFollowFeatureAvailable = false
                creators = []
                infoMessage = "Подписки недоступны в текущей версии API."
            } else if apiError == .unauthorized {
                PendingFollowIntentStore.save(influencerId)
                onUnauthorized?()
            } else if isCreatorFollowForbidden(apiError) {
                infoMessage = "Создайте профиль атлета, чтобы подписываться."
            } else {
                error = apiError.userFacing(context: .catalog)
            }
            return creators.first(where: { $0.id == influencerId }) ?? before
        }
    }

    func applyExternalAthleteUpdate(_ creator: InfluencerPublicCard) {
        if let index = creators.firstIndex(where: { $0.id == creator.id }) {
            if creator.isFollowedByMe {
                creators[index] = creator
            } else {
                creators.remove(at: index)
            }
            return
        }

        guard creator.isFollowedByMe else {
            return
        }
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || creator.displayName.lowercased().contains(query.lowercased())
        else {
            return
        }
        creators.insert(creator, at: 0)
    }

    private func loadPage(page: Int, append: Bool) async {
        defer { isLoading = false }

        let key = cacheKey(query: query, page: page)
        if let cached = await cacheStore.get(key, as: CachedCreatorsPage.self, namespace: userSub) {
            if append {
                creators = merge(existing: creators, incoming: cached.content)
            } else {
                creators = cached.content
            }
            currentPage = cached.metadata.page
            totalPages = cached.metadata.totalPages
            isShowingCachedData = true
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let result: Result<PagedInfluencerPublicCardResponse, APIError> = if let programsClient {
            await programsClient.getFollowingCreators(page: page, size: 20, search: trimmedQuery.isEmpty ? nil : trimmedQuery)
        } else {
            .failure(.invalidURL)
        }

        switch result {
        case let .success(response):
            let onlyFollowing = response.content.filter(\.isFollowedByMe)
            if append {
                creators = merge(existing: creators, incoming: onlyFollowing)
            } else {
                creators = onlyFollowing
            }
            currentPage = response.metadata.page
            totalPages = response.metadata.totalPages
            error = nil
            infoMessage = nil
            isShowingCachedData = false
            await cacheStore.set(
                key,
                value: CachedCreatorsPage(content: onlyFollowing, metadata: response.metadata),
                namespace: userSub,
                ttl: cacheTTL,
            )

        case let .failure(apiError):
            if isFollowFeatureNotSupported(apiError) {
                isFollowFeatureAvailable = false
                creators = []
                error = nil
                infoMessage = "Подписки недоступны в текущей версии API."
                return
            }
            if apiError == .unauthorized {
                onUnauthorized?()
                return
            }
            if apiError == .offline || !networkMonitor.currentStatus {
                if creators.isEmpty {
                    error = UserFacingError(
                        kind: .offline,
                        title: "Подписки недоступны офлайн",
                        message: "Нет кэша для списка подписок. Подключитесь к интернету и обновите экран.",
                    )
                } else {
                    error = nil
                    isShowingCachedData = true
                }
                return
            }
            error = apiError.userFacing(context: .catalog)
            if !append {
                creators = []
            }
        }
    }

    private func replayPendingFollowIfNeeded() async {
        guard isAuthenticated, networkMonitor.currentStatus, isFollowFeatureAvailable else { return }
        guard let pendingID = PendingFollowIntentStore.take() else { return }
        guard creators.contains(where: { $0.id == pendingID }) else { return }
        _ = await toggleFollow(influencerId: pendingID)
    }

    private func merge(existing: [InfluencerPublicCard], incoming: [InfluencerPublicCard]) -> [InfluencerPublicCard] {
        var result = existing
        var existingIDs = Set(existing.map(\.id))

        for card in incoming where !existingIDs.contains(card.id) {
            result.append(card)
            existingIDs.insert(card.id)
        }

        return result
    }

    private func cacheKey(query: String, page: Int) -> String {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "athletes.following.q=\(normalized)&page=\(page)"
    }

    private var isAuthenticated: Bool {
        let normalized = userSub.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.isEmpty && normalized != "anonymous"
    }
}

@Observable
@MainActor
final class AthleteProfileViewModel {
    let userSub: String
    let creatorID: UUID

    private let programsClient: ProgramsClientProtocol?
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring
    private let onUnauthorized: (() -> Void)?

    private let cacheTTL: TimeInterval = 60 * 60 * 24
    private let signaturePageSize = 8
    private var followLoading = false
    private var didTrackViewedEvent = false

    var creator: InfluencerPublicCard
    var programs: [ProgramListItem] = []
    var isLoadingPrograms = false
    var isShowingCachedData = false
    var error: UserFacingError?
    var infoMessage: String?
    var currentPage = 0
    var totalPages = 0
    var totalElements = 0
    private(set) var isFollowFeatureAvailable: Bool

    init(
        userSub: String,
        creator: InfluencerPublicCard,
        programsClient: ProgramsClientProtocol?,
        isFollowFeatureAvailable: Bool = true,
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
        onUnauthorized: (() -> Void)? = nil,
    ) {
        self.userSub = userSub
        creatorID = creator.id
        self.creator = creator
        self.programsClient = programsClient
        self.isFollowFeatureAvailable = isFollowFeatureAvailable
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
        self.onUnauthorized = onUnauthorized
    }

    var isFollowLoading: Bool {
        followLoading
    }

    var canFollowActions: Bool {
        networkMonitor.currentStatus && isFollowFeatureAvailable
    }

    var signaturePrograms: [ProgramListItem] {
        Array(programs.prefix(4))
    }

    var canOpenAllPrograms: Bool {
        totalElements > signaturePrograms.count || totalPages > 1 || programs.count > signaturePrograms.count
    }

    func setFollowFeatureAvailability(_ isAvailable: Bool) {
        isFollowFeatureAvailable = isAvailable
    }

    func onAppear() async {
        if !didTrackViewedEvent {
            didTrackViewedEvent = true
            ClientAnalytics.track(.athleteViewed, properties: ["influencer_id": creatorID.uuidString])
        }

        guard programs.isEmpty else {
            await replayPendingFollowIfNeeded()
            return
        }
        isLoadingPrograms = true
        await loadProgramsPage(page: 0, append: false)
        await replayPendingFollowIfNeeded()
    }

    func refresh() async {
        isLoadingPrograms = true
        await loadProgramsPage(page: 0, append: false)
        await replayPendingFollowIfNeeded()
    }

    func loadNextPageIfNeeded(lastID: String?) async {
        guard !isLoadingPrograms else { return }
        guard let lastID, lastID == programs.last?.id else { return }
        let nextPage = currentPage + 1
        guard nextPage < totalPages else { return }

        isLoadingPrograms = true
        await loadProgramsPage(page: nextPage, append: true)
    }

    func toggleFollow() async -> InfluencerPublicCard {
        guard isFollowFeatureAvailable else {
            return creator
        }
        guard !followLoading else {
            return creator
        }
        guard networkMonitor.currentStatus else {
            infoMessage = "Нужен интернет"
            return creator
        }
        guard isAuthenticated else {
            PendingFollowIntentStore.save(creatorID)
            onUnauthorized?()
            return creator
        }

        let before = creator
        let action: FollowMutationAction = before.isFollowedByMe ? .unfollow : .follow
        creator = FollowStateMachine.apply(action, to: before)
        followLoading = true
        error = nil
        infoMessage = nil

        let result: Result<Void, APIError> = if let programsClient {
            switch action {
            case .follow:
                await programsClient.followCreator(influencerId: creatorID)
            case .unfollow:
                await programsClient.unfollowCreator(influencerId: creatorID)
            }
        } else {
            .failure(.invalidURL)
        }

        followLoading = false

        switch result {
        case .success:
            if creator.isFollowedByMe {
                ClientAnalytics.track(.athleteFollowed, properties: ["influencer_id": creatorID.uuidString])
            } else {
                ClientAnalytics.track(.athleteUnfollowed, properties: ["influencer_id": creatorID.uuidString])
            }
            return creator

        case let .failure(apiError):
            creator = before
            if isFollowFeatureNotSupported(apiError) {
                isFollowFeatureAvailable = false
                infoMessage = "Подписки недоступны в текущей версии API."
                return creator
            }
            if apiError == .unauthorized {
                PendingFollowIntentStore.save(creatorID)
                onUnauthorized?()
            } else if isCreatorFollowForbidden(apiError) {
                infoMessage = "Создайте профиль атлета, чтобы подписываться."
            } else {
                error = apiError.userFacing(context: .catalog)
            }
            return creator
        }
    }

    func trackProgramOpened(programID: String) {
        ClientAnalytics.track(
            .athleteProgramViewed,
            properties: [
                "influencer_id": creatorID.uuidString,
                "program_id": programID,
            ],
        )
    }

    func applyExternalAthleteUpdate(_ updated: InfluencerPublicCard) {
        guard creator.id == updated.id else { return }
        creator = updated
    }

    private func loadProgramsPage(page: Int, append: Bool) async {
        defer { isLoadingPrograms = false }

        let key = cacheKey(page: page)
        if let cached = await cacheStore.get(key, as: CachedCreatorProgramsPage.self, namespace: userSub) {
            if append {
                programs = merge(existing: programs, incoming: cached.content)
            } else {
                programs = cached.content
            }
            currentPage = cached.metadata.page
            totalPages = cached.metadata.totalPages
            totalElements = max(cached.metadata.totalElements, programs.count)
            isShowingCachedData = true
        }

        let size = page == 0 ? signaturePageSize : 20
        let result: Result<PagedProgramResponse, APIError> = if let programsClient {
            await programsClient.getCreatorPrograms(influencerId: creatorID, page: page, size: size)
        } else {
            .failure(.invalidURL)
        }

        switch result {
        case let .success(response):
            if append {
                programs = merge(existing: programs, incoming: response.content)
            } else {
                programs = response.content
            }
            currentPage = response.metadata.page
            totalPages = response.metadata.totalPages
            totalElements = max(response.metadata.totalElements, programs.count)
            error = nil
            infoMessage = nil
            isShowingCachedData = false
            await cacheStore.set(
                key,
                value: CachedCreatorProgramsPage(content: response.content, metadata: response.metadata),
                namespace: userSub,
                ttl: cacheTTL,
            )

        case let .failure(apiError):
            if apiError == .unauthorized {
                onUnauthorized?()
                return
            }
            if apiError == .offline || !networkMonitor.currentStatus {
                if programs.isEmpty {
                    error = UserFacingError(
                        kind: .offline,
                        title: "Программы недоступны офлайн",
                        message: "Нет кэша программ этого атлета. Подключитесь к интернету и обновите экран.",
                    )
                } else {
                    error = nil
                    isShowingCachedData = true
                }
                return
            }
            error = apiError.userFacing(context: .catalog)
            if !append {
                programs = []
                totalElements = 0
            }
        }
    }

    private func replayPendingFollowIfNeeded() async {
        guard isAuthenticated, networkMonitor.currentStatus, isFollowFeatureAvailable else { return }
        guard let pendingID = PendingFollowIntentStore.take(), pendingID == creatorID else { return }
        _ = await toggleFollow()
    }

    private func merge(existing: [ProgramListItem], incoming: [ProgramListItem]) -> [ProgramListItem] {
        var result = existing
        var existingIDs = Set(existing.map(\.id))

        for card in incoming where !existingIDs.contains(card.id) {
            result.append(card)
            existingIDs.insert(card.id)
        }

        return result
    }

    private func cacheKey(page: Int) -> String {
        "athletes.programs.id=\(creatorID.uuidString)&page=\(page)"
    }

    private var isAuthenticated: Bool {
        let normalized = userSub.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.isEmpty && normalized != "anonymous"
    }
}

typealias CreatorsDiscoveryViewModel = AthleteSearchViewModel
typealias FollowingCreatorsViewModel = FollowingAthletesViewModel
typealias CreatorProfileViewModel = AthleteProfileViewModel
typealias ProgramsCatalogViewModel = CatalogViewModel
typealias AthletesCatalogViewModel = AthletesShowcaseViewModel

struct CatalogScreen: View {
    @State var programsViewModel: CatalogViewModel
    @State var athletesShowcaseViewModel: AthletesShowcaseViewModel
    @State var athletesSearchViewModel: AthleteSearchViewModel
    @State var followingViewModel: FollowingAthletesViewModel

    let userSub: String
    let environment: AppEnvironment
    let onProgramTap: (String) -> Void
    let onUnauthorized: (() -> Void)?

    @State private var selectedSegment: CatalogHubSegment
    @State private var selectedCreator: InfluencerPublicCard?

    init(
        programsViewModel: CatalogViewModel,
        athletesShowcaseViewModel: AthletesShowcaseViewModel,
        athletesSearchViewModel: AthleteSearchViewModel,
        followingViewModel: FollowingAthletesViewModel,
        userSub: String,
        environment: AppEnvironment,
        onProgramTap: @escaping (String) -> Void,
        onUnauthorized: (() -> Void)? = nil,
    ) {
        _programsViewModel = State(initialValue: programsViewModel)
        _athletesShowcaseViewModel = State(initialValue: athletesShowcaseViewModel)
        _athletesSearchViewModel = State(initialValue: athletesSearchViewModel)
        _followingViewModel = State(initialValue: followingViewModel)
        self.userSub = userSub
        self.environment = environment
        self.onProgramTap = onProgramTap
        self.onUnauthorized = onUnauthorized

        let persisted = UserDefaults.standard.string(forKey: Self.segmentStorageKey(for: userSub))
        _selectedSegment = State(initialValue: CatalogHubSegment(rawValue: persisted ?? "") ?? .programs)
    }

    var body: some View {
        VStack(spacing: FFSpacing.sm) {
            Picker("Раздел каталога", selection: $selectedSegment) {
                ForEach(CatalogHubSegment.allCases) { segment in
                    Text(segment.title).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, FFSpacing.md)
            .padding(.top, FFSpacing.md)
            .onChange(of: selectedSegment) { _, newValue in
                UserDefaults.standard.set(newValue.rawValue, forKey: Self.segmentStorageKey(for: userSub))
            }

            switch selectedSegment {
            case .programs:
                ProgramsCatalogScreen(
                    viewModel: programsViewModel,
                    environment: environment,
                    onProgramTap: onProgramTap,
                )

            case .athletes:
                AthletesCatalogScreen(
                    showcaseViewModel: athletesShowcaseViewModel,
                    searchViewModel: athletesSearchViewModel,
                    followingViewModel: followingViewModel,
                    environment: environment,
                    onOpenAthleteProfile: { creator in
                        selectedCreator = creator
                    },
                    onAthleteUpdated: { creator in
                        applyCreatorUpdate(creator)
                    },
                )
            }
        }
        .background(FFColors.background)
        .navigationDestination(item: $selectedCreator) { creator in
            AthleteProfileView(
                viewModel: AthleteProfileViewModel(
                    userSub: userSub,
                    creator: creator,
                    programsClient: programsViewModel.programsClientForCreatorFlows,
                    isFollowFeatureAvailable: athletesShowcaseViewModel.isFollowFeatureAvailable,
                    onUnauthorized: onUnauthorized,
                ),
                environment: environment,
                onProgramTap: { programID in
                    onProgramTap(programID)
                },
                onCreatorUpdated: { updated in
                    applyCreatorUpdate(updated)
                },
            )
            .navigationTitle("Профиль атлета")
        }
    }

    private func applyCreatorUpdate(_ creator: InfluencerPublicCard) {
        athletesShowcaseViewModel.applyExternalAthleteUpdate(creator)
        athletesSearchViewModel.applyExternalAthleteUpdate(creator)
        followingViewModel.applyExternalAthleteUpdate(creator)
        if selectedCreator?.id == creator.id {
            selectedCreator = creator
        }
    }

    private static func segmentStorageKey(for userSub: String) -> String {
        "catalog.segment.last.\(userSub)"
    }
}

typealias CatalogHubScreen = CatalogScreen

struct AthletesCatalogScreen: View {
    @State var showcaseViewModel: AthletesShowcaseViewModel
    @State var searchViewModel: AthleteSearchViewModel
    @State var followingViewModel: FollowingAthletesViewModel
    let environment: AppEnvironment
    let onOpenAthleteProfile: (InfluencerPublicCard) -> Void
    let onAthleteUpdated: (InfluencerPublicCard) -> Void

    @State private var isSearchPresented = false
    @State private var isFollowingPresented = false

    var body: some View {
        VStack(spacing: FFSpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FFSpacing.xs) {
                    catalogActionButton(
                        title: "Поиск",
                        systemImage: "magnifyingglass",
                    ) {
                        isSearchPresented = true
                    }

                    catalogActionButton(
                        title: "Все атлеты",
                        systemImage: "list.bullet",
                    ) {
                        isSearchPresented = true
                    }

                    if showcaseViewModel.isFollowFeatureAvailable {
                        catalogActionButton(
                            title: "Подписки",
                            systemImage: "person.2.fill",
                        ) {
                            isFollowingPresented = true
                        }
                    }
                }
                .padding(.horizontal, FFSpacing.md)
            }

            AthletesShowcaseView(
                viewModel: showcaseViewModel,
                environment: environment,
                onOpenAthleteProfile: onOpenAthleteProfile,
                onAthleteUpdated: onAthleteUpdated,
            )
        }
        .background(FFColors.background)
        .navigationDestination(isPresented: $isSearchPresented) {
            AthletesSearchView(
                viewModel: searchViewModel,
                environment: environment,
                onOpenAthleteProfile: onOpenAthleteProfile,
                onAthleteUpdated: onAthleteUpdated,
            )
            .navigationTitle("Все атлеты")
        }
        .navigationDestination(isPresented: $isFollowingPresented) {
            FollowingAthletesView(
                viewModel: followingViewModel,
                environment: environment,
                onOpenAthleteProfile: onOpenAthleteProfile,
                onAthleteUpdated: onAthleteUpdated,
            )
            .navigationTitle("Подписки")
        }
        .onChange(of: showcaseViewModel.isFollowFeatureAvailable) { _, isAvailable in
            searchViewModel.setFollowFeatureAvailability(isAvailable)
            followingViewModel.setFollowFeatureAvailability(isAvailable)
            if !isAvailable {
                isFollowingPresented = false
            }
        }
        .task {
            searchViewModel.setFollowFeatureAvailability(showcaseViewModel.isFollowFeatureAvailable)
            followingViewModel.setFollowFeatureAvailability(showcaseViewModel.isFollowFeatureAvailable)
        }
    }

    private func catalogActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .padding(.horizontal, FFSpacing.sm)
                .frame(minHeight: 40)
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

struct AthletesShowcaseView: View {
    @State var viewModel: AthletesShowcaseViewModel
    let environment: AppEnvironment
    let onOpenAthleteProfile: (InfluencerPublicCard) -> Void
    let onAthleteUpdated: (InfluencerPublicCard) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                if viewModel.isShowingCachedData {
                    cachedDataBadge
                }

                if let infoMessage = viewModel.infoMessage {
                    FFCard {
                        Text(infoMessage)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }

                if viewModel.isLoading, !viewModel.hasAnyAthletes {
                    FFLoadingState(title: "Загружаем витрину атлетов")
                } else if let error = viewModel.error, !viewModel.hasAnyAthletes {
                    FFErrorState(
                        title: error.title,
                        message: error.message,
                        retryTitle: "Повторить",
                        onRetry: { Task { await viewModel.retry() } },
                    )
                } else {
                    ForEach(viewModel.shelves) { shelf in
                        AthleteShelfView(
                            shelf: shelf,
                            environment: environment,
                            isFollowFeatureAvailable: viewModel.isFollowFeatureAvailable,
                            isFollowEnabled: viewModel.isFollowFeatureAvailable && viewModel.isOnline,
                            followHint: viewModel.isFollowFeatureAvailable && !viewModel.isOnline ? "Нужен интернет" : nil,
                            isFollowLoading: { id in viewModel.isFollowLoading(id) },
                            onOpenAthleteProfile: onOpenAthleteProfile,
                            onFollowTap: { influencerID in
                                Task {
                                    if let updated = await viewModel.toggleFollow(influencerId: influencerID) {
                                        onAthleteUpdated(updated)
                                    }
                                }
                            },
                        )
                    }
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.bottom, FFSpacing.lg)
        }
        .background(FFColors.background)
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.onAppear()
        }
    }

    private var cachedDataBadge: some View {
        FFCard {
            Text("Нет сети — показаны сохранённые данные")
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.primary)
        }
    }
}

private struct AthleteShelfView: View {
    let shelf: AthleteShelfState
    let environment: AppEnvironment
    let isFollowFeatureAvailable: Bool
    let isFollowEnabled: Bool
    let followHint: String?
    let isFollowLoading: (UUID) -> Bool
    let onOpenAthleteProfile: (InfluencerPublicCard) -> Void
    let onFollowTap: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            HStack {
                Text(shelf.kind.title)
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Spacer(minLength: FFSpacing.sm)
                if shelf.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if shelf.athletes.isEmpty {
                if let error = shelf.error {
                    FFCard {
                        Text(error.message)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                } else {
                    FFCard {
                        Text("В этой подборке пока нет данных.")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FFSpacing.sm) {
                        ForEach(Array(shelf.athletes.prefix(6))) { athlete in
                            AthleteCard(
                                creator: athlete,
                                environment: environment,
                                followButtonState: isFollowLoading(athlete.id) ? .loading : (athlete.isFollowedByMe ? .following : .follow),
                                isFollowFeatureAvailable: isFollowFeatureAvailable,
                                isFollowEnabled: isFollowEnabled,
                                followHint: followHint,
                                onTap: {
                                    onOpenAthleteProfile(athlete)
                                },
                                onFollowTap: {
                                    onFollowTap(athlete.id)
                                },
                            )
                            .frame(width: 250)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}

struct AthletesSearchView: View {
    @State var viewModel: AthleteSearchViewModel
    let environment: AppEnvironment
    let onOpenAthleteProfile: (InfluencerPublicCard) -> Void
    let onAthleteUpdated: (InfluencerPublicCard) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                if viewModel.isShowingCachedData {
                    cachedDataBadge
                }

                FFTextField(
                    label: "Поиск атлетов",
                    placeholder: "Имя атлета",
                    text: Binding(
                        get: { viewModel.query },
                        set: { viewModel.searchQueryChanged($0) },
                    ),
                    helperText: "Поиск запускается автоматически",
                )

                if let infoMessage = viewModel.infoMessage {
                    FFCard {
                        Text(infoMessage)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }

                if viewModel.isLoading, viewModel.creators.isEmpty {
                    FFLoadingState(title: "Загружаем атлетов")
                } else if let error = viewModel.error, viewModel.creators.isEmpty {
                    FFErrorState(
                        title: error.title,
                        message: error.message,
                        retryTitle: "Повторить",
                        onRetry: { Task { await viewModel.retry() } },
                    )
                } else if viewModel.creators.isEmpty {
                    FFEmptyState(
                        title: "Атлеты не найдены",
                        message: "Попробуйте изменить запрос или повторите позже.",
                    )
                } else {
                    LazyVStack(spacing: FFSpacing.sm) {
                        ForEach(viewModel.creators) { creator in
                            AthleteListCard(
                                creator: creator,
                                environment: environment,
                                followButtonState: viewModel.isFollowLoading(creator.id) ? .loading : (creator.isFollowedByMe ? .following : .follow),
                                isFollowFeatureAvailable: viewModel.isFollowFeatureAvailable,
                                isFollowEnabled: viewModel.isFollowFeatureAvailable && viewModel.isOnline,
                                followHint: viewModel.isFollowFeatureAvailable && !viewModel.isOnline ? "Нужен интернет" : nil,
                                onTap: {
                                    onOpenAthleteProfile(creator)
                                },
                                onFollowTap: {
                                    Task {
                                        if let updated = await viewModel.toggleFollow(influencerId: creator.id) {
                                            onAthleteUpdated(updated)
                                        }
                                    }
                                },
                            )
                            .onAppear {
                                Task {
                                    await viewModel.loadNextPageIfNeeded(lastID: creator.id)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.bottom, FFSpacing.lg)
        }
        .background(FFColors.background)
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.onAppear()
        }
    }

    private var cachedDataBadge: some View {
        FFCard {
            Text("Нет сети — показаны сохранённые данные")
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.primary)
        }
    }
}

struct FollowingAthletesView: View {
    @State var viewModel: FollowingAthletesViewModel
    let environment: AppEnvironment
    let onOpenAthleteProfile: (InfluencerPublicCard) -> Void
    let onAthleteUpdated: (InfluencerPublicCard) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                if viewModel.isShowingCachedData {
                    cachedDataBadge
                }

                FFTextField(
                    label: "Поиск в подписках",
                    placeholder: "Имя атлета",
                    text: Binding(
                        get: { viewModel.query },
                        set: { viewModel.searchQueryChanged($0) },
                    ),
                    helperText: "Поиск только по вашим подпискам",
                )

                if let infoMessage = viewModel.infoMessage {
                    FFCard {
                        Text(infoMessage)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }

                if viewModel.isLoading, viewModel.creators.isEmpty {
                    FFLoadingState(title: "Загружаем подписки")
                } else if let error = viewModel.error, viewModel.creators.isEmpty {
                    FFErrorState(
                        title: error.title,
                        message: error.message,
                        retryTitle: "Повторить",
                        onRetry: { Task { await viewModel.retry() } },
                    )
                } else if viewModel.creators.isEmpty {
                    FFEmptyState(
                        title: "Список подписок пуст",
                        message: "Подпишитесь на атлетов в разделе «Витрина».",
                    )
                } else {
                    LazyVStack(spacing: FFSpacing.sm) {
                        ForEach(viewModel.creators) { creator in
                            AthleteListCard(
                                creator: creator,
                                environment: environment,
                                followButtonState: viewModel.isFollowLoading(creator.id) ? .loading : (creator.isFollowedByMe ? .following : .follow),
                                isFollowFeatureAvailable: viewModel.isFollowFeatureAvailable,
                                isFollowEnabled: viewModel.isFollowFeatureAvailable && viewModel.isOnline,
                                followHint: viewModel.isFollowFeatureAvailable && !viewModel.isOnline ? "Нужен интернет" : nil,
                                onTap: {
                                    onOpenAthleteProfile(creator)
                                },
                                onFollowTap: {
                                    Task {
                                        if let updated = await viewModel.toggleFollow(influencerId: creator.id) {
                                            onAthleteUpdated(updated)
                                        }
                                    }
                                },
                            )
                            .onAppear {
                                Task {
                                    await viewModel.loadNextPageIfNeeded(lastID: creator.id)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.bottom, FFSpacing.lg)
        }
        .background(FFColors.background)
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.onAppear()
        }
    }

    private var cachedDataBadge: some View {
        FFCard {
            Text("Нет сети — показаны сохранённые данные")
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.primary)
        }
    }
}

struct AthleteProfileView: View {
    @State var viewModel: AthleteProfileViewModel
    let environment: AppEnvironment?
    let onProgramTap: (String) -> Void
    let onCreatorUpdated: (InfluencerPublicCard) -> Void

    @State private var isAllProgramsPresented = false

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                AthleteProfileHeader(
                    creator: viewModel.creator,
                    environment: environment,
                    followButtonState: viewModel.isFollowLoading ? .loading : (viewModel.creator.isFollowedByMe ? .following : .follow),
                    isFollowFeatureAvailable: viewModel.isFollowFeatureAvailable,
                    isFollowEnabled: viewModel.canFollowActions,
                    followHint: viewModel.isFollowFeatureAvailable && !viewModel.canFollowActions ? "Нужен интернет" : nil,
                    onFollowTap: {
                        Task {
                            let updated = await viewModel.toggleFollow()
                            onCreatorUpdated(updated)
                        }
                    },
                )

                if let info = viewModel.infoMessage {
                    FFCard {
                        Text(info)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }

                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.sm) {
                        HStack {
                            Text("Фирменные программы")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)
                            Spacer(minLength: FFSpacing.sm)
                            if viewModel.isLoadingPrograms {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        if viewModel.isShowingCachedData {
                            Text("Нет сети — показаны сохранённые данные")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                        }

                        if viewModel.isLoadingPrograms, viewModel.programs.isEmpty {
                            FFLoadingState(title: "Загружаем программы атлета")
                        } else if let error = viewModel.error, viewModel.programs.isEmpty {
                            FFErrorState(
                                title: error.title,
                                message: error.message,
                                retryTitle: "Повторить",
                                onRetry: { Task { await viewModel.refresh() } },
                            )
                        } else if viewModel.programs.isEmpty {
                            Text("У атлета пока нет опубликованных программ.")
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        } else {
                            LazyVStack(spacing: FFSpacing.sm) {
                                ForEach(viewModel.signaturePrograms) { program in
                                    AthleteProgramCatalogCard(
                                        program: program,
                                        environment: environment,
                                        onTap: {
                                            viewModel.trackProgramOpened(programID: program.id)
                                            onProgramTap(program.id)
                                        },
                                    )
                                }
                            }

                            if viewModel.canOpenAllPrograms {
                                FFButton(title: "Все программы атлета", variant: .secondary) {
                                    isAllProgramsPresented = true
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.onAppear()
        }
        .navigationDestination(isPresented: $isAllProgramsPresented) {
            AthleteProgramsListView(
                viewModel: viewModel,
                environment: environment,
                onProgramTap: onProgramTap,
            )
            .navigationTitle("Программы атлета")
        }
    }
}

typealias CreatorProfileView = AthleteProfileView

private struct AthleteProgramsListView: View {
    @State var viewModel: AthleteProfileViewModel
    let environment: AppEnvironment?
    let onProgramTap: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                if viewModel.isShowingCachedData {
                    FFCard {
                        Text("Нет сети — показаны сохранённые данные")
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.primary)
                    }
                }

                if viewModel.isLoadingPrograms, viewModel.programs.isEmpty {
                    FFLoadingState(title: "Загружаем программы атлета")
                } else if let error = viewModel.error, viewModel.programs.isEmpty {
                    FFErrorState(
                        title: error.title,
                        message: error.message,
                        retryTitle: "Повторить",
                        onRetry: { Task { await viewModel.refresh() } },
                    )
                } else if viewModel.programs.isEmpty {
                    FFEmptyState(
                        title: "Программы не найдены",
                        message: "Попробуйте открыть экран позже.",
                    )
                } else {
                    LazyVStack(spacing: FFSpacing.sm) {
                        ForEach(viewModel.programs) { program in
                            AthleteProgramCatalogCard(
                                program: program,
                                environment: environment,
                                onTap: {
                                    viewModel.trackProgramOpened(programID: program.id)
                                    onProgramTap(program.id)
                                },
                            )
                            .onAppear {
                                Task {
                                    await viewModel.loadNextPageIfNeeded(lastID: program.id)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .refreshable {
            await viewModel.refresh()
        }
    }
}

private struct AthleteProfileHeader: View {
    let creator: InfluencerPublicCard
    let environment: AppEnvironment?
    let followButtonState: FollowButtonState
    let isFollowFeatureAvailable: Bool
    let isFollowEnabled: Bool
    let followHint: String?
    let onFollowTap: (() -> Void)?

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack(alignment: .top, spacing: FFSpacing.sm) {
                    avatarView

                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                        Text(creator.displayName)
                            .font(FFTypography.h1)
                            .foregroundStyle(FFColors.textPrimary)
                            .lineLimit(2)

                        if creator.followersCount > 0 {
                            Text("Подписчики: \(creator.followersCount)")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                        }

                        if let direction = creator.directionTag?.trimmedNilIfEmpty {
                            Text(direction)
                                .font(FFTypography.caption.weight(.semibold))
                                .foregroundStyle(FFColors.accent)
                                .padding(.horizontal, FFSpacing.xs)
                                .padding(.vertical, FFSpacing.xxs)
                                .background(FFColors.accent.opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }

                    Spacer(minLength: FFSpacing.sm)

                    if isFollowFeatureAvailable, let onFollowTap {
                        FollowButton(
                            state: followButtonState,
                            isEnabled: isFollowEnabled,
                            action: onFollowTap,
                        )
                    }
                }

                if let followHint {
                    Text(followHint)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }

                if let bio = creator.bio?.trimmedNilIfEmpty {
                    Text(bio)
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                        .lineLimit(3)
                }

                if let achievements = creator.achievements, !achievements.isEmpty {
                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                        Text("Достижения")
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.textSecondary)
                        ForEach(Array(achievements.prefix(3)), id: \.self) { item in
                            Text("• \(item)")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textPrimary)
                        }
                    }
                }

                if let philosophy = creator.trainingPhilosophy?.trimmedNilIfEmpty {
                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                        Text("Философия тренировок")
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.textSecondary)
                        Text(philosophy)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textPrimary)
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    private var avatarView: some View {
        Group {
            if let url = resolvedAvatarURL(creator.avatar) {
                FFRemoteImage(url: url) {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(FFColors.gray700)
            .overlay {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(FFColors.gray300)
            }
    }

    private func resolvedAvatarURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        if url.scheme != nil {
            return url
        }
        guard let baseURL = environment?.backendBaseURL else {
            return url
        }
        let normalizedPath = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        return baseURL.appendingPathComponent(normalizedPath)
    }
}

struct AthleteCard: View {
    let creator: InfluencerPublicCard
    let environment: AppEnvironment?
    let followButtonState: FollowButtonState
    let isFollowFeatureAvailable: Bool
    let isFollowEnabled: Bool
    let followHint: String?
    let onTap: (() -> Void)?
    let onFollowTap: (() -> Void)?

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Button {
                    onTap?()
                } label: {
                    HStack(alignment: .top, spacing: FFSpacing.sm) {
                        avatarView
                        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                            Text(creator.displayName)
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                                .lineLimit(2)

                            if let direction = creator.directionTag?.trimmedNilIfEmpty {
                                Text(direction)
                                    .font(FFTypography.caption.weight(.semibold))
                                    .foregroundStyle(FFColors.accent)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: FFSpacing.xs)
                    }
                }
                .buttonStyle(.plain)
                .disabled(onTap == nil)

                if creator.programsCount > 0 || creator.followersCount > 0 {
                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                        if creator.programsCount > 0 {
                            Text("Программ: \(creator.programsCount)")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                        if creator.followersCount > 0 {
                            Text("Подписчики: \(creator.followersCount)")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }
                }

                if isFollowFeatureAvailable, let onFollowTap {
                    FollowButton(
                        state: followButtonState,
                        isEnabled: isFollowEnabled,
                        action: onFollowTap,
                    )
                    .frame(minHeight: 44)
                }

                if let followHint {
                    Text(followHint)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    private var avatarView: some View {
        Group {
            if let url = resolvedAvatarURL(creator.avatar) {
                FFRemoteImage(url: url) {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(FFColors.gray700)
            .overlay {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(FFColors.gray300)
            }
    }

    private func resolvedAvatarURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        if url.scheme != nil {
            return url
        }
        guard let baseURL = environment?.backendBaseURL else {
            return url
        }
        let normalizedPath = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        return baseURL.appendingPathComponent(normalizedPath)
    }
}

private struct AthleteListCard: View {
    let creator: InfluencerPublicCard
    let environment: AppEnvironment?
    let followButtonState: FollowButtonState
    let isFollowFeatureAvailable: Bool
    let isFollowEnabled: Bool
    let followHint: String?
    let onTap: (() -> Void)?
    let onFollowTap: (() -> Void)?

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack(alignment: .top, spacing: FFSpacing.sm) {
                    Button {
                        onTap?()
                    } label: {
                        HStack(alignment: .top, spacing: FFSpacing.sm) {
                            avatarView
                            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                Text(creator.displayName)
                                    .font(FFTypography.h2)
                                    .foregroundStyle(FFColors.textPrimary)
                                    .lineLimit(1)

                                if let direction = creator.directionTag?.trimmedNilIfEmpty {
                                    Text(direction)
                                        .font(FFTypography.caption.weight(.semibold))
                                        .foregroundStyle(FFColors.accent)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(onTap == nil)

                    if isFollowFeatureAvailable, let onFollowTap {
                        FollowButton(
                            state: followButtonState,
                            isEnabled: isFollowEnabled,
                            action: onFollowTap,
                        )
                        .frame(minHeight: 44)
                    }
                }

                if creator.programsCount > 0 || creator.followersCount > 0 {
                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                        if creator.programsCount > 0 {
                            Text("Программ: \(creator.programsCount)")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                        if creator.followersCount > 0 {
                            Text("Подписчики: \(creator.followersCount)")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }
                }

                if let followHint {
                    Text(followHint)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    private var avatarView: some View {
        Group {
            if let url = resolvedAvatarURL(creator.avatar) {
                FFRemoteImage(url: url) {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(FFColors.gray700)
            .overlay {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(FFColors.gray300)
            }
    }

    private func resolvedAvatarURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        if url.scheme != nil {
            return url
        }
        guard let baseURL = environment?.backendBaseURL else {
            return url
        }
        let normalizedPath = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        return baseURL.appendingPathComponent(normalizedPath)
    }
}

private struct AthleteProgramCatalogCard: View {
    let program: ProgramListItem
    let environment: AppEnvironment?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    if let imageURL = resolvedImageURL(from: program.cover?.url ?? program.media?.first?.url) {
                        FFRemoteImage(url: imageURL) {
                            placeholderImage
                        }
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                    } else {
                        placeholderImage
                    }

                    HStack(alignment: .top, spacing: FFSpacing.xs) {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text(program.title)
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)
                                .multilineTextAlignment(.leading)
                            Text(program.description?.trimmedNilIfEmpty ?? "Описание пока не добавлено.")
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                        }
                        Spacer(minLength: FFSpacing.sm)
                        VStack(alignment: .trailing, spacing: FFSpacing.xxs) {
                            FFBadge(status: .published)
                            if program.isFeatured ?? false {
                                Text("Рекомендуем")
                                    .font(FFTypography.caption.weight(.semibold))
                                    .foregroundStyle(FFColors.background)
                                    .padding(.horizontal, FFSpacing.xs)
                                    .padding(.vertical, FFSpacing.xxs)
                                    .background(FFColors.accent)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    if let influencerName = program.influencer?.displayName.trimmedNilIfEmpty {
                        Text("Атлет: \(influencerName)")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.gray300)
                    }

                    if let goals = program.goals?.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                       !goals.isEmpty
                    {
                        Text(goals.joined(separator: " • "))
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.accent)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: FFSpacing.xs) {
                        specTag(title: "Уровень", value: CatalogViewModel.localizedLevel(program.level ?? program.currentPublishedVersion?.level), icon: "chart.bar")
                        specTag(title: "Частота", value: frequencyTitle, icon: "calendar")
                        specTag(title: "Длительность", value: durationTitle, icon: "clock")
                        specTag(title: "Оборудование", value: equipmentTitle, icon: "dumbbell")
                    }

                    if let updatedAt = updatedLabel {
                        Text("Обновлено: \(updatedAt)")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }

    private var frequencyTitle: String {
        if let days = program.daysPerWeek ?? program.currentPublishedVersion?.frequencyPerWeek {
            return "\(days) дн/нед"
        }
        return "Частота не указана"
    }

    private var durationTitle: String {
        if let estimatedDuration = program.estimatedDurationMinutes {
            return "~\(estimatedDuration) мин"
        }
        return "Длительность не указана"
    }

    private var equipmentTitle: String {
        let equipment = (program.equipment ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if equipment.isEmpty {
            return "Оборудование не указано"
        }
        if equipment.count <= 2 {
            return equipment.joined(separator: ", ")
        }
        return "\(equipment.prefix(2).joined(separator: ", ")) +\(equipment.count - 2)"
    }

    private var updatedLabel: String? {
        let parsed = CatalogViewModel.parseISODate(program.updatedAt) ?? CatalogViewModel.parseISODate(program.createdAt)
        return parsed?.formatted(date: .abbreviated, time: .omitted)
    }

    private var placeholderImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .fill(FFColors.gray700)
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(FFColors.accent)
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
    }

    private func specTag(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            Label(title, systemImage: icon)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
            Text(value)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FFSpacing.sm)
        .padding(.vertical, FFSpacing.xs)
        .background(FFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .stroke(FFColors.gray700, lineWidth: 1)
        }
    }

    private func resolvedImageURL(from pathOrURL: String?) -> URL? {
        guard let pathOrURL, !pathOrURL.isEmpty else {
            return nil
        }

        if let direct = URL(string: pathOrURL), direct.scheme != nil {
            return direct
        }

        guard let baseURL = environment?.backendBaseURL else {
            return nil
        }

        let normalizedPath = pathOrURL.hasPrefix("/") ? String(pathOrURL.dropFirst()) : pathOrURL
        return baseURL.appendingPathComponent(normalizedPath)
    }
}

struct FollowButton: View {
    let state: FollowButtonState
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: FFSpacing.xxs) {
                if state == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(FFColors.background)
                }
                Text(title)
                    .font(FFTypography.caption.weight(.semibold))
            }
            .padding(.horizontal, FFSpacing.sm)
            .frame(minHeight: 36)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || state == .loading)
    }

    private var title: String {
        switch state {
        case .follow:
            "Подписаться"
        case .following:
            "Вы подписаны"
        case .loading:
            "Загрузка"
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .follow:
            FFColors.primary
        case .following:
            FFColors.surface
        case .loading:
            FFColors.gray700
        }
    }

    private var foregroundColor: Color {
        switch state {
        case .follow, .loading:
            FFColors.background
        case .following:
            FFColors.textPrimary
        }
    }

    private var borderColor: Color {
        switch state {
        case .follow, .loading:
            FFColors.primary
        case .following:
            FFColors.gray700
        }
    }
}

private extension CatalogViewModel {
    var programsClientForCreatorFlows: ProgramsClientProtocol? {
        programsClient
    }
}

private extension Optional where Wrapped == [SocialLink] {
    var orEmpty: [SocialLink] {
        self ?? []
    }
}

private func isCreatorFollowForbidden(_ apiError: APIError) -> Bool {
    if apiError == .forbidden {
        return true
    }
    if case let .httpError(statusCode, _) = apiError {
        return statusCode == 403
    }
    return false
}

private func isFollowFeatureNotSupported(_ apiError: APIError) -> Bool {
    if apiError == .invalidURL {
        return true
    }
    if case let .httpError(statusCode, _) = apiError {
        return [404, 405, 501].contains(statusCode)
    }
    return false
}

struct ProgramsCatalogScreen: View {
    @State var viewModel: ProgramsCatalogViewModel
    let environment: AppEnvironment
    let onProgramTap: (String) -> Void

    @State private var isSearchExpanded = false
    @State private var isFiltersPresented = false

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                if viewModel.isShowingCachedData {
                    cachedDataBadge
                }

                controlsRow

                if isSearchExpanded || !viewModel.query.isEmpty {
                    FFTextField(
                        label: "Поиск",
                        placeholder: "Название, цель или атлет",
                        text: Binding(
                            get: { viewModel.query },
                            set: { viewModel.searchQueryChanged($0) },
                        ),
                        helperText: nil,
                    )
                    .accessibilityLabel("Поиск программы по названию")
                }

                if let error = viewModel.error, hasAnyPrograms {
                    FFCard {
                        Text(error.message)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }

                if viewModel.isLoading, !hasAnyPrograms {
                    loadingSkeleton
                } else if let error = viewModel.error, !hasAnyPrograms {
                    FFErrorState(
                        title: error.title,
                        message: error.message,
                        retryTitle: "Повторить",
                        onRetry: { Task { await viewModel.retry() } },
                    )
                } else if !hasAnyPrograms {
                    EmptyStateView(
                        title: "Пока нет опубликованных программ",
                        message: "Программы появятся здесь после публикации.",
                    )
                } else {
                    content
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.top, FFSpacing.sm)
            .padding(.bottom, FFSpacing.lg)
        }
        .background(FFColors.background)
        .sheet(isPresented: $isFiltersPresented) {
            FiltersSheet(viewModel: viewModel)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.onAppear()
        }
    }

    private var hasAnyPrograms: Bool {
        !viewModel.programs.isEmpty || !viewModel.featuredPrograms.isEmpty
    }

    private var controlsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FFSpacing.xs) {
                catalogActionButton(
                    title: viewModel.query.isEmpty ? "Поиск" : "Поиск: \(viewModel.query)",
                    systemImage: "magnifyingglass",
                    isActive: isSearchExpanded || !viewModel.query.isEmpty,
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSearchExpanded.toggle()
                    }
                }

                catalogActionButton(
                    title: "Фильтры",
                    systemImage: "line.3.horizontal.decrease.circle",
                    isActive: viewModel.hasActiveFilters,
                ) {
                    isFiltersPresented = true
                }

                Menu {
                    ForEach(CatalogViewModel.SortOption.allCases) { option in
                        Button(option.title) {
                            viewModel.sortOption = option
                        }
                    }
                } label: {
                    chipLabel(
                        title: "Сортировка",
                        systemImage: "arrow.up.arrow.down",
                        isActive: true,
                    )
                }
            }
            .padding(.horizontal, FFSpacing.md)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: FFSpacing.md) {
            if !viewModel.featuredPrograms.isEmpty {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    Text("Подборка")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: FFSpacing.sm) {
                            ForEach(Array(viewModel.featuredPrograms.prefix(6))) { program in
                                ProgramCard(program: program, isCompact: true) {
                                    onProgramTap(program.id)
                                }
                                .frame(width: 280)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }
            }

            if viewModel.programs.isEmpty {
                EmptyStateView(
                    title: "Пока нет программ в основном каталоге",
                    message: "Попробуйте обновить экран позже.",
                )
            } else if viewModel.visiblePrograms.isEmpty {
                EmptyStateView(
                    title: "По выбранным фильтрам ничего не найдено",
                    message: "Сбросьте фильтры или измените запрос.",
                    actionTitle: "Сбросить фильтры",
                    action: { viewModel.resetFilters() },
                )
            } else {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    Text("Все программы")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)

                    LazyVStack(spacing: FFSpacing.sm) {
                        ForEach(viewModel.visiblePrograms) { program in
                            ProgramCard(program: program) {
                                onProgramTap(program.id)
                            }
                            .onAppear {
                                Task {
                                    await viewModel.loadNextPageIfNeeded(lastID: program.id)
                                }
                            }
                        }

                        if viewModel.isLoading {
                            FFLoadingState(title: "Загружаем ещё программы")
                        }
                    }
                }
            }
        }
    }

    private var cachedDataBadge: some View {
        FFCard {
            Text("Нет сети — показаны сохранённые данные")
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.primary)
        }
    }

    private var loadingSkeleton: some View {
        VStack(spacing: FFSpacing.sm) {
            FFLoadingState(title: "Загружаем каталог программ")
            FFLoadingState(title: "Подбираем лучшие варианты")
        }
    }

    private func catalogActionButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            chipLabel(title: title, systemImage: systemImage, isActive: isActive)
        }
        .buttonStyle(.plain)
    }

    private func chipLabel(title: String, systemImage: String, isActive: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(FFTypography.caption.weight(.semibold))
            .foregroundStyle(isActive ? FFColors.background : FFColors.textPrimary)
            .padding(.horizontal, FFSpacing.sm)
            .frame(minHeight: 40)
            .background(isActive ? FFColors.primary : FFColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                    .stroke(isActive ? FFColors.primary : FFColors.gray700, lineWidth: 1)
            }
            .lineLimit(1)
    }
}

struct FiltersSheet: View {
    @State var viewModel: ProgramsCatalogViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FFSpacing.sm) {
                    if !viewModel.availableGoals.isEmpty {
                        filterMenuRow(
                            title: "Цель",
                            value: viewModel.selectedGoal ?? "Все цели",
                        ) {
                            Button("Все цели") {
                                viewModel.selectedGoal = nil
                            }
                            ForEach(viewModel.availableGoals, id: \.self) { goal in
                                Button(goal) {
                                    viewModel.selectedGoal = goal
                                }
                            }
                        }
                    }

                    if !viewModel.availableLevels.isEmpty {
                        filterMenuRow(
                            title: "Уровень",
                            value: viewModel.selectedLevel ?? "Любой уровень",
                        ) {
                            Button("Любой уровень") {
                                viewModel.selectedLevel = nil
                            }
                            ForEach(viewModel.availableLevels, id: \.self) { level in
                                Button(level) {
                                    viewModel.selectedLevel = level
                                }
                            }
                        }
                    }

                    if !viewModel.availableDaysPerWeek.isEmpty {
                        filterMenuRow(
                            title: "Дней в неделю",
                            value: viewModel.selectedDaysPerWeek.map { "\($0)" } ?? "Любая частота",
                        ) {
                            Button("Любая частота") {
                                viewModel.selectedDaysPerWeek = nil
                            }
                            ForEach(viewModel.availableDaysPerWeek, id: \.self) { days in
                                Button("\(days) дн/нед") {
                                    viewModel.selectedDaysPerWeek = days
                                }
                            }
                        }
                    }

                    filterMenuRow(
                        title: "Длительность",
                        value: viewModel.selectedDuration.title,
                    ) {
                        ForEach(CatalogViewModel.DurationFilter.allCases) { duration in
                            Button(duration.title) {
                                viewModel.selectedDuration = duration
                            }
                        }
                    }

                    if !viewModel.availableEquipment.isEmpty {
                        filterMenuRow(
                            title: "Оборудование",
                            value: viewModel.selectedEquipment ?? "Любое оборудование",
                        ) {
                            Button("Любое оборудование") {
                                viewModel.selectedEquipment = nil
                            }
                            ForEach(viewModel.availableEquipment, id: \.self) { equipment in
                                Button(equipment) {
                                    viewModel.selectedEquipment = equipment
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.sm)
            }
            .background(FFColors.background)
            .navigationTitle("Фильтры")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сбросить") {
                        viewModel.resetFilters()
                    }
                    .disabled(!viewModel.hasActiveFilters)
                }
            }
        }
    }

    private func filterMenuRow(
        title: String,
        value: String,
        @ViewBuilder content: () -> some View,
    ) -> some View {
        FFCard {
            HStack(spacing: FFSpacing.sm) {
                Text(title)
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textPrimary)
                Spacer(minLength: FFSpacing.sm)
                Menu {
                    content()
                } label: {
                    HStack(spacing: FFSpacing.xxs) {
                        Text(value)
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FFColors.textSecondary)
                    }
                    .padding(.horizontal, FFSpacing.sm)
                    .frame(minHeight: 36)
                    .background(FFColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                            .stroke(FFColors.gray700, lineWidth: 1)
                    }
                }
            }
        }
    }
}

struct ProgramCard: View {
    let program: CatalogViewModel.ProgramCard
    var isCompact = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text(program.title)
                        .font(isCompact ? FFTypography.body.weight(.semibold) : FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(isCompact ? 2 : 3)

                    Text("Цель: \(goalTitle)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: FFSpacing.xs) {
                        statChip(title: "Уровень", value: program.levelTitle)
                        statChip(title: "Дней в неделю", value: daysTitle)
                        statChip(title: "Длительность", value: durationTitle)
                    }

                    if let influencerName = program.influencerName?.trimmedNilIfEmpty {
                        Text("Атлет: \(influencerName)")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("Открыть программу \(program.title)")
    }

    private var goalTitle: String {
        let goals = program.goals
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return goals.first ?? "Не указана"
    }

    private var daysTitle: String {
        if let days = program.daysPerWeek {
            return "\(days)"
        }
        return "—"
    }

    private var durationTitle: String {
        if let minutes = program.estimatedDurationMinutes {
            return "~\(minutes) мин"
        }
        return "—"
    }

    private func statChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
            Text(value)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, FFSpacing.xs)
        .padding(.vertical, FFSpacing.xxs)
        .background(FFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .stroke(FFColors.gray700, lineWidth: 1)
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: FFSpacing.sm) {
            FFEmptyState(title: title, message: message)

            if let actionTitle, let action {
                FFButton(title: actionTitle, variant: .secondary, action: action)
            }
        }
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview("Каталог") {
    NavigationStack {
        ProgramsCatalogScreen(
            viewModel: CatalogViewModel(
                userSub: "preview",
                programsClient: CatalogPreviewProgramsClient(),
            ),
            environment: PreviewMocks.environment,
            onProgramTap: { _ in },
        )
        .navigationTitle("Каталог")
    }
}

private actor CatalogPreviewProgramsClient: ProgramsClientProtocol {
    func listPublishedPrograms(
        query _: String,
        page _: Int,
        size _: Int,
    ) async -> Result<PagedProgramResponse, APIError> {
        .success(PreviewMocks.sampleProgramsPage)
    }

    func listFeaturedPrograms(page _: Int, size _: Int) async -> Result<PagedProgramResponse, APIError> {
        .success(PreviewMocks.sampleProgramsPage)
    }

    func getProgramDetails(programId _: String) async -> Result<ProgramDetails, APIError> {
        .success(PreviewMocks.sampleProgramDetails)
    }

    func startProgram(programVersionId _: String) async -> Result<ProgramEnrollment, APIError> {
        .failure(.unknown)
    }
}
