import ComposableArchitecture

@Reducer
struct RootFeature {
    private let apiClient: APIClientProtocol?

    init(apiClient: APIClientProtocol? = nil) {
        self.apiClient = apiClient
    }

    @ObservableState
    struct State: Equatable {
        var selectedTab: Tab = .catalog
        var diagnostics = DiagnosticsFeature.State()
    }

    enum Tab: Hashable {
        case catalog
        case workouts
        case profile
#if DEBUG
        case diagnostics
#endif
    }

    enum Action: Equatable {
        case tabSelected(Tab)
        case diagnostics(DiagnosticsFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.diagnostics, action: \.diagnostics) {
            DiagnosticsFeature(apiClient: apiClient)
        }

        Reduce { state, action in
            switch action {
            case let .tabSelected(tab):
                state.selectedTab = tab
                return .none
            case .diagnostics:
                return .none
            }
        }
    }
}
