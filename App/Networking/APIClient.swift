import Foundation

struct HealthResponse: Codable, Equatable {
    let status: String
}

protocol APIClientProtocol: Sendable {
    func healthCheck() async -> Result<HealthResponse, APIError>
    func me() async -> Result<MeResponse, APIError>
}

final class APIClient: APIClientProtocol, MeClientProtocol {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol) {
        self.httpClient = httpClient
    }

    static func live(
        environment: AppEnvironment,
        session: URLSession = .shared,
        tokenProvider: AuthTokenProvider = NoAuthTokenProvider(),
    ) -> APIClient? {
        guard let baseURL = environment.backendBaseURL else {
            return nil
        }
        return APIClient(httpClient: HTTPClient(baseURL: baseURL, session: session, tokenProvider: tokenProvider))
    }

    func healthCheck() async -> Result<HealthResponse, APIError> {
        let request = APIRequest.get(path: "/actuator/health", requiresAuthorization: false)
        return await decode(request, as: HealthResponse.self)
    }

    func me() async -> Result<MeResponse, APIError> {
        let request = APIRequest.get(path: "/v1/me", requiresAuthorization: true)
        return await decode(request, as: MeResponse.self)
    }

    private func decode<T: Decodable>(_ request: APIRequest, as _: T.Type) async -> Result<T, APIError> {
        do {
            let response = try await httpClient.send(request)
            let decoded = try JSONDecoder().decode(T.self, from: response.data)
            return .success(decoded)
        } catch let apiError as APIError {
            return .failure(apiError)
        } catch is DecodingError {
            return .failure(.decodingError)
        } catch {
            return .failure(.unknown)
        }
    }
}
