import SwiftUI

struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(isEnabled ? FFColors.textSecondary : FFColors.gray500)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isEnabled ? FFColors.textPrimary : FFColors.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(FFColors.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 104, maxHeight: 104, alignment: .topLeading)
            .padding(12)
            .background(FFColors.gray700.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(FFColors.gray500.opacity(0.4), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
    }
}
