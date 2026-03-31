import ComposableArchitecture
import Network
import SwiftUI
import UIKit

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
        Self.configureNavigationBarAppearance()

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

        let syncClient: AthleteTrainingClientProtocol? = apiClient
        let syncNetworkMonitor = networkMonitor
        Task {
            await SyncCoordinator.shared.configure(
                athleteTrainingClient: syncClient,
                networkMonitor: syncNetworkMonitor,
            )
        }

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

    private static func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(FFColors.background)
        appearance.shadowColor = UIColor(FFColors.gray700)
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(FFColors.textPrimary),
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(FFColors.textPrimary),
        ]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
        navigationBar.tintColor = UIColor(FFColors.accent)

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(FFColors.surface)
        tabBarAppearance.shadowColor = UIColor(FFColors.gray700)

        let normalColor = UIColor(FFColors.textSecondary)
        let selectedColor = UIColor(FFColors.textPrimary)

        for layoutAppearance in [
            tabBarAppearance.stackedLayoutAppearance,
            tabBarAppearance.inlineLayoutAppearance,
            tabBarAppearance.compactInlineLayoutAppearance,
        ] {
            layoutAppearance.normal.iconColor = normalColor
            layoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
            layoutAppearance.selected.iconColor = selectedColor
            layoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        }

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tabBarAppearance
        tabBar.scrollEdgeAppearance = tabBarAppearance
        tabBar.tintColor = selectedColor
        tabBar.unselectedItemTintColor = normalColor
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
                apiClient: apiClient,
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
