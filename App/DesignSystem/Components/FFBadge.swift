import SwiftUI

struct FFBadge: View {
    enum Status {
        case draft
        case published
        case archived

        var title: String {
            switch self {
            case .draft:
                return "Черновик"
            case .published:
                return "Опубликовано"
            case .archived:
                return "В архиве"
            }
        }

        var foreground: Color {
            switch self {
            case .draft:
                return FFColors.background
            case .published:
                return FFColors.accent
            case .archived:
                return FFColors.gray300
            }
        }

        var background: Color {
            switch self {
            case .draft:
                return FFColors.primary
            case .published:
                return FFColors.accent.opacity(0.18)
            case .archived:
                return FFColors.gray700
            }
        }
    }

    let status: Status

    var body: some View {
        Text(status.title)
            .font(FFTypography.caption)
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xs)
            .foregroundStyle(status.foreground)
            .background(status.background)
            .clipShape(Capsule())
    }
}
