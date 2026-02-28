import ComposableArchitecture
import Network
import SwiftUI

@main
struct FitfluenceApp: App {
    private let environment = AppEnvironment.from()
    private let authService: AuthService
    private let apiClient: APIClient?
    private let sessionManager: SessionManaging
    private let networkMonitor: NetworkMonitoring
    private let cacheStore: CacheStore
    private let localNetworkProbe: LocalNetworkProbe?

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
        cacheStore = CompositeCacheStore()
        if environment.name.uppercased() == "DEV" {
            let probe = LocalNetworkProbe()
            probe.start()
            localNetworkProbe = probe
        } else {
            localNetworkProbe = nil
        }

        FFLog.info("Запуск приложения в окружении: \(environment.name)")
        FFLog.info("Backend URL: \(environment.backendBaseURL?.absoluteString ?? "не задан")")
        FFLog.info("Keycloak URL: \(environment.keycloakBaseURL?.absoluteString ?? "не задан")")
        FFLog.info("Keycloak realm: \(environment.keycloakRealm)")
        FFLog.info("Keycloak clientId: \(environment.keycloakClientId)")
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                store: Store(initialState: RootFeature.State()) {
                    RootFeature(
                        sessionManager: sessionManager,
                        authService: authService,
                        apiClient: apiClient,
                        cacheStore: cacheStore,
                        networkMonitor: networkMonitor,
                    )
                },
                environment: environment,
            )
        }
    }
}

private final class LocalNetworkProbe {
    private var browser: NWBrowser?

    func start() {
        let parameters = NWParameters()
        let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: parameters)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                FFLog.info("Local network probe ready")
            case let .waiting(error):
                FFLog.error("Local network probe waiting: \(error)")
            case let .failed(error):
                FFLog.error("Local network probe failed: \(error)")
                self?.stop()
            default:
                break
            }
        }

        browser.browseResultsChangedHandler = { _, _ in }
        browser.start(queue: .main)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.stop()
        }
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}
