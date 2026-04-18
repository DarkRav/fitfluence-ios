import ComposableArchitecture
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

    init() {
        Self.configureNavigationBarAppearance()

        let tokenStore = KeychainTokenStore()
        let appleCredentialUserStore = KeychainAppleCredentialUserStore()
        let authBaseURL = environment.backendBaseURL ?? URL(string: "https://invalid.fitfluence.local")!
        let backendAuthClient = BackendAuthClient(baseURL: authBaseURL)

        authService = AuthService(
            tokenStore: tokenStore,
            appleCredentialUserStore: appleCredentialUserStore,
            backendAuthClient: backendAuthClient,
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

        FFLog.info("Запуск приложения в окружении: \(environment.name)")
        FFLog.info("Backend URL: \(environment.backendBaseURL?.absoluteString ?? "не задан")")
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
