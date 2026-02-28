import Foundation

struct CreateAthleteProfileRequest: Codable, Equatable, Sendable {
    let displayName: String
    let primaryGoal: String
}

struct CreateAthleteProfileResponse: Codable, Equatable, Sendable {
    let id: String?
}

protocol AthleteProfileClientProtocol: Sendable {
    func createProfile(_ request: CreateAthleteProfileRequest) async -> Result<CreateAthleteProfileResponse, APIError>
}
