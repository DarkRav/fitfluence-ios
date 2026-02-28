import Foundation

enum PreviewMocks {
    static let environment = AppEnvironment(
        name: "PREVIEW",
        baseURL: URL(string: "https://preview.fitfluence.local"),
        keycloakURL: URL(string: "https://preview-auth.fitfluence.local")
    )
}
