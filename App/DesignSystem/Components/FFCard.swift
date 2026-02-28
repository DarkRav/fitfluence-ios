import SwiftUI

struct FFCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(FFSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FFColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.card))
            .shadow(color: FFTheme.Shadow.color, radius: FFTheme.Shadow.radius, y: FFTheme.Shadow.y)
    }
}
