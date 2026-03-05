import SwiftUI

struct RecentWorkoutRow: View {
    let title: String
    let dateText: String

    var body: some View {
        HStack(spacing: FFSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)
                    .lineLimit(2)

                Text(dateText)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
            }

            Spacer(minLength: FFSpacing.xs)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FFColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
