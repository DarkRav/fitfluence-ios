import ComposableArchitecture
import Foundation

@Reducer
struct ProgramDetailsFeature {
    @ObservableState
    struct State: Equatable {
        let programId: String
        var details: ProgramDetails?
        var isLoading = false
        var isStartingProgram = false
        var error: UserFacingError?
        var successMessage: String?
    }

    enum Action: Equatable {
        case onAppear
        case retry
        case detailsResponse(Result<ProgramDetails, APIError>)
        case startProgramTapped
        case startProgramResponse(Result<ProgramEnrollment, APIError>)
    }

    private let programsClient: ProgramsClientProtocol?

    init(programsClient: ProgramsClientProtocol?) {
        self.programsClient = programsClient
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.details == nil else { return .none }
                state.isLoading = true
                state.error = nil
                return loadDetails(programId: state.programId)

            case .retry:
                state.isLoading = true
                state.error = nil
                return loadDetails(programId: state.programId)

            case let .detailsResponse(result):
                state.isLoading = false
                switch result {
                case let .success(details):
                    state.details = details
                    state.error = nil
                case let .failure(apiError):
                    state.error = apiError.userFacingError
                }
                return .none

            case .startProgramTapped:
                guard
                    let versionID = state.details?.currentPublishedVersion?.id,
                    !state.isStartingProgram
                else {
                    return .none
                }

                state.isStartingProgram = true
                state.error = nil
                return .run { [programsClient] send in
                    let result: Result<ProgramEnrollment, APIError> = if let programsClient {
                        await programsClient.startProgram(programVersionId: versionID)
                    } else {
                        .failure(.invalidURL)
                    }
                    await send(.startProgramResponse(result))
                }

            case let .startProgramResponse(result):
                state.isStartingProgram = false
                switch result {
                case .success:
                    state.successMessage = "Программа успешно начата."
                case let .failure(apiError):
                    state.error = apiError.userFacingError
                }
                return .none
            }
        }
    }

    private func loadDetails(programId: String) -> Effect<Action> {
        .run { [programsClient] send in
            let result: Result<ProgramDetails, APIError> = if let programsClient {
                await programsClient.getProgramDetails(programId: programId)
            } else {
                .failure(.invalidURL)
            }
            await send(.detailsResponse(result))
        }
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
                message: "Недостаточно прав для просмотра программы.",
            )
        case .serverError:
            UserFacingError(
                title: "Сервис временно недоступен",
                message: "Попробуйте открыть программу чуть позже.",
            )
        case .decodingError:
            UserFacingError(
                title: "Ошибка данных",
                message: "Не удалось обработать ответ сервера.",
            )
        default:
            UserFacingError(
                title: "Не удалось загрузить программу",
                message: "Попробуйте ещё раз через несколько секунд.",
            )
        }
    }
}
