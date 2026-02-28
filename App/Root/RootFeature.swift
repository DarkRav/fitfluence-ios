import ComposableArchitecture

@Reducer
struct RootFeature {
    struct State: Equatable {}

    enum Action: Equatable {}

    var body: some ReducerOf<Self> {
        Reduce { _, _ in
            .none
        }
    }
}
