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
        if let date = iso8601WithFractions.date(from: value) {
            return date
        }
        return iso8601.date(from: value)
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

    private nonisolated static let iso8601WithFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct CatalogScreen: View {
    @State var viewModel: CatalogViewModel
    let environment: AppEnvironment
    let onProgramTap: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                if viewModel.isShowingCachedData {
                    cachedDataBadge
                }

                scopeSelector

                FFTextField(
                    label: "Поиск",
                    placeholder: "Название, цель или автор",
                    text: Binding(
                        get: { viewModel.query },
                        set: { viewModel.searchQueryChanged($0) },
                    ),
                    helperText: "Поиск работает по опубликованным программам",
                )
                .accessibilityLabel("Поиск программы по названию")

                controlsBar
                filtersBar

                if viewModel.isLoading, viewModel.activePrograms.isEmpty {
                    loadingSkeleton
                } else if let error = viewModel.error {
                    FFErrorState(
                        title: error.title,
                        message: error.message,
                        retryTitle: "Повторить",
                        onRetry: { Task { await viewModel.retry() } },
                    )
                } else if viewModel.activePrograms.isEmpty {
                    FFEmptyState(
                        title: "Пока нет опубликованных программ",
                        message: "Попробуйте изменить запрос или обновить экран позже.",
                    )
                } else if viewModel.visiblePrograms.isEmpty {
                    FFEmptyState(
                        title: "По выбранным фильтрам ничего не найдено",
                        message: "Сбросьте фильтры или измените поиск.",
                    )
                    FFButton(title: "Сбросить фильтры", variant: .secondary) {
                        viewModel.resetFilters()
                    }
                } else {
                    LazyVStack(spacing: FFSpacing.sm) {
                        ForEach(viewModel.visiblePrograms) { program in
                            programCard(program: program) {
                                onProgramTap(program.id)
                            }
                            .onAppear {
                                Task { await viewModel.loadNextPageIfNeeded(lastID: program.id) }
                            }
                        }

                        if viewModel.isLoading {
                            FFLoadingState(title: "Загружаем ещё программы")
                        }
                    }
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.top, FFSpacing.md)
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
            Text("Оффлайн. Показаны сохранённые данные.")
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.primary)
        }
    }

    private var scopeSelector: some View {
        HStack(spacing: FFSpacing.xs) {
            ForEach(CatalogViewModel.Scope.allCases) { scope in
                Button {
                    Task {
                        await viewModel.selectScope(scope)
                    }
                } label: {
                    Text(scope.title)
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(viewModel.scope == scope ? FFColors.background : FFColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(viewModel.scope == scope ? FFColors.primary : FFColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                                .stroke(viewModel.scope == scope ? FFColors.primary : FFColors.gray700, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var controlsBar: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack {
                    Text("Найдено \(viewModel.visiblePrograms.count) из \(viewModel.activePrograms.count)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                    Spacer()
                    sortMenu
                }
                if viewModel.hasActiveFilters {
                    FFButton(title: "Сбросить фильтры", variant: .secondary) {
                        viewModel.resetFilters()
                    }
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(CatalogViewModel.SortOption.allCases) { option in
                Button(option.title) {
                    viewModel.sortOption = option
                }
            }
        } label: {
            menuChip(title: "Сортировка", value: viewModel.sortOption.title)
        }
    }

    @ViewBuilder
    private var filtersBar: some View {
        if !viewModel.availableGoals.isEmpty
            || !viewModel.availableLevels.isEmpty
            || !viewModel.availableEquipment.isEmpty
            || !viewModel.availableDaysPerWeek.isEmpty
        {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FFSpacing.xs) {
                    if !viewModel.availableGoals.isEmpty {
                        Menu {
                            Button("Все цели") { viewModel.selectedGoal = nil }
                            ForEach(viewModel.availableGoals, id: \.self) { goal in
                                Button(goal) { viewModel.selectedGoal = goal }
                            }
                        } label: {
                            menuChip(title: "Цель", value: viewModel.selectedGoal ?? "Все")
                        }
                    }

                    if !viewModel.availableLevels.isEmpty {
                        Menu {
                            Button("Любой уровень") { viewModel.selectedLevel = nil }
                            ForEach(viewModel.availableLevels, id: \.self) { level in
                                Button(level) { viewModel.selectedLevel = level }
                            }
                        } label: {
                            menuChip(title: "Уровень", value: viewModel.selectedLevel ?? "Все")
                        }
                    }

                    if !viewModel.availableDaysPerWeek.isEmpty {
                        Menu {
                            Button("Любая частота") { viewModel.selectedDaysPerWeek = nil }
                            ForEach(viewModel.availableDaysPerWeek, id: \.self) { days in
                                Button("\(days) дн/нед") { viewModel.selectedDaysPerWeek = days }
                            }
                        } label: {
                            menuChip(
                                title: "Дней в неделю",
                                value: viewModel.selectedDaysPerWeek.map { "\($0)" } ?? "Все",
                            )
                        }
                    }

                    Menu {
                        ForEach(CatalogViewModel.DurationFilter.allCases) { duration in
                            Button(duration.title) {
                                viewModel.selectedDuration = duration
                            }
                        }
                    } label: {
                        menuChip(title: "Длительность", value: viewModel.selectedDuration.title)
                    }

                    if !viewModel.availableEquipment.isEmpty {
                        Menu {
                            Button("Любое оборудование") { viewModel.selectedEquipment = nil }
                            ForEach(viewModel.availableEquipment, id: \.self) { equipment in
                                Button(equipment) { viewModel.selectedEquipment = equipment }
                            }
                        } label: {
                            menuChip(title: "Оборудование", value: viewModel.selectedEquipment ?? "Все")
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func menuChip(title: String, value: String) -> some View {
        HStack(spacing: FFSpacing.xxs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
            Text(value)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FFColors.textSecondary)
        }
        .padding(.horizontal, FFSpacing.sm)
        .frame(minHeight: 44)
        .background(FFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .stroke(FFColors.gray700, lineWidth: 1)
        }
    }

    private var loadingSkeleton: some View {
        VStack(spacing: FFSpacing.sm) {
            FFLoadingState(title: "Загружаем программы")
            FFLoadingState(title: "Подбираем лучшие варианты")
        }
    }

    private func programCard(program: CatalogViewModel.ProgramCard, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    if let imageURL = resolvedImageURL(from: program.coverURL) {
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
                            Text(program.description)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                        }
                        Spacer(minLength: FFSpacing.sm)
                        VStack(alignment: .trailing, spacing: FFSpacing.xxs) {
                            FFBadge(status: .published)
                            if program.isFeatured {
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

                    if let influencerName = program.influencerName {
                        Text("Автор: \(influencerName)")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.gray300)
                    }

                    if !program.goals.isEmpty {
                        Text(program.goals.joined(separator: " • "))
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.accent)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: FFSpacing.xs) {
                        specTag(title: "Уровень", value: program.levelTitle, icon: "chart.bar")
                        specTag(title: "Частота", value: program.frequencyTitle, icon: "calendar")
                        specTag(title: "Длительность", value: program.durationTitle, icon: "clock")
                        specTag(title: "Оборудование", value: program.equipmentTitle, icon: "dumbbell")
                    }

                    if let updatedAt = program.updatedLabel {
                        Text("Обновлено: \(updatedAt)")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("Открыть программу \(program.title)")
        .accessibilityHint("Откроет детальную страницу программы")
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

        guard let baseURL = environment.backendBaseURL else {
            return nil
        }

        let normalizedPath = pathOrURL.hasPrefix("/") ? String(pathOrURL.dropFirst()) : pathOrURL
        return baseURL.appendingPathComponent(normalizedPath)
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
        CatalogScreen(
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
