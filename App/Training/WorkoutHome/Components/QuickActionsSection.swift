import SwiftUI

struct QuickActionsSection: View {
    let onOpenTemplates: () -> Void

    var body: some View {
        WorkoutCardContainer(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Шаблоны")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)

                Button(action: onOpenTemplates) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Открыть шаблоны")
                            .font(FFTypography.caption.weight(.semibold))
                        Spacer()
                        Text("Готовые заготовки")
                            .font(FFTypography.caption)
                    }
                    .foregroundStyle(FFColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
