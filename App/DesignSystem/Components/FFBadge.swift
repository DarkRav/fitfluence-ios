import SwiftUI

struct FFBadge: View {
    enum Status {
        case draft
        case published
        case archived
        case notStarted
        case inProgress
        case completed

        var title: String {
            switch self {
            case .draft:
                "Черновик"
            case .published:
                "Опубликовано"
            case .archived:
                "В архиве"
            case .notStarted:
                "Не начата"
            case .inProgress:
                "В процессе"
            case .completed:
                "Завершена"
            }
        }

        var foreground: Color {
            switch self {
            case .draft:
                FFColors.background
            case .published:
                FFColors.textPrimary
            case .archived:
                FFColors.textSecondary
            case .notStarted:
                FFColors.textSecondary
            case .inProgress:
                FFColors.textPrimary
            case .completed:
                FFColors.background
            }
        }

        var background: Color {
            switch self {
            case .draft:
                FFColors.primary
            case .published:
                FFColors.gray100
            case .archived:
                FFColors.gray100
            case .notStarted:
                FFColors.gray100
            case .inProgress:
                FFColors.accent.opacity(0.18)
            case .completed:
                FFColors.primary
            }
        }
    }

    let status: Status

    var body: some View {
        Text(status.title)
            .font(FFTypography.caption.weight(.semibold))
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xs)
            .foregroundStyle(status.foreground)
            .background(status.background)
            .clipShape(Capsule())
    }
}
