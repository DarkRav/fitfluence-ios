import SwiftUI
import ComposableArchitecture

struct RootView: View {
    let store: StoreOf<RootFeature>

    var body: some View {
        Text("Fitfluence")
            .font(FFTypography.h1)
            .foregroundStyle(FFColors.textPrimary)
            .padding(FFSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FFColors.background)
    }
}
