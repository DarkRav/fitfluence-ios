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

struct InfluencersSearchRequest: Codable, Equatable, Sendable {
    let filter: InfluencerSearchFilter?
    let page: Int?
    let size: Int?
}

struct InfluencerSearchFilter: Codable, Equatable, Sendable {
    let search: String?
}

struct FollowCreatorRequest: Codable, Equatable, Sendable {
    let influencerId: String
}

struct SocialLink: Codable, Equatable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String?
    let platform: String?
    let url: URL?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case label
        case name
        case platform
        case type
        case url
        case href
    }

    init(
        id: String,
        title: String?,
        platform: String?,
        url: URL?,
    ) {
        self.id = id
        self.title = title
        self.platform = platform
        self.url = url
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let raw = try? container.decode(String.self)
        {
            let parsedURL = URL(string: raw)
            id = parsedURL?.absoluteString ?? raw
            title = nil
            platform = nil
            url = parsedURL
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)

        let resolvedPlatform = container.decodeLossyString(forKeys: [.platform, .type])
        let resolvedTitle = container.decodeLossyString(forKeys: [.title, .label, .name])
        let resolvedURL = container.decodeLossyURL(forKeys: [.url, .href])
        let resolvedID = container.decodeLossyString(forKeys: [.id])
            ?? resolvedURL?.absoluteString
            ?? resolvedPlatform
            ?? UUID().uuidString

        id = resolvedID
        title = resolvedTitle
        platform = resolvedPlatform
        url = resolvedURL
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(platform, forKey: .platform)
        try container.encodeIfPresent(url, forKey: .url)
    }
}

struct InfluencerPublicCard: Codable, Equatable, Sendable, Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let bio: String?
    let avatar: URL?
    let socialLinks: [SocialLink]?
    let followersCount: Int
    let programsCount: Int
    let isFollowedByMe: Bool
    let directionTag: String?
    let achievements: [String]?
    let trainingPhilosophy: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case bio
        case avatar
        case socialLinks
        case followersCount
        case programsCount
        case isFollowedByMe
        case directionTag
        case trainingDirection
        case specialization
        case tag
        case focus
        case achievements
        case achievementsList
        case highlights
        case titles
        case trainingPhilosophy
        case philosophy
        case aboutDirection
    }

    init(
        id: UUID,
        displayName: String,
        bio: String?,
        avatar: URL?,
        socialLinks: [SocialLink]?,
        followersCount: Int,
        programsCount: Int,
        isFollowedByMe: Bool,
        directionTag: String? = nil,
        achievements: [String]? = nil,
        trainingPhilosophy: String? = nil,
    ) {
        self.id = id
        self.displayName = displayName
        self.bio = bio
        self.avatar = avatar
        self.socialLinks = socialLinks
        self.followersCount = max(0, followersCount)
        self.programsCount = max(0, programsCount)
        self.isFollowedByMe = isFollowedByMe
        self.directionTag = directionTag?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.achievements = achievements?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .nilIfEmpty
        self.trainingPhilosophy = trainingPhilosophy?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let uuid = try? container.decode(UUID.self, forKey: .id) {
            id = uuid
        } else if let rawID = container.decodeLossyString(forKeys: [.id]),
                  let uuid = UUID(uuidString: rawID)
        {
            id = uuid
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Invalid influencer id")
        }

        displayName = container.decodeLossyString(forKeys: [.displayName]) ?? "Атлет"
        bio = container.decodeLossyString(forKeys: [.bio])

        if let directURL = container.decodeLossyURL(forKeys: [.avatar]) {
            avatar = directURL
        } else if let media = try? container.decodeIfPresent(ContentMedia.self, forKey: .avatar) {
            avatar = URL(string: media.url)
        } else if let payload = try? container.decodeIfPresent(AvatarPayload.self, forKey: .avatar),
                  let rawURL = payload.url?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawURL.isEmpty
        {
            avatar = URL(string: rawURL)
        } else {
            avatar = nil
        }

        socialLinks = try? container.decodeIfPresent([SocialLink].self, forKey: .socialLinks)
        followersCount = max(0, container.decodeLossyInt(forKeys: [.followersCount]) ?? 0)
        programsCount = max(0, container.decodeLossyInt(forKeys: [.programsCount]) ?? 0)
        isFollowedByMe = container.decodeLossyBool(forKeys: [.isFollowedByMe]) ?? false
        directionTag = container.decodeLossyString(forKeys: [.directionTag, .trainingDirection, .specialization, .tag, .focus])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        achievements = container.decodeLossyStringArray(forKeys: [.achievements, .achievementsList, .highlights, .titles])?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .nilIfEmpty
        trainingPhilosophy = container.decodeLossyString(forKeys: [.trainingPhilosophy, .philosophy, .aboutDirection])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(avatar, forKey: .avatar)
        try container.encodeIfPresent(socialLinks, forKey: .socialLinks)
        try container.encode(followersCount, forKey: .followersCount)
        try container.encode(programsCount, forKey: .programsCount)
        try container.encode(isFollowedByMe, forKey: .isFollowedByMe)
        try container.encodeIfPresent(directionTag, forKey: .directionTag)
        try container.encodeIfPresent(achievements, forKey: .achievements)
        try container.encodeIfPresent(trainingPhilosophy, forKey: .trainingPhilosophy)
    }
}

struct PagedInfluencerPublicCardResponse: Decodable, Equatable, Sendable {
    let content: [InfluencerPublicCard]
    let metadata: PageMetadata

    private enum CodingKeys: String, CodingKey {
        case content
        case items
        case data
        case value
        case results
        case metadata
        case page
        case size
        case totalElements
        case totalPages
    }

    init(content: [InfluencerPublicCard], metadata: PageMetadata) {
        self.content = content
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let direct = try? container.decode([InfluencerPublicCard].self)
        {
            content = direct
            metadata = PageMetadata(
                page: 0,
                size: direct.count,
                totalElements: direct.count,
                totalPages: direct.isEmpty ? 0 : 1,
            )
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = container.decodeLossyArray(forKeys: [.content, .items, .data, .value, .results]) ?? []

        if let decodedMetadata = try? container.decodeIfPresent(PageMetadata.self, forKey: .metadata) {
            metadata = decodedMetadata
        } else {
            let page = container.decodeLossyInt(forKeys: [.page]) ?? 0
            let size = container.decodeLossyInt(forKeys: [.size]) ?? max(1, content.count)
            let totalElements = container.decodeLossyInt(forKeys: [.totalElements]) ?? content.count
            let totalPages = container.decodeLossyInt(forKeys: [.totalPages])
                ?? (size > 0 ? Int(ceil(Double(max(totalElements, content.count)) / Double(size))) : 0)
            metadata = PageMetadata(
                page: max(0, page),
                size: max(1, size),
                totalElements: max(0, totalElements),
                totalPages: max(0, totalPages),
            )
        }
    }
}

private struct AvatarPayload: Codable, Equatable, Sendable {
    let url: String?
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
    let socialLinks: [SocialLink]?
    let followersCount: Int?
    let programsCount: Int?
    let isFollowedByMe: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case avatar
        case bio
        case socialLinks
        case followersCount
        case programsCount
        case isFollowedByMe
    }

    init(
        id: String,
        displayName: String,
        avatar: ContentMedia?,
        bio: String?,
        socialLinks: [SocialLink]? = nil,
        followersCount: Int? = nil,
        programsCount: Int? = nil,
        isFollowedByMe: Bool? = nil,
    ) {
        self.id = id
        self.displayName = displayName
        self.avatar = avatar
        self.bio = bio
        self.socialLinks = socialLinks
        self.followersCount = followersCount
        self.programsCount = programsCount
        self.isFollowedByMe = isFollowedByMe
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyString(forKeys: [.id]) ?? ""
        displayName = container.decodeLossyString(forKeys: [.displayName]) ?? "Атлет"
        bio = container.decodeLossyString(forKeys: [.bio])
        socialLinks = try? container.decodeIfPresent([SocialLink].self, forKey: .socialLinks)
        followersCount = container.decodeLossyInt(forKeys: [.followersCount])
        programsCount = container.decodeLossyInt(forKeys: [.programsCount])
        isFollowedByMe = container.decodeLossyBool(forKeys: [.isFollowedByMe])

        if let media = try? container.decodeIfPresent(ContentMedia.self, forKey: .avatar) {
            avatar = media
        } else if let rawAvatarURL = container.decodeLossyString(forKeys: [.avatar]),
                  !rawAvatarURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            avatar = ContentMedia(
                id: "avatar-\(id)",
                type: .image,
                url: rawAvatarURL,
                mimeType: nil,
                tags: nil,
                createdAt: nil,
                ownerType: nil,
                ownerId: nil,
                ownerDisplayName: nil,
            )
        } else {
            avatar = nil
        }
    }
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
    let description: String?
    let isBodyweight: Bool?
    let media: [ContentMedia]?
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
    func influencersSearch(request: InfluencersSearchRequest) async -> Result<PagedInfluencerPublicCardResponse, APIError>
    func getFollowingCreators(page: Int, size: Int, search: String?) async -> Result<PagedInfluencerPublicCardResponse, APIError>
    func followCreator(influencerId: UUID) async -> Result<Void, APIError>
    func unfollowCreator(influencerId: UUID) async -> Result<Void, APIError>
    func getCreatorPrograms(influencerId: UUID, page: Int, size: Int) async -> Result<PagedProgramResponse, APIError>
    func getProgramDetails(programId: String) async -> Result<ProgramDetails, APIError>
    func startProgram(programVersionId: String) async -> Result<ProgramEnrollment, APIError>
}

extension ProgramsClientProtocol {
    func influencersSearch(request _: InfluencersSearchRequest) async -> Result<PagedInfluencerPublicCardResponse, APIError> {
        .failure(.invalidURL)
    }

    func getFollowingCreators(page _: Int, size _: Int, search _: String?) async -> Result<PagedInfluencerPublicCardResponse, APIError> {
        .failure(.invalidURL)
    }

    func followCreator(influencerId _: UUID) async -> Result<Void, APIError> {
        .failure(.invalidURL)
    }

    func unfollowCreator(influencerId _: UUID) async -> Result<Void, APIError> {
        .failure(.invalidURL)
    }

    func getCreatorPrograms(influencerId _: UUID, page: Int, size: Int) async -> Result<PagedProgramResponse, APIError> {
        await listPublishedPrograms(query: "", page: page, size: size)
    }
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

extension InfluencerBrief {
    var asPublicCard: InfluencerPublicCard? {
        guard let uuid = UUID(uuidString: id) else {
            return nil
        }
        return InfluencerPublicCard(
            id: uuid,
            displayName: displayName,
            bio: bio,
            avatar: avatar.flatMap { URL(string: $0.url) },
            socialLinks: socialLinks,
            followersCount: max(0, followersCount ?? 0),
            programsCount: max(0, programsCount ?? 0),
            isFollowedByMe: isFollowedByMe ?? false,
        )
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyString(forKeys keys: [Key]) -> String? {
        for key in keys {
            if let value = try? decodeIfPresent(String.self, forKey: key) {
                return value
            }
            if let value = try? decodeIfPresent(Int.self, forKey: key) {
                return String(value)
            }
            if let value = try? decodeIfPresent(UUID.self, forKey: key) {
                return value.uuidString
            }
        }
        return nil
    }

    func decodeLossyInt(forKeys keys: [Key]) -> Int? {
        for key in keys {
            if let value = try? decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            if let value = try? decodeIfPresent(String.self, forKey: key),
               let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                return parsed
            }
            if let value = try? decodeIfPresent(Double.self, forKey: key) {
                return Int(value)
            }
        }
        return nil
    }

    func decodeLossyBool(forKeys keys: [Key]) -> Bool? {
        for key in keys {
            if let value = try? decodeIfPresent(Bool.self, forKey: key) {
                return value
            }
            if let value = try? decodeIfPresent(Int.self, forKey: key) {
                return value != 0
            }
            if let value = try? decodeIfPresent(String.self, forKey: key) {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["true", "1", "yes"].contains(normalized) {
                    return true
                }
                if ["false", "0", "no"].contains(normalized) {
                    return false
                }
            }
        }
        return nil
    }

    func decodeLossyURL(forKeys keys: [Key]) -> URL? {
        for key in keys {
            if let value = try? decodeIfPresent(URL.self, forKey: key) {
                return value
            }
            if let value = try? decodeIfPresent(String.self, forKey: key),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return URL(string: value)
            }
        }
        return nil
    }

    func decodeLossyArray<T: Decodable>(forKeys keys: [Key]) -> [T]? {
        for key in keys {
            if let value = try? decodeIfPresent([T].self, forKey: key) {
                return value
            }
        }
        return nil
    }

    func decodeLossyStringArray(forKeys keys: [Key]) -> [String]? {
        for key in keys {
            if let direct = try? decodeIfPresent([String].self, forKey: key) {
                return direct
            }

            if let single = try? decodeIfPresent(String.self, forKey: key) {
                let parts = single
                    .split(whereSeparator: { [",", ";", "\n", "•"].contains($0) })
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return parts.isEmpty ? [single] : parts
            }

            if let values = try? decodeIfPresent([JSONValue].self, forKey: key) {
                let mapped = values.compactMap { value -> String? in
                    switch value {
                    case let .string(text):
                        return text
                    case let .int(number):
                        return String(number)
                    case let .double(number):
                        return String(number)
                    default:
                        return nil
                    }
                }
                if !mapped.isEmpty {
                    return mapped
                }
            }
        }
        return nil
    }
}

private extension Array where Element == String {
    var nilIfEmpty: [String]? {
        isEmpty ? nil : self
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
