import Foundation

struct HealthResponse: Codable, Equatable {
    let status: String
}

protocol APIClientProtocol: Sendable {
    func healthCheck() async -> Result<HealthResponse, APIError>
    func me() async -> Result<MeResponse, APIError>
    func createProfile(_ request: CreateAthleteProfileRequest) async -> Result<CreateAthleteProfileResponse, APIError>
    func createProfile(_ request: CreateInfluencerProfileRequest) async
        -> Result<CreateInfluencerProfileResponse, APIError>
}

final class APIClient: APIClientProtocol, MeClientProtocol, AthleteProfileClientProtocol,
    InfluencerProfileClientProtocol
{
    private let httpClient: HTTPClientProtocol
    private let authService: AuthServiceProtocol?

    init(httpClient: HTTPClientProtocol, authService: AuthServiceProtocol? = nil) {
        self.httpClient = httpClient
        self.authService = authService
    }

    static func live(
        environment: AppEnvironment,
        session: URLSession = .shared,
        tokenProvider: AuthTokenProvider = NoAuthTokenProvider(),
        authService: AuthServiceProtocol? = nil,
    ) -> APIClient? {
        guard let baseURL = environment.backendBaseURL else {
            return nil
        }
        return APIClient(
            httpClient: HTTPClient(baseURL: baseURL, session: session, tokenProvider: tokenProvider),
            authService: authService,
        )
    }

    func healthCheck() async -> Result<HealthResponse, APIError> {
        let request = APIRequest.get(path: "/actuator/health", requiresAuthorization: false)
        return await decode(request, as: HealthResponse.self)
    }

    func me() async -> Result<MeResponse, APIError> {
        let request = APIRequest.get(path: "/v1/me", requiresAuthorization: true)
        return await decode(request, as: MeResponse.self)
    }

    func createProfile(_ request: CreateAthleteProfileRequest) async -> Result<CreateAthleteProfileResponse, APIError> {
        do {
            let payload = try JSONEncoder().encode(request)
            let apiRequest = APIRequest(path: "/v1/athlete/profile", method: .post, body: payload)
            return await decode(apiRequest, as: CreateAthleteProfileResponse.self)
        } catch {
            return .failure(.unknown)
        }
    }

    func createProfile(_ request: CreateInfluencerProfileRequest) async
        -> Result<CreateInfluencerProfileResponse, APIError>
    {
        do {
            let payload = try JSONEncoder().encode(request)
            let apiRequest = APIRequest(path: "/v1/influencer/profile", method: .post, body: payload)
            return await decode(apiRequest, as: CreateInfluencerProfileResponse.self)
        } catch {
            return .failure(.unknown)
        }
    }

    private func decode<T: Decodable>(_ request: APIRequest, as _: T.Type) async -> Result<T, APIError> {
        await decodeWithRetry(request, allowRetryAfterRefresh: true)
    }

    private func decodeWithRetry<T: Decodable>(
        _ request: APIRequest,
        allowRetryAfterRefresh: Bool,
    ) async -> Result<T, APIError> {
        do {
            let response = try await httpClient.send(request)
            let decoded = try JSONDecoder().decode(T.self, from: response.data)
            return .success(decoded)
        } catch let apiError as APIError {
            if case .unauthorized = apiError, allowRetryAfterRefresh, let authService {
                let refreshed = await authService.refresh()
                if refreshed {
                    return await decodeWithRetry(request, allowRetryAfterRefresh: false)
                }
                await authService.logout()
                return .failure(.unauthorized)
            }
            return .failure(apiError)
        } catch is DecodingError {
            return .failure(.decodingError)
        } catch {
            return .failure(.unknown)
        }
    }
}
