import SwiftUI

enum FFSelectionEmphasis {
    case primary
    case accent
    case subtleAccent

    var selectedBackground: Color {
        switch self {
        case .primary:
            FFColors.primary
        case .accent:
            FFColors.accent
        case .subtleAccent:
            FFColors.accent.opacity(0.16)
        }
    }

    var selectedForeground: Color {
        switch self {
        case .subtleAccent:
            FFColors.textPrimary
        case .primary, .accent:
            FFColors.textOnEmphasis
        }
    }

    var selectedBorder: Color {
        switch self {
        case .primary:
            FFColors.primary
        case .accent:
            FFColors.accent
        case .subtleAccent:
            FFColors.accent.opacity(0.42)
        }
    }
}

struct FFSelectableSurfaceModifier: ViewModifier {
    let isSelected: Bool
    var emphasis: FFSelectionEmphasis = .primary
    var unselectedBackground: Color = FFColors.surface
    var unselectedForeground: Color = FFColors.textPrimary
    var unselectedBorder: Color = FFColors.gray700
    var cornerRadius: CGFloat = FFTheme.Radius.control
    var lineWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isSelected ? emphasis.selectedForeground : unselectedForeground)
            .background(isSelected ? emphasis.selectedBackground : unselectedBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isSelected ? emphasis.selectedBorder : unselectedBorder, lineWidth: lineWidth)
            }
    }
}

extension View {
    func ffSelectableSurface(
        isSelected: Bool,
        emphasis: FFSelectionEmphasis = .primary,
        unselectedBackground: Color = FFColors.surface,
        unselectedForeground: Color = FFColors.textPrimary,
        unselectedBorder: Color = FFColors.gray700,
        cornerRadius: CGFloat = FFTheme.Radius.control,
        lineWidth: CGFloat = 1,
    ) -> some View {
        modifier(
            FFSelectableSurfaceModifier(
                isSelected: isSelected,
                emphasis: emphasis,
                unselectedBackground: unselectedBackground,
                unselectedForeground: unselectedForeground,
                unselectedBorder: unselectedBorder,
                cornerRadius: cornerRadius,
                lineWidth: lineWidth,
            ),
        )
    }
}
