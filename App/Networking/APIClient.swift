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
    func listPublishedPrograms(query: String, page: Int, size: Int) async -> Result<PagedProgramResponse, APIError>
    func getProgramDetails(programId: String) async -> Result<ProgramDetails, APIError>
    func startProgram(programVersionId: String) async -> Result<ProgramEnrollment, APIError>
}

final class APIClient: APIClientProtocol, MeClientProtocol, AthleteProfileClientProtocol,
    InfluencerProfileClientProtocol, ProgramsClientProtocol
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
        do {
            let body = ProgramsSearchRequest(
                filter: ProgramFilter(search: nil, influencerId: nil, status: .published),
                page: 0,
                size: 1,
            )
            let payload = try JSONEncoder().encode(body)
            let request = APIRequest(
                path: "/v1/programs/published/search",
                method: .post,
                queryItems: [],
                headers: [:],
                body: payload,
                requiresAuthorization: false,
                timeoutInterval: nil,
            )
            let result: Result<PagedProgramResponse, APIError> = await decode(request, as: PagedProgramResponse.self)
            switch result {
            case let .success(response):
                return .success(HealthResponse(status: "OK (\(response.metadata.totalElements))"))
            case let .failure(error):
                return .failure(error)
            }
        } catch {
            return .failure(.unknown)
        }
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

    func listPublishedPrograms(
        query: String,
        page: Int,
        size: Int = 20,
    ) async -> Result<PagedProgramResponse, APIError> {
        do {
            let body = ProgramsSearchRequest(
                filter: ProgramFilter(search: query.isEmpty ? nil : query, influencerId: nil, status: .published),
                page: page,
                size: size,
            )
            let payload = try JSONEncoder().encode(body)
            let request = APIRequest(path: "/v1/programs/published/search", method: .post, body: payload)
            return await decode(request, as: PagedProgramResponse.self)
        } catch {
            return .failure(.unknown)
        }
    }

    func getProgramDetails(programId: String) async -> Result<ProgramDetails, APIError> {
        let request = APIRequest.get(path: "/v1/programs/\(programId)", requiresAuthorization: true)
        return await decode(request, as: ProgramDetails.self)
    }

    func startProgram(programVersionId: String) async -> Result<ProgramEnrollment, APIError> {
        do {
            let payload = try JSONEncoder().encode(CreateSelfEnrollmentRequest(programVersionId: programVersionId))
            let request = APIRequest(path: "/v1/athlete/enrollments/self", method: .post, body: payload)
            return await decode(request, as: ProgramEnrollment.self)
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
