import SwiftUI

struct FFButton: View {
    enum Variant {
        case primary
        case secondary
        case destructive
        case disabled
    }

    let title: String
    var variant: Variant = .primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FFTypography.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .buttonStyle(FFButtonStyle(variant: variant))
        .hoverEffect(.highlight)
        .disabled(variant == .disabled)
    }
}

private struct FFButtonStyle: ButtonStyle {
    let variant: FFButton.Variant

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, FFSpacing.md)
            .background(backgroundColor(configuration: configuration))
            .foregroundStyle(foregroundColor)
            .overlay {
                if variant == .secondary {
                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                        .stroke(FFColors.accent, lineWidth: 1.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary:
            FFColors.background
        case .secondary:
            FFColors.accent
        case .destructive:
            FFColors.textPrimary
        case .disabled:
            FFColors.gray500
        }
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        switch variant {
        case .primary:
            configuration.isPressed ? FFColors.primary.opacity(0.85) : FFColors.primary
        case .secondary:
            FFColors.surface
        case .destructive:
            configuration.isPressed ? FFColors.danger.opacity(0.85) : FFColors.danger
        case .disabled:
            FFColors.gray700
        }
    }
}

#Preview {
    VStack(spacing: FFSpacing.sm) {
        FFButton(title: "Сохранить", variant: .primary) {}
        FFButton(title: "Подробнее", variant: .secondary) {}
        FFButton(title: "Удалить", variant: .destructive) {}
        FFButton(title: "Недоступно", variant: .disabled) {}
    }
    .padding()
    .background(FFColors.background)
}
