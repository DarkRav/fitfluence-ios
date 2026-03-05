import SwiftUI

struct WorkoutPrimaryButton: View {
    let title: String
    var isLoading = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: FFSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .tint(FFColors.background)
                        .controlSize(.small)
                }

                Text(title)
                    .font(.headline)
                    .lineLimit(1)
            }
            .foregroundStyle(FFColors.background)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .padding(.horizontal, 16)
            .background(FFColors.primary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

struct WorkoutSecondaryButton: View {
    let title: String
    var height: CGFloat = 44
    var cornerRadius: CGFloat = 14
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(FFColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(FFColors.gray700)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(FFColors.gray500.opacity(0.45), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }
}
