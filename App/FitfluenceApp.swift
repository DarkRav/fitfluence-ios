import SwiftUI
import ComposableArchitecture

@main
struct FitfluenceApp: App {
    var body: some Scene {
        WindowGroup {
            RootView(
                store: Store(initialState: RootFeature.State()) {
                    RootFeature()
                }
            )
        }
    }
}
