import SwiftUI

struct FFBadge: View {
    enum Status {
        case draft
        case published
        case archived

        var title: String {
            switch self {
            case .draft:
                "Черновик"
            case .published:
                "Опубликовано"
            case .archived:
                "В архиве"
            }
        }

        var foreground: Color {
            switch self {
            case .draft:
                FFColors.background
            case .published:
                FFColors.accent
            case .archived:
                FFColors.gray300
            }
        }

        var background: Color {
            switch self {
            case .draft:
                FFColors.primary
            case .published:
                FFColors.accent.opacity(0.18)
            case .archived:
                FFColors.gray700
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
