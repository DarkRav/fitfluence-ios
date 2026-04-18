import AuthenticationServices
import Foundation

enum AppleCredentialState: Sendable {
    case authorized
    case revoked
    case notFound
    case transferred
    case unknown
}

protocol AppleCredentialStateChecking: Sendable {
    @MainActor
    func credentialState(forUserID userID: String) async -> AppleCredentialState
}

struct AppleCredentialStateChecker: AppleCredentialStateChecking {
    @MainActor
    func credentialState(forUserID userID: String) async -> AppleCredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                continuation.resume(returning: Self.map(state))
            }
        }
    }

    private static func map(_ state: ASAuthorizationAppleIDProvider.CredentialState) -> AppleCredentialState {
        switch state {
        case .authorized:
            return .authorized
        case .revoked:
            return .revoked
        case .notFound:
            return .notFound
        case .transferred:
            return .transferred
        @unknown default:
            return .unknown
        }
    }
}
