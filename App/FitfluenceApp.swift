import SwiftUI
import ComposableArchitecture

@main
struct FitfluenceApp: App {
    private let environment = AppEnvironment.from()

    init() {
        FFLog.info("Запуск приложения в окружении: \(environment.name)")
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                store: Store(initialState: RootFeature.State()) {
                    RootFeature()
                },
                environment: environment
            )
        }
    }
}
