import Foundation

struct CreateAthleteProfileRequest: Codable, Equatable, Sendable {
    let displayName: String
    let primaryGoal: String

    enum CodingKeys: String, CodingKey {
        case displayName
        case primaryGoal
        case goals
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Legacy compatibility.
        try container.encode(displayName, forKey: .displayName)
        try container.encode(primaryGoal, forKey: .primaryGoal)

        // OpenAPI contract compatibility.
        let normalizedGoal = primaryGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedGoal.isEmpty {
            try container.encode([normalizedGoal], forKey: .goals)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = (try? container.decodeIfPresent(String.self, forKey: .displayName)) ?? ""
        let directGoal = (try? container.decodeIfPresent(String.self, forKey: .primaryGoal)) ?? nil
        let goals = (try? container.decodeIfPresent([String].self, forKey: .goals)) ?? nil

        if let directGoal {
            primaryGoal = directGoal
        } else if let first = goals?.first {
            primaryGoal = first
        } else {
            primaryGoal = ""
        }
    }

    init(displayName: String, primaryGoal: String) {
        self.displayName = displayName
        self.primaryGoal = primaryGoal
    }
}

struct CreateAthleteProfileResponse: Decodable, Equatable, Sendable {
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

protocol AthleteProfileClientProtocol: Sendable {
    func createProfile(_ request: CreateAthleteProfileRequest) async -> Result<CreateAthleteProfileResponse, APIError>
}
