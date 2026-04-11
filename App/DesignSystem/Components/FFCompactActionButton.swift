import SwiftUI

struct FFCompactActionButton: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var alignment: Alignment = .center
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: horizontalAlignment, spacing: 2) {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                        .font(FFTypography.caption.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(textAlignment)
                        .minimumScaleFactor(0.8)
                } else {
                    Text(title)
                        .font(FFTypography.caption.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(textAlignment)
                        .minimumScaleFactor(0.8)
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(FFColors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(textAlignment)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(isEnabled ? FFColors.textPrimary : FFColors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: alignment)
            .padding(.horizontal, FFSpacing.sm)
            .background(isEnabled ? FFColors.surface : FFColors.background.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control, style: .continuous)
                    .stroke(FFColors.gray700, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var horizontalAlignment: HorizontalAlignment {
        switch alignment {
        case .leading, .topLeading, .bottomLeading:
            .leading
        case .trailing, .topTrailing, .bottomTrailing:
            .trailing
        default:
            .center
        }
    }

    private var textAlignment: TextAlignment {
        switch alignment {
        case .leading, .topLeading, .bottomLeading:
            .leading
        case .trailing, .topTrailing, .bottomTrailing:
            .trailing
        default:
            .center
        }
    }
}
