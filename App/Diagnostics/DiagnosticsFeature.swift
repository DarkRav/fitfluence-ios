import ComposableArchitecture

@Reducer
struct DiagnosticsFeature {
    @ObservableState
    struct State: Equatable {
        var phase: Phase = .idle
    }

    enum Phase: Equatable {
        case idle
        case loading
        case success(HealthResponse)
        case failure(APIError)
    }

    enum Action: Equatable {
        case checkConnectionTapped
        case healthResponse(Result<HealthResponse, APIError>)
    }

    private let apiClient: APIClientProtocol?

    init(apiClient: APIClientProtocol?) {
        self.apiClient = apiClient
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .checkConnectionTapped:
                state.phase = .loading
                return .run { [apiClient] send in
                    let result: Result<HealthResponse, APIError> = if let apiClient {
                        await apiClient.healthCheck()
                    } else {
                        .failure(.invalidURL)
                    }

                    await send(.healthResponse(result))
                }

            case let .healthResponse(result):
                switch result {
                case let .success(response):
                    state.phase = .success(response)
                case let .failure(error):
                    state.phase = .failure(error)
                }
                return .none
            }
        }
    }
}
