import SwiftUI

struct FFCard<Content: View>: View {
    var padding: CGFloat = FFSpacing.md
    var fillColor: Color = FFColors.surface
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fillColor)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.card, style: .continuous)
                    .stroke(FFColors.gray700.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: FFTheme.Shadow.color, radius: FFTheme.Shadow.radius, y: FFTheme.Shadow.y)
    }
}
