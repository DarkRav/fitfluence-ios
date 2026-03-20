import Foundation

enum APIExerciseMovementPattern: String, Codable, Equatable, Sendable {
    case push = "PUSH"
    case pull = "PULL"
    case squat = "SQUAT"
    case hinge = "HINGE"
    case other = "OTHER"
}

enum APIExerciseDifficultyLevel: String, Codable, Equatable, Sendable {
    case beginner = "BEGINNER"
    case intermediate = "INTERMEDIATE"
    case advanced = "ADVANCED"
}

enum APIMuscleGroup: String, Codable, Equatable, Sendable {
    case back = "BACK"
    case chest = "CHEST"
    case legs = "LEGS"
    case shoulders = "SHOULDERS"
    case arms = "ARMS"
    case abs = "ABS"
}

enum APIEquipmentCategory: String, Codable, Equatable, Sendable {
    case freeWeight = "FREE_WEIGHT"
    case machine = "MACHINE"
    case bodyweight = "BODYWEIGHT"
    case band = "BAND"
    case cardio = "CARDIO"
}

struct APIExerciseMuscle: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let code: String
    let name: String
    let muscleGroup: APIMuscleGroup?
    let description: String?
    let media: [ContentMedia]?
}

struct APIExerciseEquipment: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let code: String
    let name: String
    let category: APIEquipmentCategory?
    let description: String?
    let media: [ContentMedia]?
}

struct APIExercise: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let code: String
    let name: String
    let description: String?
    let movementPattern: APIExerciseMovementPattern?
    let difficultyLevel: APIExerciseDifficultyLevel?
    let isBodyweight: Bool?
    let createdByInfluencerId: String?
    let muscles: [APIExerciseMuscle]?
    let media: [ContentMedia]?
    let equipment: [APIExerciseEquipment]?
}

struct APIExerciseFilter: Codable, Equatable, Sendable {
    let search: String?
    let movementPattern: APIExerciseMovementPattern?
    let difficultyLevel: APIExerciseDifficultyLevel?
    let muscleIds: [String]?
    let muscleGroups: [APIMuscleGroup]?
    let mediaTags: [String]?
    let equipmentIds: [String]?
}

struct APIExercisesSearchRequest: Codable, Equatable, Sendable {
    let filter: APIExerciseFilter?
    let page: Int?
    let size: Int?
}

struct APIPagedExerciseResponse: Decodable, Equatable, Sendable {
    let content: [APIExercise]
    let metadata: PageMetadata

    private enum CodingKeys: String, CodingKey {
        case content
        case metadata
        case page
        case size
        case totalElements
        case totalPages
    }

    init(content: [APIExercise], metadata: PageMetadata) {
        self.content = content
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent([APIExercise].self, forKey: .content) ?? []

        if let metadata = try container.decodeIfPresent(PageMetadata.self, forKey: .metadata) {
            self.metadata = metadata
            return
        }

        let page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 0
        let size = try container.decodeIfPresent(Int.self, forKey: .size) ?? max(1, content.count)
        let totalElements = try container.decodeIfPresent(Int.self, forKey: .totalElements) ?? content.count
        let totalPages = try container.decodeIfPresent(Int.self, forKey: .totalPages)
            ?? (size > 0 ? Int(ceil(Double(max(totalElements, content.count)) / Double(size))) : 0)

        metadata = PageMetadata(
            page: max(0, page),
            size: max(1, size),
            totalElements: max(0, totalElements),
            totalPages: max(0, totalPages),
        )
    }
}

struct APIAthleteExerciseCatalogMetadataResponse: Codable, Equatable, Sendable {
    let muscles: [APIExerciseMuscle]
    let equipment: [APIExerciseEquipment]
    let muscleGroups: [APIMuscleGroup]
    let equipmentCategories: [APIEquipmentCategory]
    let movementPatterns: [APIExerciseMovementPattern]
    let difficultyLevels: [APIExerciseDifficultyLevel]
}

protocol ExerciseCatalogAPIClientProtocol: Sendable {
    func searchAthleteExercises(request: APIExercisesSearchRequest?) async -> Result<APIPagedExerciseResponse, APIError>
    func athleteExerciseCatalogMetadata() async -> Result<APIAthleteExerciseCatalogMetadataResponse, APIError>
    func athleteExercise(id: String) async -> Result<APIExercise, APIError>
}

extension ExerciseCatalogAPIClientProtocol {
    func athleteExerciseCatalogMetadata() async -> Result<APIAthleteExerciseCatalogMetadataResponse, APIError> {
        .failure(.unknown)
    }

    func athleteExercise(id _: String) async -> Result<APIExercise, APIError> {
        .failure(.unknown)
    }
}

extension APIClient: ExerciseCatalogAPIClientProtocol {
    func searchAthleteExercises(request: APIExercisesSearchRequest?) async -> Result<APIPagedExerciseResponse, APIError> {
        do {
            let payload = try request.map { try JSONEncoder().encode($0) }
            let apiRequest = APIRequest(
                path: "/v1/athlete/exercises/search",
                method: .post,
                body: payload,
                requiresAuthorization: true,
            )
            return await decode(apiRequest, as: APIPagedExerciseResponse.self)
        } catch {
            return .failure(.unknown)
        }
    }

    func athleteExerciseCatalogMetadata() async -> Result<APIAthleteExerciseCatalogMetadataResponse, APIError> {
        let request = APIRequest.get(path: "/v1/athlete/exercise-catalog/metadata", requiresAuthorization: true)
        return await decode(request, as: APIAthleteExerciseCatalogMetadataResponse.self)
    }

    func athleteExercise(id: String) async -> Result<APIExercise, APIError> {
        let request = APIRequest.get(path: "/v1/athlete/exercises/\(id)", requiresAuthorization: true)
        return await decode(request, as: APIExercise.self)
    }
}
