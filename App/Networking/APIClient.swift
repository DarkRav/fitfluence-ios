import Foundation

struct HealthResponse: Codable, Equatable {
    let status: String
}

struct AthleteWorkoutTemplateExerciseCatalogPayload: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
}

struct AthleteWorkoutTemplateExercisePayload: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let exercise: AthleteWorkoutTemplateExerciseCatalogPayload
    let sets: Int
    let repsMin: Int?
    let repsMax: Int?
    let targetRpe: Int?
    let restSeconds: Int?
    let notes: String?
    let progressionPolicyId: String?
    let orderIndex: Int
}

struct AthleteWorkoutTemplatePayload: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let athleteId: String
    let title: String
    let notes: String?
    let exercises: [AthleteWorkoutTemplateExercisePayload]
    let createdAt: String?
    let updatedAt: String?
}

struct AthleteWorkoutTemplateExerciseInputRequest: Codable, Equatable, Sendable {
    let exerciseId: String
    let sets: Int
    let repsMin: Int?
    let repsMax: Int?
    let targetRpe: Int?
    let restSeconds: Int?
    let notes: String?
    let progressionPolicyId: String?
}

struct CreateAthleteWorkoutTemplateRequestBody: Codable, Equatable, Sendable {
    let title: String
    let notes: String?
    let exercises: [AthleteWorkoutTemplateExerciseInputRequest]
}

struct UpdateAthleteWorkoutTemplateRequestBody: Codable, Equatable, Sendable {
    let title: String?
    let notes: String?
    let exercises: [AthleteWorkoutTemplateExerciseInputRequest]?
}

protocol AthleteWorkoutTemplatesAPIClientProtocol: Sendable {
    func listAthleteWorkoutTemplates() async -> Result<[AthleteWorkoutTemplatePayload], APIError>
    func createAthleteWorkoutTemplate(
        request: CreateAthleteWorkoutTemplateRequestBody,
    ) async -> Result<AthleteWorkoutTemplatePayload, APIError>
    func updateAthleteWorkoutTemplate(
        templateId: String,
        request: UpdateAthleteWorkoutTemplateRequestBody,
    ) async -> Result<AthleteWorkoutTemplatePayload, APIError>
    func deleteAthleteWorkoutTemplate(templateId: String) async -> Result<Void, APIError>
}

extension APIClient: AthleteWorkoutTemplatesAPIClientProtocol {
    func listAthleteWorkoutTemplates() async -> Result<[AthleteWorkoutTemplatePayload], APIError> {
        let request = APIRequest.get(path: "/v1/athlete/templates", requiresAuthorization: true)
        return await decode(request, as: [AthleteWorkoutTemplatePayload].self)
    }

    func createAthleteWorkoutTemplate(
        request: CreateAthleteWorkoutTemplateRequestBody,
    ) async -> Result<AthleteWorkoutTemplatePayload, APIError> {
        do {
            let body = try JSONEncoder().encode(request)
            let apiRequest = APIRequest(
                path: "/v1/athlete/templates",
                method: .post,
                body: body,
                requiresAuthorization: true,
            )
            return await decode(apiRequest, as: AthleteWorkoutTemplatePayload.self)
        } catch {
            return .failure(.unknown)
        }
    }

    func updateAthleteWorkoutTemplate(
        templateId: String,
        request: UpdateAthleteWorkoutTemplateRequestBody,
    ) async -> Result<AthleteWorkoutTemplatePayload, APIError> {
        do {
            let body = try JSONEncoder().encode(request)
            let apiRequest = APIRequest(
                path: "/v1/athlete/templates/\(templateId)",
                method: .patch,
                body: body,
                requiresAuthorization: true,
            )
            return await decode(apiRequest, as: AthleteWorkoutTemplatePayload.self)
        } catch {
            return .failure(.unknown)
        }
    }

    func deleteAthleteWorkoutTemplate(templateId: String) async -> Result<Void, APIError> {
        let request = APIRequest(
            path: "/v1/athlete/templates/\(templateId)",
            method: .delete,
            requiresAuthorization: true,
        )
        return await performWithRetry(request, allowRetryAfterRefresh: true)
    }
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
                body: payload,
                requiresAuthorization: false,
            )
            let result: Result<PagedProgramResponse, APIError> = await decode(request, as: PagedProgramResponse.self)
            switch result {
            case .success:
                return .success(HealthResponse(status: "OK"))
            case let .failure(error):
                return .failure(error)
            }
        } catch {
            return .failure(.unknown)
        }
    }

    func me() async -> Result<MeResponse, APIError> {
        let request = APIRequest.get(path: "/v1/me", requiresAuthorization: true)
        return await decodeMeWithRetry(request, allowRetryAfterRefresh: true)
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

    func listFeaturedPrograms(page: Int, size: Int = 20) async -> Result<PagedProgramResponse, APIError> {
        let request = APIRequest.get(
            path: "/v1/programs/featured",
            queryItems: [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "size", value: "\(size)"),
            ],
            requiresAuthorization: false,
        )
        return await decode(request, as: PagedProgramResponse.self)
    }

    func influencersSearch(request: InfluencersSearchRequest) async -> Result<PagedInfluencerPublicCardResponse, APIError> {
        do {
            let payload = try JSONEncoder().encode(request)
            let apiRequest = APIRequest(path: "/v1/influencers/search", method: .post, body: payload)
            return await decode(apiRequest, as: PagedInfluencerPublicCardResponse.self)
        } catch {
            return .failure(.unknown)
        }
    }

    func getFollowingCreators(
        page: Int,
        size: Int = 20,
        search: String?,
    ) async -> Result<PagedInfluencerPublicCardResponse, APIError> {
        var queryItems = [
            URLQueryItem(name: "page", value: "\(max(0, page))"),
            URLQueryItem(name: "size", value: "\(max(1, size))"),
        ]
        if let search = search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        let request = APIRequest.get(path: "/v1/athlete/follows", queryItems: queryItems, requiresAuthorization: true)
        return await decode(request, as: PagedInfluencerPublicCardResponse.self)
    }

    func followCreator(influencerId: UUID) async -> Result<Void, APIError> {
        do {
            let payload = try JSONEncoder().encode(FollowCreatorRequest(influencerId: influencerId.uuidString))
            let request = APIRequest(path: "/v1/athlete/follows", method: .post, body: payload, requiresAuthorization: true)
            return await performWithRetry(request, allowRetryAfterRefresh: true)
        } catch {
            return .failure(.unknown)
        }
    }

    func unfollowCreator(influencerId: UUID) async -> Result<Void, APIError> {
        let request = APIRequest(
            path: "/v1/athlete/follows/\(influencerId.uuidString)",
            method: .delete,
            requiresAuthorization: true,
        )
        return await performWithRetry(request, allowRetryAfterRefresh: true)
    }

    func getCreatorPrograms(
        influencerId: UUID,
        page: Int,
        size: Int = 20,
    ) async -> Result<PagedProgramResponse, APIError> {
        do {
            let body = ProgramsSearchRequest(
                filter: ProgramFilter(search: nil, influencerId: influencerId.uuidString, status: .published),
                page: max(0, page),
                size: max(1, size),
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

    func decode<T: Decodable>(_ request: APIRequest, as _: T.Type) async -> Result<T, APIError> {
        await decodeWithRetry(request, allowRetryAfterRefresh: true)
    }

    private func decodeWithRetry<T: Decodable>(
        _ request: APIRequest,
        allowRetryAfterRefresh: Bool,
    ) async -> Result<T, APIError> {
        do {
            let response = try await httpClient.send(request)
            do {
                let decoded = try JSONDecoder().decode(T.self, from: response.data)
                return .success(decoded)
            } catch let decodingError as DecodingError {
                let snippet = String(data: response.data.prefix(600), encoding: .utf8) ?? "<non-utf8>"
                FFLog.error(
                    "API decode failed method=\(request.method.rawValue) path=\(request.path) error=\(String(describing: decodingError)); bodySnippet=\(snippet)",
                )
                return .failure(.decodingError)
            }
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
        } catch {
            return .failure(.unknown)
        }
    }

    func performWithRetry(
        _ request: APIRequest,
        allowRetryAfterRefresh: Bool,
    ) async -> Result<Void, APIError> {
        do {
            _ = try await httpClient.send(request)
            return .success(())
        } catch let apiError as APIError {
            if case .unauthorized = apiError, allowRetryAfterRefresh, let authService {
                let refreshed = await authService.refresh()
                if refreshed {
                    return await performWithRetry(request, allowRetryAfterRefresh: false)
                }
                await authService.logout()
                return .failure(.unauthorized)
            }
            return .failure(apiError)
        } catch {
            return .failure(.unknown)
        }
    }

    private func decodeMeWithRetry(
        _ request: APIRequest,
        allowRetryAfterRefresh: Bool,
    ) async -> Result<MeResponse, APIError> {
        do {
            let response = try await httpClient.send(request)
            do {
                return try .success(decodeMeResponse(from: response.data))
            } catch let decodingError as DecodingError {
                let snippet = String(data: response.data.prefix(600), encoding: .utf8) ?? "<non-utf8>"
                FFLog.error(
                    "API decode /v1/me failed: \(String(describing: decodingError)); bodySnippet=\(snippet)",
                )
                return .failure(.decodingError)
            } catch {
                let snippet = String(data: response.data.prefix(600), encoding: .utf8) ?? "<non-utf8>"
                FFLog.error("API decode /v1/me unknown error; bodySnippet=\(snippet)")
                return .failure(.decodingError)
            }
        } catch let apiError as APIError {
            if case .unauthorized = apiError, allowRetryAfterRefresh, let authService {
                let refreshed = await authService.refresh()
                if refreshed {
                    return await decodeMeWithRetry(request, allowRetryAfterRefresh: false)
                }
                await authService.logout()
                return .failure(.unauthorized)
            }
            return .failure(apiError)
        } catch {
            return .failure(.unknown)
        }
    }

    private func decodeMeResponse(from data: Data) throws -> MeResponse {
        let decoder = JSONDecoder()
        if let direct = try? decoder.decode(MeResponse.self, from: data) {
            return direct
        }

        let object = try JSONSerialization.jsonObject(with: data)
        for candidate in extractMeCandidates(from: object) {
            guard JSONSerialization.isValidJSONObject(candidate),
                  let candidateData = try? JSONSerialization.data(withJSONObject: candidate),
                  let decoded = try? decoder.decode(MeResponse.self, from: candidateData)
            else {
                continue
            }
            return decoded
        }

        // Throw a real DecodingError so callers keep existing mapping.
        let context = DecodingError.Context(codingPath: [], debugDescription: "Unsupported /v1/me JSON shape")
        throw DecodingError.dataCorrupted(context)
    }

    private func extractMeCandidates(from object: Any) -> [[String: Any]] {
        switch object {
        case let dictionary as [String: Any]:
            var candidates: [[String: Any]] = [dictionary]
            let keys = ["data", "result", "payload", "me", "user", "value", "response"]

            for key in keys {
                if let nested = dictionary[key] {
                    candidates.append(contentsOf: extractMeCandidates(from: nested))
                }
            }
            return candidates

        case let array as [Any]:
            return array.flatMap { extractMeCandidates(from: $0) }

        default:
            return []
        }
    }
}
