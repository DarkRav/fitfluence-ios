import Foundation

enum PreviewMocks {
    static let environment = AppEnvironment(
        name: "PREVIEW",
        baseURL: URL(string: "https://preview.fitfluence.local"),
        keycloakURL: URL(string: "https://preview-auth.fitfluence.local"),
        keycloakRealm: "fitfluence",
        keycloakClientId: "fitfluence-ios",
        keycloakRedirectURI: URL(string: "fitfluence://oauth/callback"),
        keycloakScopes: "openid profile email offline_access",
        keycloakRegistrationHintMode: "kc_action",
    )
}
