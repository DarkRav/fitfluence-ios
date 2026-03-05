import SwiftUI

struct ProgramProgressCard: View {
    let programTitle: String
    let detailsLine: String
    let progressText: String
    let progressValue: Double
    let isCompleted: Bool
    var isActionEnabled = true
    let onAction: () -> Void
    let onOpenHistory: () -> Void

    var body: some View {
        WorkoutCardContainer(cornerRadius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: onOpenHistory) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Прогресс программы")
                            .font(FFTypography.body.weight(.semibold))
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
                            Text("✓ Завершено")
                                .font(FFTypography.caption.weight(.semibold))
                                .foregroundStyle(FFColors.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(FFColors.gray700.opacity(0.65))
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                FFButton(
                    title: isCompleted ? "Выбрать следующую программу" : "Продолжить программу",
                    variant: isActionEnabled ? .secondary : .disabled,
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
                    .fill(FFColors.gray700.opacity(0.9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(FFColors.gray500.opacity(0.24), lineWidth: 0.6)
                    }

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
