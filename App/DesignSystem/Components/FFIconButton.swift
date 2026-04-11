import SwiftUI

struct FFIconButton: View {
    enum Style {
        case ghost
        case outlined
        case tonal(Color)
    }

    let systemName: String
    var tint: Color = FFColors.textSecondary
    var size: CGFloat = 32
    var cornerRadius: CGFloat = FFTheme.Radius.control
    var font: Font = .system(size: 14, weight: .semibold)
    var style: Style = .outlined
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(font)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(background)
                .clipShape(shape)
                .overlay {
                    if let border {
                        shape.stroke(border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        switch style {
        case .ghost:
            .clear
        case .outlined:
            FFColors.surface
        case let .tonal(color):
            color.opacity(0.12)
        }
    }

    private var border: Color? {
        switch style {
        case .ghost:
            nil
        case .outlined:
            FFColors.gray700
        case .tonal:
            nil
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}
