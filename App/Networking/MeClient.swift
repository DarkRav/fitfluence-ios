import Foundation

struct MeResponse: Decodable, Equatable, Sendable {
    struct ProfileSummary: Decodable, Equatable, Sendable {
        let id: String?

        enum CodingKeys: String, CodingKey {
            case id
            case userId
        }

        init(from decoder: Decoder) throws {
            if let singleContainer = try? decoder.singleValueContainer() {
                if let value = try? singleContainer.decode(String.self) {
                    id = value
                    return
                }
                if let value = try? singleContainer.decode(UUID.self) {
                    id = value.uuidString
                    return
                }
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            let idValue = Self.decodeString(from: container, key: .id)
            let userIDValue = Self.decodeString(from: container, key: .userId)
            let idUUIDValue = Self.decodeUUIDString(from: container, key: .id)
            let userIDUUIDValue = Self.decodeUUIDString(from: container, key: .userId)
            id = idValue ?? userIDValue ?? idUUIDValue ?? userIDUUIDValue
        }

        init(id: String?) {
            self.id = id
        }

        private static func decodeString(
            from container: KeyedDecodingContainer<CodingKeys>,
            key: CodingKeys,
        ) -> String? {
            (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
        }

        private static func decodeUUIDString(
            from container: KeyedDecodingContainer<CodingKeys>,
            key: CodingKeys,
        ) -> String? {
            (try? container.decodeIfPresent(UUID.self, forKey: key))?.uuidString
        }
    }

    struct Identity: Decodable, Equatable, Sendable {
        let sub: String?
        let email: String?
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case sub
            case userId
            case id
            case email
            case username
            case displayName
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let subValue = (try? container.decodeIfPresent(String.self, forKey: .sub)) ?? nil
            let userIDValue = (try? container.decodeIfPresent(String.self, forKey: .userId)) ?? nil
            let idValue = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? nil
            let userIDUUID = (try? container.decodeIfPresent(UUID.self, forKey: .userId))?.uuidString
            let idUUID = (try? container.decodeIfPresent(UUID.self, forKey: .id))?.uuidString

            sub = subValue ?? userIDValue ?? idValue ?? userIDUUID ?? idUUID
            email = (try? container.decodeIfPresent(String.self, forKey: .email))
                ?? (try? container.decodeIfPresent(String.self, forKey: .username))
            displayName = (try? container.decodeIfPresent(String.self, forKey: .displayName)) ?? nil
        }
    }

    struct ProfileState: Decodable, Equatable, Sendable {
        let exists: Bool
        let data: ProfileSummary?

        enum CodingKeys: String, CodingKey {
            case exists
            case data
            case profile
            case value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let dataValue = (try? container.decodeIfPresent(ProfileSummary.self, forKey: .data)) ?? nil
            let profileValue = (try? container.decodeIfPresent(ProfileSummary.self, forKey: .profile)) ?? nil
            let fallbackValue = (try? container.decodeIfPresent(ProfileSummary.self, forKey: .value)) ?? nil
            let decodedData = dataValue ?? profileValue ?? fallbackValue

            data = decodedData
            exists = MeResponse.decodeBool(from: container, key: .exists) ?? (decodedData != nil)
        }

        init(exists: Bool, data: ProfileSummary?) {
            self.exists = exists
            self.data = data
        }
    }

    struct Profiles: Decodable, Equatable, Sendable {
        let athleteProfile: ProfileState
        let influencerProfile: ProfileState

        enum CodingKeys: String, CodingKey {
            case athleteProfile
            case influencerProfile
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            athleteProfile = (try? container.decode(ProfileState.self, forKey: .athleteProfile))
                ?? ProfileState(exists: false, data: nil)
            influencerProfile = (try? container.decode(ProfileState.self, forKey: .influencerProfile))
                ?? ProfileState(exists: false, data: nil)
        }
    }

    struct Onboarding: Decodable, Equatable, Sendable {
        let requiresAthleteProfile: Bool
        let requiresInfluencerProfile: Bool

        enum CodingKeys: String, CodingKey {
            case requiresAthleteProfile
            case requiresInfluencerProfile
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            requiresAthleteProfile =
                MeResponse.decodeBool(from: container, key: .requiresAthleteProfile) ?? false
            requiresInfluencerProfile =
                MeResponse.decodeBool(from: container, key: .requiresInfluencerProfile) ?? false
        }
    }

    let subject: String?
    let email: String?
    let displayName: String?
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
        case displayName
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
        let nestedIdentity = try? container.decodeIfPresent(Identity.self, forKey: .identity)
        let nestedProfiles = try? container.decodeIfPresent(Profiles.self, forKey: .profiles)
        let nestedOnboarding = try? container.decodeIfPresent(Onboarding.self, forKey: .onboarding)

        let subjectValue = (try? container.decodeIfPresent(String.self, forKey: .subject)) ?? nil
        let emailValue = (try? container.decodeIfPresent(String.self, forKey: .email)) ?? nil
        let displayNameValue = (try? container.decodeIfPresent(String.self, forKey: .displayName)) ?? nil

        subject = nestedIdentity?.sub ?? subjectValue
        email = nestedIdentity?.email ?? emailValue
        displayName = nestedIdentity?.displayName ?? displayNameValue
        roles = Self.decodeRoles(from: container)

        let athleteProfileValue =
            (try? container.decodeIfPresent(ProfileSummary.self, forKey: .athleteProfile)) ?? nil
        let influencerProfileValue =
            (try? container.decodeIfPresent(ProfileSummary.self, forKey: .influencerProfile)) ?? nil

        athleteProfile = nestedProfiles?.athleteProfile.data ?? athleteProfileValue
        influencerProfile = nestedProfiles?.influencerProfile.data ?? influencerProfileValue

        let requiresAthleteExplicit = Self.decodeBool(from: container, key: .requiresAthleteProfile)
        let requiresInfluencerExplicit = Self.decodeBool(from: container, key: .requiresInfluencerProfile)
        let hasAthleteExplicit = Self.decodeBool(from: container, key: .hasAthleteProfile)
        let hasInfluencerExplicit = Self.decodeBool(from: container, key: .hasInfluencerProfile)

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
        displayName: String? = nil,
        roles: [String] = [],
        requiresAthleteProfile: Bool,
        requiresInfluencerProfile: Bool,
        athleteProfile: ProfileSummary?,
        influencerProfile: ProfileSummary?,
    ) {
        self.subject = subject
        self.email = email
        self.displayName = displayName
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

    private static func decodeRoles(
        from container: KeyedDecodingContainer<CodingKeys>,
    ) -> [String] {
        if let decoded = try? container.decodeIfPresent([String].self, forKey: .roles) {
            return decoded
        }
        let single = (try? container.decodeIfPresent(String.self, forKey: .roles)) ?? nil
        if let value = single {
            return [value]
        }
        return []
    }

    private static func decodeBool<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        key: Key,
    ) -> Bool? {
        let boolValue = (try? container.decodeIfPresent(Bool.self, forKey: key)) ?? nil
        if let value = boolValue {
            return value
        }
        let intValue = (try? container.decodeIfPresent(Int.self, forKey: key)) ?? nil
        if let value = intValue {
            return value != 0
        }
        let stringValue = (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
        if let value = stringValue {
            switch value.lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
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

protocol AccountDeletionClientProtocol: Sendable {
    func deleteAccount() async -> Result<Void, APIError>
}

struct UnavailableMeClient: MeClientProtocol {
    func me() async -> Result<MeResponse, APIError> {
        .failure(.invalidURL)
    }
}

struct UnavailableAccountDeletionClient: AccountDeletionClientProtocol {
    func deleteAccount() async -> Result<Void, APIError> {
        .failure(.invalidURL)
    }
}
