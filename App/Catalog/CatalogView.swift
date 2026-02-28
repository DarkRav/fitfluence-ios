import Observation
import SwiftUI

@Observable
@MainActor
final class CatalogViewModel {
    struct ProgramCard: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let description: String
        let influencerName: String?
        let goals: [String]
        let coverURL: String?
        let isPublished: Bool
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

    var query = ""
    var programs: [ProgramCard] = []
    var isLoading = false
    var isRefreshing = false
    var isShowingCachedData = false
    var error: UserFacingError?
    var currentPage = 0
    var totalPages = 0

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
        guard programs.isEmpty else { return }
        isLoading = true
        error = nil
        currentPage = 0
        await loadPage(page: 0, append: false)
    }

    func refresh() async {
        isRefreshing = true
        error = nil
        currentPage = 0
        await loadPage(page: 0, append: false)
        isRefreshing = false
    }

    func retry() async {
        isLoading = true
        error = nil
        await loadPage(page: currentPage, append: false)
    }

    func searchQueryChanged(_ value: String) {
        query = value
        error = nil

        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self.searchSubmit()
        }
    }

    func searchSubmit() async {
        isLoading = true
        error = nil
        currentPage = 0
        await loadPage(page: 0, append: false)
    }

    func loadNextPageIfNeeded(lastID: String?) async {
        guard !isLoading else { return }
        guard totalPages > 0 else { return }
        guard let lastID, lastID == programs.last?.id else { return }
        let nextPage = currentPage + 1
        guard nextPage < totalPages else { return }

        isLoading = true
        await loadPage(page: nextPage, append: true)
    }

    private func loadPage(page: Int, append: Bool) async {
        defer {
            isLoading = false
        }

        let key = cacheKey(query: query, page: page)
        if let cached = await cacheStore.get(key, as: CachedCatalogPage.self, namespace: userSub) {
            if append {
                programs.append(contentsOf: cached.cards)
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
            let cards = response.content.map {
                ProgramCard(
                    id: $0.id,
                    title: $0.title,
                    description: $0.description ?? "Описание пока не добавлено.",
                    influencerName: $0.influencer?.displayName,
                    goals: $0.goals ?? [],
                    coverURL: $0.cover?.url ?? $0.media?.first?.url,
                    isPublished: $0.status == .published,
                )
            }

            if append {
                programs.append(contentsOf: cards)
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

    private func cacheKey(query: String, page: Int) -> String {
        "programs.list?q=\(query)&page=\(page)"
    }
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

                FFTextField(
                    label: "Поиск",
                    placeholder: "Название программы",
                    text: Binding(
                        get: { viewModel.query },
                        set: { viewModel.searchQueryChanged($0) },
                    ),
                    helperText: "Введите название программы",
                )
                .accessibilityLabel("Поиск программы по названию")

                if viewModel.isLoading, viewModel.programs.isEmpty {
                    loadingSkeleton
                } else if let error = viewModel.error {
                    FFErrorState(
                        title: error.title,
                        message: error.message,
                        retryTitle: "Повторить",
                        onRetry: { Task { await viewModel.retry() } },
                    )
                } else if viewModel.programs.isEmpty {
                    FFEmptyState(
                        title: "Пока нет опубликованных программ",
                        message: "Попробуйте изменить запрос или обновить экран позже.",
                    )
                } else {
                    LazyVStack(spacing: FFSpacing.sm) {
                        ForEach(viewModel.programs) { program in
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
                        if program.isPublished {
                            FFBadge(status: .published)
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
