import Foundation

struct AppEnvironment: Equatable {
    let name: String
    let baseURL: URL?
    let keycloakURL: URL?
    let keycloakRealm: String
    let keycloakClientId: String
    let keycloakRedirectURI: URL?
    let keycloakScopes: String
    let keycloakRegistrationHintMode: String

    var backendBaseURL: URL? {
        baseURL
    }

    var keycloakBaseURL: URL? {
        keycloakURL
    }

    static func from(bundle: Bundle = .main) -> AppEnvironment {
        let dictionary = bundle.infoDictionary ?? [:]
        let name = (dictionary["AppEnvironmentName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawBaseURL = (dictionary["BaseURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawKeycloakURL = (dictionary["KeycloakURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let keycloakRealm = (dictionary["KeycloakRealm"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let keycloakClientId = (dictionary["KeycloakClientId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawKeycloakRedirectURI = (dictionary["KeycloakRedirectURI"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let keycloakScopes = (dictionary["KeycloakScopes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let keycloakRegistrationHintMode = (dictionary["KeycloakRegistrationHintMode"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedName = (name?.isEmpty == false ? name : nil) ?? "UNKNOWN"

        return AppEnvironment(
            name: resolvedName,
            baseURL: URL(string: rawBaseURL ?? ""),
            keycloakURL: URL(string: rawKeycloakURL ?? ""),
            keycloakRealm: (keycloakRealm?.isEmpty == false ? keycloakRealm : nil) ?? "",
            keycloakClientId: (keycloakClientId?.isEmpty == false ? keycloakClientId : nil) ?? "",
            keycloakRedirectURI: URL(string: rawKeycloakRedirectURI ?? ""),
            keycloakScopes: (keycloakScopes?.isEmpty == false ? keycloakScopes : nil) ?? "openid profile email offline_access",
            keycloakRegistrationHintMode: (keycloakRegistrationHintMode?.isEmpty == false ? keycloakRegistrationHintMode : nil)
                ?? "kc_action",
        )
    }
}
