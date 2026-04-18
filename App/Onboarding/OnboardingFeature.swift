import ComposableArchitecture

@Reducer
struct OnboardingFeature {
    @ObservableState
    struct State: Equatable {
        let context: OnboardingContext
        var athleteDisplayName: String
        var isSubmitting = false
        var errorMessage: String?
        var successMessage: String?

        init(context: OnboardingContext) {
            self.context = context
            athleteDisplayName = ""
        }
    }

    enum Action: Equatable {
        case athleteDisplayNameChanged(String)
        case createAthleteTapped(String)
        case athleteResponse(Result<CreateAthleteProfileResponse, APIError>)
        case postSubmitStateResolved(RootSessionState)
        case clearMessage
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case sessionResolved(RootSessionState)
    }

    private let athleteClient: AthleteProfileClientProtocol?
    private let sessionManager: SessionManaging

    init(
        athleteClient: AthleteProfileClientProtocol?,
        sessionManager: SessionManaging,
    ) {
        self.athleteClient = athleteClient
        self.sessionManager = sessionManager
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .athleteDisplayNameChanged(value):
                state.athleteDisplayName = value
                return .none

            case let .createAthleteTapped(displayName):
                state.athleteDisplayName = displayName
                guard !state.athleteDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    state.errorMessage = "Укажите имя профиля."
                    return .none
                }

                guard let athleteClient else {
                    state.errorMessage = "Сервис профиля временно недоступен."
                    return .none
                }

                state.isSubmitting = true
                state.errorMessage = nil

                let request = CreateAthleteProfileRequest(
                    displayName: state.athleteDisplayName,
                    primaryGoal: "",
                )

                return .run { send in
                    let result = await athleteClient.createProfile(request)
                    await send(.athleteResponse(result))
                }

            case let .athleteResponse(result):
                state.isSubmitting = false
                switch result {
                case .success:
                    state.successMessage = "Профиль создан."
                    return .run { [sessionManager] send in
                        let nextState = await sessionManager.postLoginBootstrap()
                        await send(.postSubmitStateResolved(nextState))
                    }

                case let .failure(error):
                    if error.isConflict {
                        state.successMessage = "Профиль уже создан."
                        return .run { [sessionManager] send in
                            let nextState = await sessionManager.postLoginBootstrap()
                            await send(.postSubmitStateResolved(nextState))
                        }
                    }
                    state.errorMessage = error.userFacing(context: .workoutsList).message
                    return .none
                }

            case let .postSubmitStateResolved(nextState):
                state.successMessage = nil
                return .send(.delegate(.sessionResolved(nextState)))

            case .clearMessage:
                state.errorMessage = nil
                state.successMessage = nil
                return .none

            case .delegate:
                return .none
            }
        }
    }
}

private extension APIError {
    var isConflict: Bool {
        if case let .httpError(statusCode, _) = self {
            return statusCode == 409
        }
        return false
    }
}
