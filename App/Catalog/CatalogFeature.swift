import ComposableArchitecture
import Foundation

@Reducer
struct CatalogFeature {
    @ObservableState
    struct State: Equatable {
        var query = ""
        var programs: [ProgramCard] = []
        var isLoading = false
        var isRefreshing = false
        var error: UserFacingError?
        var currentPage = 0
        var totalPages = 0
    }

    struct ProgramCard: Equatable, Identifiable {
        let id: String
        let title: String
        let description: String
        let influencerName: String?
        let goals: [String]
        let coverURL: String?
        let isPublished: Bool
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case onAppear
        case refresh
        case searchQueryChanged(String)
        case searchSubmit
        case loadNextPage
        case retry
        case programTapped(String)
        case programsResponse(Result<PagedProgramResponse, APIError>, append: Bool)
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case openProgram(String)
    }

    private enum CancelID {
        case searchDebounce
        case loadPrograms
    }

    private let programsClient: ProgramsClientProtocol?

    init(programsClient: ProgramsClientProtocol?) {
        self.programsClient = programsClient
    }

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear:
                guard state.programs.isEmpty else { return .none }
                state.isLoading = true
                state.error = nil
                state.currentPage = 0
                return loadProgramsEffect(query: state.query, page: 0, append: false)

            case .refresh:
                state.isRefreshing = true
                state.error = nil
                state.currentPage = 0
                return loadProgramsEffect(query: state.query, page: 0, append: false)

            case let .searchQueryChanged(value):
                state.query = value
                state.error = nil
                return .run { send in
                    try await Task.sleep(for: .milliseconds(400))
                    await send(.searchSubmit)
                }
                .cancellable(id: CancelID.searchDebounce, cancelInFlight: true)

            case .searchSubmit:
                state.isLoading = true
                state.error = nil
                state.currentPage = 0
                return loadProgramsEffect(query: state.query, page: 0, append: false)

            case .loadNextPage:
                guard !state.isLoading else { return .none }
                guard state.totalPages > 0 else { return .none }
                let nextPage = state.currentPage + 1
                guard nextPage < state.totalPages else { return .none }

                state.isLoading = true
                return loadProgramsEffect(query: state.query, page: nextPage, append: true)

            case .retry:
                state.isLoading = true
                state.error = nil
                return loadProgramsEffect(query: state.query, page: state.currentPage, append: false)

            case let .programTapped(programID):
                return .send(.delegate(.openProgram(programID)))

            case let .programsResponse(result, append):
                state.isLoading = false
                state.isRefreshing = false

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
                        state.programs.append(contentsOf: cards)
                    } else {
                        state.programs = cards
                    }
                    state.currentPage = response.metadata.page
                    state.totalPages = response.metadata.totalPages
                    state.error = nil

                case let .failure(apiError):
                    state.error = apiError.userFacingError
                    if !append {
                        state.programs = []
                    }
                }

                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func loadProgramsEffect(query: String, page: Int, append: Bool) -> Effect<Action> {
        .run { [programsClient] send in
            let result: Result<PagedProgramResponse, APIError> = if let programsClient {
                await programsClient.listPublishedPrograms(query: query, page: page, size: 20)
            } else {
                .failure(.invalidURL)
            }
            await send(.programsResponse(result, append: append))
        }
        .cancellable(id: CancelID.loadPrograms, cancelInFlight: true)
    }
}

private extension APIError {
    var userFacingError: UserFacingError {
        switch self {
        case .offline:
            UserFacingError(
                title: "Нет подключения к интернету",
                message: "Проверьте сеть и попробуйте снова.",
            )
        case .unauthorized:
            UserFacingError(
                title: "Сессия истекла",
                message: "Войдите снова, чтобы продолжить.",
            )
        case .forbidden:
            UserFacingError(
                title: "Доступ запрещён",
                message: "У вас нет прав для просмотра каталога.",
            )
        case .serverError:
            UserFacingError(
                title: "Сервис временно недоступен",
                message: "Попробуйте открыть каталог чуть позже.",
            )
        case .decodingError:
            UserFacingError(
                title: "Ошибка данных",
                message: "Не удалось обработать ответ сервера.",
            )
        default:
            UserFacingError(
                title: "Не удалось загрузить каталог",
                message: "Попробуйте ещё раз через несколько секунд.",
            )
        }
    }
}
