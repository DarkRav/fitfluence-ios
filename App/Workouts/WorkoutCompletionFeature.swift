import ComposableArchitecture

@Reducer
struct WorkoutCompletionFeature {
    @ObservableState
    struct State: Equatable {
        let summary: WorkoutPlayerFeature.CompletionSummary
    }

    enum Action: Equatable {
        case doneTapped
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case close
    }

    var body: some ReducerOf<Self> {
        Reduce { _, action in
            switch action {
            case .doneTapped:
                .send(.delegate(.close))
            case .delegate:
                .none
            }
        }
    }
}
