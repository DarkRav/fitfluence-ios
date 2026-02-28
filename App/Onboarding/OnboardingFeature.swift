import ComposableArchitecture

@Reducer
struct OnboardingFeature {
    @ObservableState
    struct State: Equatable {
        var context: OnboardingContext
        var step: Step
        var athleteDisplayName = ""
        var athleteGoal = ""
        var influencerDisplayName = ""
        var influencerBio = ""
        var isSubmitting = false
        var errorMessage: String?
        var successMessage: String?

        init(context: OnboardingContext) {
            self.context = context
            step = Step.initial(for: context.requiredProfiles)
        }
    }

    enum Step: Equatable {
        case choice
        case athleteForm
        case influencerForm
        case influencerNotSupported

        static func initial(for required: RequiredProfiles) -> Step {
            switch (required.requiresAthleteProfile, required.requiresInfluencerProfile) {
            case (true, true):
                .choice
            case (true, false):
                .athleteForm
            case (false, true):
                .influencerForm
            case (false, false):
                .choice
            }
        }
    }

    enum Action: Equatable {
        case chooseAthleteTapped
        case chooseInfluencerTapped
        case backToChoiceTapped

        case athleteDisplayNameChanged(String)
        case athleteGoalChanged(String)
        case createAthleteTapped
        case athleteResponse(Result<CreateAthleteProfileResponse, APIError>)

        case influencerDisplayNameChanged(String)
        case influencerBioChanged(String)
        case createInfluencerTapped
        case influencerResponse(Result<CreateInfluencerProfileResponse, APIError>)

        case postSubmitStateResolved(RootSessionState)
        case clearMessage

        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case sessionResolved(RootSessionState)
    }

    private let athleteClient: AthleteProfileClientProtocol?
    private let influencerClient: InfluencerProfileClientProtocol?
    private let sessionManager: SessionManaging

    init(
        athleteClient: AthleteProfileClientProtocol?,
        influencerClient: InfluencerProfileClientProtocol?,
        sessionManager: SessionManaging,
    ) {
        self.athleteClient = athleteClient
        self.influencerClient = influencerClient
        self.sessionManager = sessionManager
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .chooseAthleteTapped:
                state.step = .athleteForm
                state.errorMessage = nil
                return .none

            case .chooseInfluencerTapped:
                state.step = .influencerForm
                state.errorMessage = nil
                return .none

            case .backToChoiceTapped:
                state.step = .choice
                state.errorMessage = nil
                return .none

            case let .athleteDisplayNameChanged(value):
                state.athleteDisplayName = value
                return .none

            case let .athleteGoalChanged(value):
                state.athleteGoal = value
                return .none

            case .createAthleteTapped:
                guard !state.athleteDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    state.errorMessage = "Укажите имя профиля атлета."
                    return .none
                }

                guard let athleteClient else {
                    state.errorMessage = "Эндпоинт профиля атлета недоступен."
                    return .none
                }

                state.isSubmitting = true
                state.errorMessage = nil

                let request = CreateAthleteProfileRequest(
                    displayName: state.athleteDisplayName,
                    primaryGoal: state.athleteGoal.trimmingCharacters(in: .whitespacesAndNewlines),
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
                    state.errorMessage = error.userMessage
                    return .none
                }

            case let .influencerDisplayNameChanged(value):
                state.influencerDisplayName = value
                return .none

            case let .influencerBioChanged(value):
                state.influencerBio = value
                return .none

            case .createInfluencerTapped:
                guard !state.influencerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    state.errorMessage = "Укажите имя профиля инфлюэнсера."
                    return .none
                }

                guard let influencerClient else {
                    state.step = .influencerNotSupported
                    return .none
                }

                state.isSubmitting = true
                state.errorMessage = nil

                let request = CreateInfluencerProfileRequest(
                    displayName: state.influencerDisplayName,
                    bio: state.influencerBio.trimmingCharacters(in: .whitespacesAndNewlines),
                )

                return .run { send in
                    let result = await influencerClient.createProfile(request)
                    await send(.influencerResponse(result))
                }

            case let .influencerResponse(result):
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
                    if case let .httpError(statusCode, _) = error, statusCode == 404 {
                        state.step = .influencerNotSupported
                    } else {
                        state.errorMessage = error.userMessage
                    }
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

    var userMessage: String {
        switch self {
        case .offline:
            "Нет подключения к интернету"
        case .timeout, .transportError, .httpError:
            "Сервер недоступен"
        case .unauthorized:
            "Требуется авторизация"
        case .forbidden:
            "Доступ запрещён"
        case .serverError:
            "Ошибка сервера"
        case .decodingError:
            "Не удалось обработать ответ"
        case .cancelled, .invalidURL, .unknown:
            "Неизвестная ошибка"
        }
    }
}
