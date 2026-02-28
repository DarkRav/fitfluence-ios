import SwiftUI

struct FFTextField: View {
    enum FieldState: Equatable {
        case normal
        case focused
        case error(String)
        case disabled
    }

    let label: String
    let placeholder: String
    @Binding var text: String
    var helperText: String?
    var state: FieldState = .normal

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            Text(label)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)

            TextField(placeholder, text: $text)
                .font(FFTypography.body)
                .foregroundStyle(FFColors.textPrimary)
                .padding(.horizontal, FFSpacing.md)
                .frame(minHeight: 44)
                .background(FFColors.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                        .stroke(borderColor, lineWidth: borderWidth)
                }
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                .focused($isFocused)
                .disabled(state == .disabled)

            if let statusText {
                Text(statusText)
                    .font(FFTypography.caption)
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var borderColor: Color {
        switch resolvedState {
        case .normal:
            return FFColors.gray700
        case .focused:
            return FFColors.accent
        case .error:
            return FFColors.danger
        case .disabled:
            return FFColors.gray500
        }
    }

    private var borderWidth: CGFloat {
        resolvedState == .focused ? 2 : 1
    }

    private var statusText: String? {
        switch state {
        case .error(let message):
            return message
        case .normal, .focused, .disabled:
            return helperText
        }
    }

    private var statusColor: Color {
        if case .error = state {
            return FFColors.danger
        }
        return FFColors.textSecondary
    }

    private var resolvedState: FieldState {
        if case .disabled = state {
            return .disabled
        }
        if case .error = state {
            return state
        }
        return isFocused ? .focused : .normal
    }
}
