import Foundation

struct MeResponse: Decodable, Equatable, Sendable {
    struct ProfileSummary: Codable, Equatable, Sendable {
        let id: String?
    }

    let subject: String?
    let email: String?
    let requiresAthleteProfile: Bool
    let requiresInfluencerProfile: Bool
    let athleteProfile: ProfileSummary?
    let influencerProfile: ProfileSummary?

    var hasAthleteProfile: Bool {
        athleteProfile != nil
    }

    var hasInfluencerProfile: Bool {
        influencerProfile != nil
    }

    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case email
        case requiresAthleteProfile
        case requiresInfluencerProfile
        case athleteProfile
        case influencerProfile
        case hasAthleteProfile
        case hasInfluencerProfile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subject = try container.decodeIfPresent(String.self, forKey: .subject)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        athleteProfile = try container.decodeIfPresent(ProfileSummary.self, forKey: .athleteProfile)
        influencerProfile = try container.decodeIfPresent(ProfileSummary.self, forKey: .influencerProfile)

        let requiresAthleteExplicit = try container.decodeIfPresent(Bool.self, forKey: .requiresAthleteProfile)
        let requiresInfluencerExplicit = try container.decodeIfPresent(Bool.self, forKey: .requiresInfluencerProfile)
        let hasAthleteExplicit = try container.decodeIfPresent(Bool.self, forKey: .hasAthleteProfile)
        let hasInfluencerExplicit = try container.decodeIfPresent(Bool.self, forKey: .hasInfluencerProfile)

        let resolvedHasAthlete = hasAthleteExplicit ?? (athleteProfile != nil)
        let resolvedHasInfluencer = hasInfluencerExplicit ?? (influencerProfile != nil)

        requiresAthleteProfile = requiresAthleteExplicit ?? !resolvedHasAthlete
        requiresInfluencerProfile = requiresInfluencerExplicit ?? !resolvedHasInfluencer
    }

    init(
        subject: String?,
        email: String?,
        requiresAthleteProfile: Bool,
        requiresInfluencerProfile: Bool,
        athleteProfile: ProfileSummary?,
        influencerProfile: ProfileSummary?,
    ) {
        self.subject = subject
        self.email = email
        self.requiresAthleteProfile = requiresAthleteProfile
        self.requiresInfluencerProfile = requiresInfluencerProfile
        self.athleteProfile = athleteProfile
        self.influencerProfile = influencerProfile
    }
}

struct RequiredProfiles: Equatable, Sendable {
    let requiresAthleteProfile: Bool
    let requiresInfluencerProfile: Bool
}

struct OnboardingContext: Equatable, Sendable {
    let me: MeResponse
    let requiredProfiles: RequiredProfiles
}

struct UserContext: Equatable, Sendable {
    let me: MeResponse
}

protocol MeClientProtocol: Sendable {
    func me() async -> Result<MeResponse, APIError>
}

struct UnavailableMeClient: MeClientProtocol {
    func me() async -> Result<MeResponse, APIError> {
        .failure(.invalidURL)
    }
}
