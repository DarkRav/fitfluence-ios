import Foundation

enum RootSessionState: Equatable, Sendable {
    case unauthenticated
    case authenticating
    case needsOnboarding(OnboardingContext)
    case authenticated(UserContext)
    case error(UserFacingError)
}

struct UserFacingError: Equatable, Sendable {
    var kind: UserFacingErrorKind = .unknown
    let title: String
    let message: String

    init(kind: UserFacingErrorKind = .unknown, title: String, message: String) {
        self.kind = kind
        self.title = title
        self.message = message
    }
}

protocol SessionManaging: Sendable {
    func bootstrap() async -> RootSessionState
    func postLoginBootstrap() async -> RootSessionState
    func logout() async -> RootSessionState
}

final class SessionManager: SessionManaging, @unchecked Sendable {
    private let authService: AuthServiceProtocol
    private let meClient: MeClientProtocol

    init(authService: AuthServiceProtocol, meClient: MeClientProtocol) {
        self.authService = authService
        self.meClient = meClient
    }

    func bootstrap() async -> RootSessionState {
        guard await authService.currentTokenSet() != nil else {
            return .unauthenticated
        }

        guard await authService.validateExternalCredentialIfNeeded() else {
            return .unauthenticated
        }

        guard await authService.refreshIfNeeded() else {
            await authService.logout()
            return .unauthenticated
        }

        return await resolveMeState()
    }

    func postLoginBootstrap() async -> RootSessionState {
        await resolveMeState()
    }

    func logout() async -> RootSessionState {
        await authService.logout()
        return .unauthenticated
    }

    private func resolveMeState() async -> RootSessionState {
        let meResult = await meClient.me()

        switch meResult {
        case let .success(me):
            let requiredProfiles = me.requiredProfilesForSession

            if requiredProfiles.requiresAthleteProfile {
                return .needsOnboarding(
                    OnboardingContext(me: me, requiredProfiles: requiredProfiles),
                )
            }

            return .authenticated(UserContext(me: me))

        case let .failure(error):
            switch error {
            case .unauthorized, .forbidden:
                await authService.logout()
                return .unauthenticated
            default:
                return .error(
                    UserFacingError(
                        title: "Ошибка сессии",
                        message: "Не удалось загрузить профиль пользователя.",
                    ),
                )
            }
        }
    }
}
