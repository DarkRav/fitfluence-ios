import Foundation

struct ProgramsSearchRequest: Codable, Equatable, Sendable {
    let filter: ProgramFilter?
    let page: Int?
    let size: Int?
}

struct ProgramFilter: Codable, Equatable, Sendable {
    let search: String?
    let influencerId: String?
    let status: ProgramStatus?
}

struct PagedProgramResponse: Codable, Equatable, Sendable {
    let content: [ProgramListItem]
    let metadata: PageMetadata
}

struct PageMetadata: Codable, Equatable, Sendable {
    let page: Int
    let size: Int
    let totalElements: Int
    let totalPages: Int
}

enum ProgramStatus: String, Codable, Equatable, Sendable {
    case draft = "DRAFT"
    case published = "PUBLISHED"
    case archived = "ARCHIVED"
}

enum ProgramVersionStatus: String, Codable, Equatable, Sendable {
    case draft = "DRAFT"
    case published = "PUBLISHED"
    case archived = "ARCHIVED"
}

enum ContentMediaType: String, Codable, Equatable, Sendable {
    case image = "IMAGE"
    case video = "VIDEO"
}

struct ContentMedia: Codable, Equatable, Sendable {
    let id: String
    let type: ContentMediaType
    let url: String
    let mimeType: String?
    let tags: [String]?
    let createdAt: String?
    let ownerType: String?
    let ownerId: String?
    let ownerDisplayName: String?
}

struct InfluencerBrief: Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let avatar: ContentMedia?
    let bio: String?
}

struct ProgramVersionSummary: Codable, Equatable, Sendable {
    let id: String
    let versionNumber: Int
    let status: ProgramVersionStatus
    let publishedAt: String?
    let level: String?
    let frequencyPerWeek: Int?
    let requirements: [String: JSONValue]?
}

struct ProgramListItem: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let status: ProgramStatus
    let isFeatured: Bool?
    let influencer: InfluencerBrief?
    let cover: ContentMedia?
    let media: [ContentMedia]?
    let goals: [String]?
    let currentPublishedVersion: ProgramVersionSummary?
    let level: String?
    let daysPerWeek: Int?
    let estimatedDurationMinutes: Int?
    let equipment: [String]?
    let createdAt: String?
    let updatedAt: String?
}

struct ExerciseSummary: Codable, Equatable, Sendable {
    let id: String
    let code: String?
    let name: String
}

struct ExerciseTemplate: Codable, Equatable, Sendable {
    let id: String
    let exercise: ExerciseSummary
    let sets: Int
    let repsMin: Int?
    let repsMax: Int?
    let targetRpe: Int?
    let restSeconds: Int?
    let notes: String?
    let orderIndex: Int?
}

struct WorkoutTemplate: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let dayOrder: Int
    let title: String?
    let coachNote: String?
    let exercises: [ExerciseTemplate]?
    let media: [ContentMedia]?
}

struct ProgramDetails: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let status: ProgramStatus
    let isFeatured: Bool?
    let influencer: InfluencerBrief?
    let cover: ContentMedia?
    let media: [ContentMedia]?
    let goals: [String]?
    let currentPublishedVersion: ProgramVersionSummary?
    let createdAt: String?
    let updatedAt: String?
    let versions: [ProgramVersionSummary]?
    let workouts: [WorkoutTemplate]?
}

struct CreateSelfEnrollmentRequest: Codable, Equatable, Sendable {
    let programVersionId: String
}

enum EnrollmentStatus: String, Codable, Equatable, Sendable {
    case active = "ACTIVE"
    case paused = "PAUSED"
    case completed = "COMPLETED"
}

struct ProgramEnrollment: Codable, Equatable, Sendable {
    let id: String
    let athleteId: String
    let programVersionId: String
    let status: EnrollmentStatus
    let startedAt: String
    let createdAt: String?
    let updatedAt: String?
}

protocol ProgramsClientProtocol: Sendable {
    func listPublishedPrograms(query: String, page: Int, size: Int) async -> Result<PagedProgramResponse, APIError>
    func listFeaturedPrograms(page: Int, size: Int) async -> Result<PagedProgramResponse, APIError>
    func getProgramDetails(programId: String) async -> Result<ProgramDetails, APIError>
    func startProgram(programVersionId: String) async -> Result<ProgramEnrollment, APIError>
}

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

extension ContentMedia {
    func resolvedURL(baseURL: URL?) -> URL? {
        guard let direct = URL(string: url) else {
            return nil
        }
        if direct.scheme != nil {
            return direct
        }
        guard let baseURL else {
            return nil
        }
        let normalizedPath = url.hasPrefix("/") ? String(url.dropFirst()) : url
        return baseURL.appendingPathComponent(normalizedPath)
    }
}
