import AuthenticationServices
import Foundation
import UIKit

struct AppleAuthorizationPayload: Equatable, Sendable {
    let identityToken: String
    let authorizationCode: String
    let userIdentifier: String
}

protocol AppleSignInAuthorizing: Sendable {
    @MainActor
    func authorize() async throws -> AppleAuthorizationPayload
}

final class AppleSignInAuthorizer: NSObject, AppleSignInAuthorizing {
    @MainActor
    private var continuation: CheckedContinuation<AppleAuthorizationPayload, Error>?

    @MainActor
    func authorize() async throws -> AppleAuthorizationPayload {
        guard continuation == nil else {
            throw APIError.unknown
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

@MainActor
extension AppleSignInAuthorizer: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization,
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: APIError.unknown)
            continuation = nil
            return
        }

        guard
            let identityTokenData = credential.identityToken,
            let identityToken = String(data: identityTokenData, encoding: .utf8),
            !identityToken.isEmpty
        else {
            continuation?.resume(throwing: APIError.unknown)
            continuation = nil
            return
        }

        guard
            let authorizationCodeData = credential.authorizationCode,
            let authorizationCode = String(data: authorizationCodeData, encoding: .utf8),
            !authorizationCode.isEmpty
        else {
            continuation?.resume(throwing: APIError.unknown)
            continuation = nil
            return
        }

        continuation?.resume(
            returning: AppleAuthorizationPayload(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                userIdentifier: credential.user,
            ),
        )
        continuation = nil
    }

    func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithError error: Error,
    ) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation?.resume(throwing: APIError.cancelled)
        } else {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}

@MainActor
extension AppleSignInAuthorizer: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
