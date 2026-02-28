import ComposableArchitecture
import SwiftUI

@main
struct FitfluenceApp: App {
    private let environment = AppEnvironment.from()
    private let authService: AuthService
    private let apiClient: APIClient?
    private let sessionManager: SessionManaging
    private let networkMonitor: NetworkMonitoring

    init() {
        let tokenStore = KeychainTokenStore()

        let keycloakBaseURL = environment.keycloakBaseURL ?? URL(string: "https://invalid.fitfluence.local")!
        let discoveryService = OIDCDiscoveryService(
            baseURL: keycloakBaseURL,
            realm: environment.keycloakRealm,
            session: .shared,
        )

        authService = AuthService(
            environment: environment,
            discoveryService: discoveryService,
            tokenStore: tokenStore,
        )

        let tokenProvider = StoredAuthTokenProvider(tokenStore: tokenStore)
        apiClient = APIClient.live(
            environment: environment,
            session: .shared,
            tokenProvider: tokenProvider,
            authService: authService,
        )

        sessionManager = SessionManager(
            authService: authService,
            meClient: apiClient ?? UnavailableMeClient(),
        )
        networkMonitor = NetworkMonitor()

        FFLog.info("Запуск приложения в окружении: \(environment.name)")
        FFLog.info("Backend URL: \(environment.backendBaseURL?.absoluteString ?? "не задан")")
        FFLog.info("Keycloak URL: \(environment.keycloakBaseURL?.absoluteString ?? "не задан")")
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                store: Store(initialState: RootFeature.State()) {
                    RootFeature(
                        sessionManager: sessionManager,
                        authService: authService,
                        apiClient: apiClient,
                        networkMonitor: networkMonitor,
                    )
                },
                environment: environment,
            )
        }
    }
}
