import SwiftUI

struct WorkoutOverviewHeroView: View {
    let title: String
    let subtitle: String
    let durationChipTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.md) {
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(FFColors.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(FFColors.textSecondary)
                .lineLimit(1)

            if let durationChipTitle {
                HStack(spacing: FFSpacing.sm) {
                    heroChip(title: durationChipTitle, systemImage: "clock.fill")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FFSpacing.md)
        .padding(.vertical, FFSpacing.lg)
        .background(
            LinearGradient(
                colors: [
                    FFColors.surface.opacity(0.94),
                    FFColors.surface.opacity(0.84),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(FFColors.gray700.opacity(0.42), lineWidth: 1)
        }
    }

    private func heroChip(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(FFTypography.body.weight(.semibold))
            .foregroundStyle(FFColors.textPrimary)
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.sm)
            .background(FFColors.gray700.opacity(0.72))
            .clipShape(Capsule())
    }
}

enum WorkoutExercisePickerFlow: String, Identifiable, Equatable, Sendable {
    case addAfterCurrent
    case replaceCurrent

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .addAfterCurrent:
            "Добавить упражнение"
        case .replaceCurrent:
            "Заменить упражнение"
        }
    }
}

struct WorkoutStructureActionsView: View {
    let onAddExercise: () -> Void
    let onReplaceExercise: () -> Void

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Структура тренировки")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                Text("Меняйте упражнение или добавляйте новое прямо во время сессии. Выбор идёт через существующий каталог.")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)

                HStack(spacing: FFSpacing.xs) {
                    structureButton(
                        title: "Добавить упражнение",
                        systemImage: "plus.rectangle.on.rectangle",
                        action: onAddExercise,
                    )

                    structureButton(
                        title: "Заменить текущее",
                        systemImage: "arrow.triangle.2.circlepath",
                        action: onReplaceExercise,
                    )
                }
            }
        }
    }

    private func structureButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, FFSpacing.sm)
                .background(FFColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                        .stroke(FFColors.gray700, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct WorkoutSetListActionsView: View {
    let canDuplicateLastSet: Bool
    let onAddSet: () -> Void
    let onDuplicateLastSet: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            listActionButton(
                title: "Добавить подход",
                systemImage: "plus",
                action: onAddSet,
            )

            if canDuplicateLastSet {
                listActionButton(
                    title: "Дублировать последний",
                    systemImage: "doc.on.doc",
                    action: onDuplicateLastSet,
                )
            }
        }
    }

    private func listActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            HStack(spacing: FFSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(FFTypography.body.weight(.semibold))
            }
            .foregroundStyle(FFColors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, FFSpacing.md)
            .background(FFColors.surface.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(FFColors.gray700.opacity(0.45), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct WorkoutExerciseQueueView: View {
    let items: [WorkoutPlayerViewModel.ExerciseProgressItem]
    let subtitlesByID: [String: String]
    let thumbnailURLsByID: [String: URL]
    let onSelect: (String) -> Void
    let onReplace: (String) -> Void
    let onReorder: (String, String) -> Void

    var body: some View {
        FFVerticalReorderStack(items: items, spacing: FFSpacing.lg, onReorder: onReorder) { item, isDragging in
            queueRow(
                item: item,
                index: items.firstIndex(where: { $0.id == item.id }) ?? 0,
                isDragging: isDragging
            )
        }
    }

    private func queueRow(
        item: WorkoutPlayerViewModel.ExerciseProgressItem,
        index: Int,
        isDragging: Bool = false,
    ) -> some View {
        HStack(spacing: FFSpacing.md) {
            Button {
                onSelect(item.id)
            } label: {
                HStack(spacing: FFSpacing.md) {
                    thumbnail(for: item)

                    VStack(alignment: .leading, spacing: 4) {
                        if item.isCurrent {
                            Text("ТЕКУЩЕЕ УПРАЖНЕНИЕ")
                                .font(FFTypography.caption.weight(.bold))
                                .foregroundStyle(FFColors.primary)
                        }

                        Text(item.title)
                            .font(.system(size: 18, weight: item.isCurrent ? .bold : .semibold, design: .rounded))
                            .foregroundStyle(FFColors.textPrimary)
                            .lineLimit(2)

                        Text(subtitlesByID[item.id] ?? itemSubtitle(item))
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: FFSpacing.sm)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, FFSpacing.xxs)
            }
            .buttonStyle(.plain)

            Menu {
                Button("Заменить упражнение", systemImage: "arrow.triangle.2.circlepath") {
                    onReplace(item.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(FFColors.textSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(FFColors.textSecondary)
                .frame(width: 36, height: 36)
                .background(FFColors.background.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .padding(.horizontal, FFSpacing.xs)
        .padding(.vertical, FFSpacing.xxs)
        .background(isDragging ? FFColors.surface.opacity(0.55) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func thumbnail(for item: WorkoutPlayerViewModel.ExerciseProgressItem) -> some View {
        if let url = thumbnailURLsByID[item.id] {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholderThumbnail
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            placeholderThumbnail
                .frame(width: 64, height: 64)
        }
    }

    private var placeholderThumbnail: some View {
        ZStack {
            FFColors.surface
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(FFColors.textSecondary)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func itemSubtitle(_ item: WorkoutPlayerViewModel.ExerciseProgressItem) -> String {
        if item.isSkipped {
            return "Пропущено"
        }
        return "\(item.totalSets) подходов"
    }
}

struct WorkoutPrimaryActionStrip: View {
    let secondaryTitle: String
    let primaryTitle: String
    let isSecondaryEnabled: Bool
    let isPrimaryEnabled: Bool
    let onSecondary: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: FFSpacing.sm) {
            actionButton(
                title: secondaryTitle,
                isPrimary: false,
                action: onSecondary,
            )
            .opacity(isSecondaryEnabled ? 1 : 0.55)
            .disabled(!isSecondaryEnabled)

            actionButton(
                title: primaryTitle,
                isPrimary: true,
                action: onPrimary,
            )
            .opacity(isPrimaryEnabled ? 1 : 0.55)
            .disabled(!isPrimaryEnabled)
        }
    }

    private func actionButton(
        title: String,
        isPrimary: Bool,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(FFTypography.body.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.horizontal, FFSpacing.sm)
                .ffSelectableSurface(
                    isSelected: isPrimary,
                    emphasis: .primary,
                    unselectedBorder: FFColors.gray700.opacity(0.55),
                    cornerRadius: 18,
                )
        }
        .buttonStyle(.plain)
    }
}

struct WorkoutFlowNavigationView: View {
    let progressLabel: String
    let progressSummary: String
    let items: [WorkoutPlayerViewModel.ExerciseProgressItem]
    let previousTitle: String?
    let nextTitle: String?
    let canMoveToPrevious: Bool
    let canMoveToNext: Bool
    let onPrevious: () -> Void
    let onShowAll: () -> Void
    let onNext: () -> Void
    let onJumpToExercise: (String) -> Void

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text("Маршрут тренировки")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Text(progressLabel)
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(FFColors.textSecondary)
                    Text(progressSummary)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FFSpacing.xs) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            Button {
                                onJumpToExercise(item.id)
                            } label: {
                                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                    HStack(spacing: FFSpacing.xxs) {
                                        Text("\(index + 1)")
                                            .font(FFTypography.caption.weight(.bold))
                                            .foregroundStyle(itemTint(item))
                                            .frame(width: 22, height: 22)
                                            .background(itemTint(item).opacity(0.14))
                                            .clipShape(Circle())
                                        Text(item.title)
                                            .font(FFTypography.caption.weight(.semibold))
                                            .foregroundStyle(FFColors.textPrimary)
                                            .lineLimit(1)
                                    }

                                    Text(itemSubtitle(item))
                                        .font(FFTypography.caption)
                                        .foregroundStyle(FFColors.textSecondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 176, alignment: .leading)
                                .padding(.horizontal, FFSpacing.sm)
                                .padding(.vertical, FFSpacing.sm)
                                .background(itemBackground(item))
                                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                                .overlay {
                                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                                        .stroke(itemBorder(item), lineWidth: item.isCurrent ? 1.5 : 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: FFSpacing.xs) {
                    navigationButton(
                        title: "Предыдущее",
                        subtitle: previousTitle ?? "Нет предыдущего",
                        systemImage: "chevron.left",
                        isEnabled: canMoveToPrevious,
                        action: onPrevious,
                    )

                    navigationButton(
                        title: "Список",
                        subtitle: "Все упражнения",
                        systemImage: "list.bullet",
                        isEnabled: true,
                        action: onShowAll,
                    )

                    navigationButton(
                        title: "Следующее",
                        subtitle: nextTitle ?? "Финиш тренировки",
                        systemImage: "chevron.right",
                        isEnabled: canMoveToNext,
                        action: onNext,
                    )
                }
            }
        }
    }

    private func navigationButton(
        title: String,
        subtitle: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void,
    ) -> some View {
        FFCompactActionButton(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            alignment: .leading,
            isEnabled: isEnabled,
            action: action,
        )
    }

    private func itemSubtitle(_ item: WorkoutPlayerViewModel.ExerciseProgressItem) -> String {
        if item.isSkipped {
            return "Пропущено"
        }
        if item.completedSets >= item.totalSets, item.totalSets > 0 {
            return "Завершено"
        }
        return "\(item.completedSets) из \(item.totalSets) подходов"
    }

    private func itemTint(_ item: WorkoutPlayerViewModel.ExerciseProgressItem) -> Color {
        if item.isCurrent {
            return FFColors.accent
        }
        if item.isSkipped {
            return FFColors.danger
        }
        if item.completedSets >= item.totalSets, item.totalSets > 0 {
            return FFColors.primary
        }
        return FFColors.textSecondary
    }

    private func itemBackground(_ item: WorkoutPlayerViewModel.ExerciseProgressItem) -> Color {
        if item.isCurrent {
            return FFColors.accent.opacity(0.08)
        }
        if item.isSkipped {
            return FFColors.danger.opacity(0.08)
        }
        return FFColors.background.opacity(0.4)
    }

    private func itemBorder(_ item: WorkoutPlayerViewModel.ExerciseProgressItem) -> Color {
        if item.isCurrent {
            return FFColors.accent.opacity(0.5)
        }
        if item.isSkipped {
            return FFColors.danger.opacity(0.38)
        }
        return FFColors.gray700
    }
}

struct WorkoutRestTimerControlsView: View {
    let title: String
    let detail: String
    let remainingSeconds: Int
    let isRunning: Bool
    @Binding var isExpanded: Bool
    let presetSeconds: [Int]
    let onPauseResume: () -> Void
    let onSkip: () -> Void
    let onAddTime: (Int) -> Void
    let onReset: () -> Void
    let onRestartWithPreset: (Int) -> Void

    var body: some View {
        VStack(spacing: FFSpacing.xs) {
            FFCard(padding: FFSpacing.sm) {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    HStack(spacing: FFSpacing.sm) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: FFSpacing.xxs) {
                                Image(systemName: "timer")
                                Text(title)
                            }
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: FFSpacing.xs)

                        Text(formattedTime(remainingSeconds))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(FFColors.textPrimary)

                        miniAction(title: "+15") { onAddTime(15) }
                        miniAction(title: isRunning ? "Пауза" : "Старт") { onPauseResume() }
                        miniAction(title: "Скип") { onSkip() }
                    }

                    Text(detail)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                        .lineLimit(1)

                    if isExpanded {
                        HStack(spacing: FFSpacing.xs) {
                            ForEach(presetSeconds, id: \.self) { value in
                                timerChip(title: formattedPreset(value)) {
                                    onRestartWithPreset(value)
                                }
                            }
                            timerChip(title: "Сброс", action: onReset)
                            Spacer(minLength: 0)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.top, FFSpacing.xs)
        .background(Color.clear)
    }

    private func miniAction(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, FFSpacing.xs)
                .frame(minHeight: 30)
                .background(FFColors.surface)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(FFColors.gray700.opacity(0.5), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func timerChip(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .padding(.horizontal, FFSpacing.sm)
                .frame(minHeight: 34)
                .background(FFColors.surface)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(FFColors.gray700, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func formattedPreset(_ seconds: Int) -> String {
        "\(seconds) сек"
    }

    private func formattedTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct WorkoutRestReadyView: View {
    let title: String
    let detail: String
    let presetSeconds: [Int]
    let onAddTime: (Int) -> Void
    let onDismiss: () -> Void

    var body: some View {
        FFCard(padding: FFSpacing.sm) {
            HStack(spacing: FFSpacing.sm) {
                Label(title, systemImage: "checkmark.circle")
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.textPrimary)

                Spacer(minLength: FFSpacing.xs)

                ForEach(presetSeconds, id: \.self) { value in
                    Button {
                        onAddTime(value)
                    } label: {
                        Text("+\(value)")
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                            .padding(.horizontal, FFSpacing.sm)
                            .frame(minHeight: 30)
                            .background(FFColors.surface)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(FFColors.gray700.opacity(0.5), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }

                Button("Скрыть", action: onDismiss)
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.textSecondary)
            }

            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                Text(detail)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.top, FFSpacing.xs)
        .background(Color.clear)
    }
}
