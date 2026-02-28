import Foundation

struct HealthResponse: Codable, Equatable {
    let status: String
}

protocol APIClientProtocol: Sendable {
    func healthCheck() async -> Result<HealthResponse, APIError>
}

final class APIClient: APIClientProtocol {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol) {
        self.httpClient = httpClient
    }

    static func live(
        environment: AppEnvironment,
        session: URLSession = .shared,
        tokenProvider: AuthTokenProvider = NoAuthTokenProvider()
    ) -> APIClient? {
        guard let baseURL = environment.backendBaseURL else {
            return nil
        }
        return APIClient(httpClient: HTTPClient(baseURL: baseURL, session: session, tokenProvider: tokenProvider))
    }

    func healthCheck() async -> Result<HealthResponse, APIError> {
        let request = APIRequest.get(path: "/actuator/health", requiresAuthorization: false)

        do {
            let response = try await httpClient.send(request)
            do {
                let decoded = try JSONDecoder().decode(HealthResponse.self, from: response.data)
                return .success(decoded)
            } catch {
                return .failure(.decodingError)
            }
        } catch let apiError as APIError {
            return .failure(apiError)
        } catch {
            return .failure(.unknown)
        }
    }
}
