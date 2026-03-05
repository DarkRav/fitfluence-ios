import SwiftUI

struct WorkoutPrimaryButton: View {
    let title: String
    var isLoading = false
    var action: () -> Void

    var body: some View {
        FFButton(
            title: title,
            variant: .primary,
            isLoading: isLoading,
            action: action,
        )
    }
}

struct WorkoutSecondaryButton: View {
    let title: String
    var height: CGFloat = 44
    var cornerRadius: CGFloat = 14
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        FFButton(
            title: title,
            variant: isEnabled ? .secondary : .disabled,
            action: action,
        )
        .frame(minHeight: max(height, 52))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .opacity(isEnabled ? 1 : 0.55)
    }
}
