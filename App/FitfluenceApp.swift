import ComposableArchitecture
import SwiftUI

@main
struct FitfluenceApp: App {
    private let environment = AppEnvironment.from()
    private let authService: AuthService
    private let apiClient: APIClient?
    private let sessionManager: SessionManaging

    init() {
        let tokenStore = KeychainTokenStore()

        let keycloakBaseURL = environment.keycloakBaseURL ?? URL(string: "http://localhost:9990")!
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

        FFLog.info("Запуск приложения в окружении: \(environment.name)")
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                store: Store(initialState: RootFeature.State()) {
                    RootFeature(
                        sessionManager: sessionManager,
                        authService: authService,
                        apiClient: apiClient,
                    )
                },
                environment: environment,
            )
        }
    }
}
