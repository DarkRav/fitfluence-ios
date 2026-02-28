import Foundation

struct MeResponse: Decodable, Equatable, Sendable {
    struct ProfileSummary: Decodable, Equatable, Sendable {
        let id: String?

        enum CodingKeys: String, CodingKey {
            case id
            case userId
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
                ?? container.decodeIfPresent(String.self, forKey: .userId)
        }

        init(id: String?) {
            self.id = id
        }
    }

    struct Identity: Decodable, Equatable, Sendable {
        let sub: String?
        let email: String?
    }

    struct ProfileState: Decodable, Equatable, Sendable {
        let exists: Bool
        let data: ProfileSummary?
    }

    struct Profiles: Decodable, Equatable, Sendable {
        let athleteProfile: ProfileState
        let influencerProfile: ProfileState
    }

    struct Onboarding: Decodable, Equatable, Sendable {
        let requiresAthleteProfile: Bool
        let requiresInfluencerProfile: Bool
    }

    let subject: String?
    let email: String?
    let roles: [String]
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
        case identity
        case roles
        case profiles
        case onboarding
        case requiresAthleteProfile
        case requiresInfluencerProfile
        case athleteProfile
        case influencerProfile
        case hasAthleteProfile
        case hasInfluencerProfile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nestedIdentity = try container.decodeIfPresent(Identity.self, forKey: .identity)
        let nestedProfiles = try container.decodeIfPresent(Profiles.self, forKey: .profiles)
        let nestedOnboarding = try container.decodeIfPresent(Onboarding.self, forKey: .onboarding)

        subject = try nestedIdentity?.sub ?? (container.decodeIfPresent(String.self, forKey: .subject))
        email = try nestedIdentity?.email ?? (container.decodeIfPresent(String.self, forKey: .email))
        roles = try container.decodeIfPresent([String].self, forKey: .roles) ?? []

        athleteProfile = try nestedProfiles?.athleteProfile.data
            ?? (container.decodeIfPresent(ProfileSummary.self, forKey: .athleteProfile))
        influencerProfile = try nestedProfiles?.influencerProfile.data
            ?? (container.decodeIfPresent(ProfileSummary.self, forKey: .influencerProfile))

        let requiresAthleteExplicit = try container.decodeIfPresent(Bool.self, forKey: .requiresAthleteProfile)
        let requiresInfluencerExplicit = try container.decodeIfPresent(Bool.self, forKey: .requiresInfluencerProfile)
        let hasAthleteExplicit = try container.decodeIfPresent(Bool.self, forKey: .hasAthleteProfile)
        let hasInfluencerExplicit = try container.decodeIfPresent(Bool.self, forKey: .hasInfluencerProfile)

        let resolvedHasAthlete = nestedProfiles?.athleteProfile.exists ?? hasAthleteExplicit
            ?? (athleteProfile != nil)
        let resolvedHasInfluencer = nestedProfiles?.influencerProfile.exists ?? hasInfluencerExplicit
            ?? (influencerProfile != nil)

        requiresAthleteProfile = nestedOnboarding?
            .requiresAthleteProfile ?? requiresAthleteExplicit ?? !resolvedHasAthlete
        requiresInfluencerProfile =
            nestedOnboarding?.requiresInfluencerProfile ?? requiresInfluencerExplicit ?? !resolvedHasInfluencer
    }

    init(
        subject: String?,
        email: String?,
        roles: [String] = [],
        requiresAthleteProfile: Bool,
        requiresInfluencerProfile: Bool,
        athleteProfile: ProfileSummary?,
        influencerProfile: ProfileSummary?,
    ) {
        self.subject = subject
        self.email = email
        self.roles = roles
        self.requiresAthleteProfile = requiresAthleteProfile
        self.requiresInfluencerProfile = requiresInfluencerProfile
        self.athleteProfile = athleteProfile
        self.influencerProfile = influencerProfile
    }

    var requiredProfilesForSession: RequiredProfiles {
        let requiresAthlete = requiresAthleteProfile && allowsRole("ATHLETE")
        let requiresInfluencer = requiresInfluencerProfile && allowsRole("INFLUENCER")

        if requiresAthlete || requiresInfluencer {
            return RequiredProfiles(
                requiresAthleteProfile: requiresAthlete,
                requiresInfluencerProfile: requiresInfluencer,
            )
        }

        // If roles are missing/ambiguous, fallback to backend flags.
        return RequiredProfiles(
            requiresAthleteProfile: requiresAthleteProfile,
            requiresInfluencerProfile: requiresInfluencerProfile,
        )
    }

    private func allowsRole(_ role: String) -> Bool {
        let normalized = roles.map { $0.uppercased() }
        if normalized.isEmpty {
            return true
        }
        return normalized.contains(role) || normalized.contains("ROLE_\(role)")
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
