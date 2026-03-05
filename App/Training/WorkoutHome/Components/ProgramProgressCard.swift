import SwiftUI

struct ProgramProgressCard: View {
    let programTitle: String
    let detailsLine: String
    let progressText: String
    let progressValue: Double
    let isCompleted: Bool
    var isActionEnabled = true
    let onAction: () -> Void

    var body: some View {
        WorkoutCardContainer(cornerRadius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Прогресс программы")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)

                Text(programTitle)
                    .font(FFTypography.body.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)
                    .lineLimit(2)

                Text(detailsLine)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                    .lineLimit(1)

                Text(progressText)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)

                ProgramProgressBar(value: progressValue)
                    .padding(.top, 12)

                if isCompleted {
                    Text("Программа завершена")
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(FFColors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(FFColors.gray700.opacity(0.7))
                        .clipShape(Capsule())
                }

                WorkoutSecondaryButton(
                    title: isCompleted ? "Выбрать следующую программу" : "Продолжить программу",
                    height: 48,
                    cornerRadius: 16,
                    isEnabled: isActionEnabled,
                    action: onAction,
                )
            }
        }
    }
}

private struct ProgramProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(FFColors.gray700)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(FFColors.accent)
                    .frame(width: max(8, proxy.size.width * normalizedValue))
            }
        }
        .frame(height: 8)
    }

    private var normalizedValue: Double {
        min(max(value, 0), 1)
    }
}
