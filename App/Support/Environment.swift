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
        let keycloakClientId = (dictionary["KeycloakClientId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawKeycloakRedirectURI = (dictionary["KeycloakRedirectURI"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let keycloakScopes = (dictionary["KeycloakScopes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let keycloakRegistrationHintMode = (dictionary["KeycloakRegistrationHintMode"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedName = (name?.isEmpty == false ? name : nil) ?? "UNKNOWN"
        let isDev = resolvedName.uppercased() == "DEV"
        let parsedBaseURL = URL(string: rawBaseURL ?? "")
        let parsedKeycloakURL = URL(string: rawKeycloakURL ?? "")

        let resolvedKeycloakURL: URL? = {
            if let parsedKeycloakURL, parsedKeycloakURL.host?.isEmpty == false {
                return parsedKeycloakURL
            }
            guard isDev, let baseHost = parsedBaseURL?.host, !baseHost.isEmpty else {
                return parsedKeycloakURL
            }

            var components = URLComponents()
            components.scheme = parsedBaseURL?.scheme ?? "http"
            components.host = baseHost
            components.port = 9990
            return components.url
        }()

        let resolvedRealm = (keycloakRealm?.isEmpty == false ? keycloakRealm : nil) ?? (isDev ? "fitfluence" : "")
        let resolvedClientId = (keycloakClientId?.isEmpty == false ? keycloakClientId : nil) ??
            (isDev ? "fitfluence-ios" : "")
        let resolvedRedirectURI = URL(string: rawKeycloakRedirectURI ?? "") ??
            (isDev ? URL(string: "fitfluence://oauth/callback") : nil)
        let resolvedScopes = (keycloakScopes?.isEmpty == false ? keycloakScopes : nil) ??
            (isDev ? "openid" : "openid profile email offline_access")

        return AppEnvironment(
            name: resolvedName,
            baseURL: parsedBaseURL,
            keycloakURL: resolvedKeycloakURL,
            keycloakRealm: resolvedRealm,
            keycloakClientId: resolvedClientId,
            keycloakRedirectURI: resolvedRedirectURI,
            keycloakScopes: resolvedScopes,
            keycloakRegistrationHintMode: (keycloakRegistrationHintMode?
                .isEmpty == false ? keycloakRegistrationHintMode : nil)
                ?? "kc_action",
        )
    }
}
