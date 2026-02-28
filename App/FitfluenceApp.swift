import ComposableArchitecture
import SwiftUI

@main
struct FitfluenceApp: App {
    private let environment = AppEnvironment.from()
    private let apiClient: APIClient?

    init() {
        apiClient = APIClient.live(environment: environment)
        FFLog.info("Запуск приложения в окружении: \(environment.name)")
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                store: Store(initialState: RootFeature.State()) {
                    RootFeature(apiClient: apiClient)
                },
                environment: environment,
            )
        }
    }
}
