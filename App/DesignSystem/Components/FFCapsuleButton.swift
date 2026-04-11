import SwiftUI

struct FFCapsuleButton: View {
    enum Style {
        case filled(Color)
        case subtle(Color)
    }

    let title: String
    var style: Style = .filled(FFColors.gray700)
    var foreground: Color? = nil
    var minHeight: CGFloat = 36
    var horizontalPadding: CGFloat = FFSpacing.xs
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FFTypography.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(resolvedForeground)
                .padding(.horizontal, horizontalPadding)
                .frame(minHeight: minHeight)
                .background(background)
                .clipShape(Capsule())
                .overlay {
                    if let border {
                        Capsule()
                            .stroke(border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var resolvedForeground: Color {
        if let foreground {
            return foreground
        }
        switch style {
        case .filled:
            return FFColors.textOnEmphasis
        case .subtle:
            return FFColors.textPrimary
        }
    }

    private var background: Color {
        switch style {
        case let .filled(color):
            color
        case let .subtle(color):
            color.opacity(0.12)
        }
    }

    private var border: Color? {
        switch style {
        case .filled:
            nil
        case let .subtle(color):
            color.opacity(0.28)
        }
    }
}
