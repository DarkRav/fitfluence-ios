import Foundation

enum UserFacingErrorKind: Equatable, Sendable {
    case offline
    case unauthorized
    case forbidden
    case server
    case decoding
    case unknown
}

enum UserFacingErrorContext {
    case catalog
    case programDetails
    case workoutsList
    case workoutPlayer
}

extension APIError {
    func userFacing(context: UserFacingErrorContext) -> UserFacingError {
        switch self {
        case .offline:
            UserFacingError(
                kind: .offline,
                title: "Нет подключения к интернету",
                message: "Проверьте сеть и попробуйте снова.",
            )
        case .unauthorized:
            UserFacingError(
                kind: .unauthorized,
                title: "Сессия истекла",
                message: "Войдите снова, чтобы продолжить.",
            )
        case .forbidden:
            UserFacingError(
                kind: .forbidden,
                title: "Доступ запрещён",
                message: forbiddenMessage(for: context),
            )
        case .serverError, .timeout, .transportError:
            UserFacingError(
                kind: .server,
                title: "Сервис временно недоступен",
                message: "Попробуйте ещё раз чуть позже.",
            )
        case .decodingError:
            UserFacingError(
                kind: .decoding,
                title: "Ошибка данных",
                message: "Не удалось обработать ответ сервера",
            )
        default:
            UserFacingError(
                kind: .unknown,
                title: "Что-то пошло не так",
                message: "Не удалось завершить запрос. Попробуйте ещё раз.",
            )
        }
    }

    private func forbiddenMessage(for context: UserFacingErrorContext) -> String {
        switch context {
        case .catalog:
            "У вас нет прав для просмотра каталога."
        case .programDetails:
            "Недостаточно прав для просмотра программы."
        case .workoutsList, .workoutPlayer:
            "Недостаточно прав для просмотра тренировок."
        }
    }
}
