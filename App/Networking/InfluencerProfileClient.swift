import Foundation

struct CreateInfluencerProfileRequest: Codable, Equatable, Sendable {
    let displayName: String
    let bio: String
}

struct CreateInfluencerProfileResponse: Decodable, Equatable, Sendable {
    let id: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let directID = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? nil
        let userID = (try? container.decodeIfPresent(String.self, forKey: .userId)) ?? nil
        let directUUID = (try? container.decodeIfPresent(UUID.self, forKey: .id))?.uuidString
        let userUUID = (try? container.decodeIfPresent(UUID.self, forKey: .userId))?.uuidString
        id = directID ?? userID ?? directUUID ?? userUUID
    }

    init(id: String?) {
        self.id = id
    }
}

protocol InfluencerProfileClientProtocol: Sendable {
    func createProfile(_ request: CreateInfluencerProfileRequest) async
        -> Result<CreateInfluencerProfileResponse, APIError>
}
