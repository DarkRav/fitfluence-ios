import Foundation

struct CreateInfluencerProfileRequest: Codable, Equatable, Sendable {
    let displayName: String
    let bio: String
}

struct CreateInfluencerProfileResponse: Codable, Equatable, Sendable {
    let id: String?
}

protocol InfluencerProfileClientProtocol: Sendable {
    func createProfile(_ request: CreateInfluencerProfileRequest) async
        -> Result<CreateInfluencerProfileResponse, APIError>
}
