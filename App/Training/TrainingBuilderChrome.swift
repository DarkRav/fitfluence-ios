import SwiftUI

struct TrainingBuilderHeroCard: View {
    let eyebrow: String?
    let title: String
    let subtitle: String
    var badges: [String] = []
    var accentFill: Color = FFColors.accent.opacity(0.08)

    var body: some View {
        FFCard(padding: FFSpacing.sm, fillColor: accentFill) {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                if let eyebrow, !eyebrow.isEmpty {
                    Text(eyebrow.uppercased())
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(FFColors.accent)
                }

                Text(title)
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }

                if !badges.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: FFSpacing.xs) {
                            ForEach(badges, id: \.self) { badge in
                                TrainingBuilderBadge(title: badge)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct TrainingBuilderSectionCard<Content: View>: View {
    let eyebrow: String?
    let title: String
    let helper: String
    @ViewBuilder let content: Content

    var body: some View {
        FFCard(padding: FFSpacing.sm) {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    if let eyebrow, !eyebrow.isEmpty {
                        Text(eyebrow.uppercased())
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.accent)
                    }
                    Text(title)
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    if !helper.isEmpty {
                        Text(helper)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }
                content
            }
        }
    }
}

struct TrainingBuilderChoiceTile: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    var alignment: Alignment = .leading
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FFTypography.body.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(FFTypography.caption)
                        .lineLimit(2)
                }
            }
            .foregroundStyle(isSelected ? FFColors.background : FFColors.textPrimary)
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: alignment)
            .background(isSelected ? FFColors.primary : FFColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                    .stroke(isSelected ? FFColors.primary : FFColors.gray700, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct TrainingBuilderBadge: View {
    let title: String
    var isAccent: Bool = false

    var body: some View {
        Text(title)
            .font(FFTypography.caption.weight(.semibold))
            .foregroundStyle(isAccent ? FFColors.background : FFColors.textSecondary)
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xs)
            .background(isAccent ? FFColors.accent : FFColors.surface)
            .clipShape(Capsule())
            .overlay {
                if !isAccent {
                    Capsule()
                        .stroke(FFColors.gray700.opacity(0.8), lineWidth: 1)
                }
            }
    }
}

struct TrainingBuilderBottomBar: View {
    let helper: String
    let title: String
    let summary: String?
    var buttonVariant: FFButton.Variant = .primary
    var isLoading = false
    var action: () -> Void

    var body: some View {
        VStack(spacing: FFSpacing.xs) {
            if let summary {
                Text(summary)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(helper)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            FFButton(title: title, variant: buttonVariant, isLoading: isLoading, action: action)
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.top, 6)
        .padding(.bottom, FFSpacing.xs)
        .background(FFColors.background.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FFColors.gray700.opacity(0.6))
                .frame(height: 1)
        }
    }
}
