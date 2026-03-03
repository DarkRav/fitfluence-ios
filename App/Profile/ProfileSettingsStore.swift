import Foundation

protocol ProfileSettingsStore: Sendable {
    func load(userSub: String) async -> ProfileSettings
    func save(_ settings: ProfileSettings, userSub: String) async
}

actor LocalProfileSettingsStore: ProfileSettingsStore {
    private let defaults: UserDefaults
    private let keyPrefix = "fitfluence.profile.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(userSub: String) async -> ProfileSettings {
        guard
            let data = defaults.data(forKey: key(userSub: userSub)),
            let decoded = try? JSONDecoder().decode(ProfileSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    func save(_ settings: ProfileSettings, userSub: String) async {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key(userSub: userSub))
    }

    private func key(userSub: String) -> String {
        "\(keyPrefix).\(userSub)"
    }
}
