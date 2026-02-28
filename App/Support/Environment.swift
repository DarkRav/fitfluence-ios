import Foundation

struct AppEnvironment: Equatable {
    let name: String
    let baseURL: URL?
    let keycloakURL: URL?

    static func from(bundle: Bundle = .main) -> AppEnvironment {
        let dictionary = bundle.infoDictionary ?? [:]
        let name = (dictionary["AppEnvironmentName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawBaseURL = (dictionary["BaseURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawKeycloakURL = (dictionary["KeycloakURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedName = (name?.isEmpty == false ? name : nil) ?? "UNKNOWN"

        return AppEnvironment(
            name: resolvedName,
            baseURL: URL(string: rawBaseURL ?? ""),
            keycloakURL: URL(string: rawKeycloakURL ?? ""),
        )
    }
}
