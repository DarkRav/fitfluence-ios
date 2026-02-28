import ComposableArchitecture

@Reducer
struct RootFeature {
    @ObservableState
    struct State: Equatable {
        var selectedTab: Tab = .catalog
    }

    enum Tab: Hashable {
        case catalog
        case workouts
        case profile
    }

    enum Action: Equatable {
        case tabSelected(Tab)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .tabSelected(let tab):
                state.selectedTab = tab
                return .none
            }
        }
    }
}
