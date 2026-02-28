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

extension UserFacingError {
    init(kind: UserFacingErrorKind, title: String, message: String) {
        self.kind = kind
        self.title = title
        self.message = message
    }
}

extension APIError {
    func userFacing(context: UserFacingErrorContext) -> UserFacingError {
        switch self {
        case .offline:
            return UserFacingError(
                kind: .offline,
                title: "Нет подключения к интернету",
                message: "Проверьте сеть и попробуйте снова.",
            )
        case .unauthorized:
            return UserFacingError(
                kind: .unauthorized,
                title: "Сессия истекла",
                message: "Войдите снова, чтобы продолжить.",
            )
        case .forbidden:
            return UserFacingError(
                kind: .forbidden,
                title: "Доступ запрещён",
                message: forbiddenMessage(for: context),
            )
        case .serverError, .timeout, .transportError:
            return UserFacingError(
                kind: .server,
                title: "Сервис временно недоступен",
                message: serverMessage(for: context),
            )
        case .decodingError:
            return UserFacingError(
                kind: .decoding,
                title: "Ошибка данных",
                message: "Не удалось обработать ответ сервера",
            )
        default:
            return UserFacingError(
                kind: .unknown,
                title: "Что-то пошло не так",
                message: unknownMessage(for: context),
            )
        }
    }

    private func forbiddenMessage(for context: UserFacingErrorContext) -> String {
        switch context {
        case .catalog:
            return "У вас нет прав для просмотра каталога."
        case .programDetails:
            return "Недостаточно прав для просмотра программы."
        case .workoutsList, .workoutPlayer:
            return "Недостаточно прав для просмотра тренировок."
        }
    }

    private func serverMessage(for context: UserFacingErrorContext) -> String {
        switch context {
        case .catalog:
            return "Не удалось загрузить каталог. Попробуйте позже."
        case .programDetails:
            return "Не удалось загрузить программу. Попробуйте позже."
        case .workoutsList:
            return "Не удалось загрузить список тренировок. Попробуйте позже."
        case .workoutPlayer:
            return "Не удалось загрузить тренировку. Попробуйте позже."
        }
    }

    private func unknownMessage(for context: UserFacingErrorContext) -> String {
        switch context {
        case .catalog:
            return "Не удалось загрузить каталог."
        case .programDetails:
            return "Не удалось загрузить программу."
        case .workoutsList:
            return "Не удалось загрузить тренировки."
        case .workoutPlayer:
            return "Не удалось открыть тренировку."
        }
    }
}
