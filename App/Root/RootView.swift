import SwiftUI
import ComposableArchitecture

struct RootView: View {
    let store: StoreOf<RootFeature>

    var body: some View {
        Text("Fitfluence")
            .font(.title)
    }
}
