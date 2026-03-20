import SwiftUI

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
        HStack(spacing: FFSpacing.xs) {
            listActionButton(
                title: "Добавить подход",
                systemImage: "plus.circle",
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
            Label(title, systemImage: systemImage)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, FFSpacing.sm)
                .background(FFColors.background.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                        .stroke(FFColors.gray700, lineWidth: 1)
                }
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
        Button(action: action) {
            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                Label(title, systemImage: systemImage)
                    .font(FFTypography.caption.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(FFTypography.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isEnabled ? FFColors.textPrimary : FFColors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(.horizontal, FFSpacing.sm)
            .background(isEnabled ? FFColors.surface : FFColors.background.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                    .stroke(FFColors.gray700, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
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
        FFCard(padding: FFSpacing.sm) {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                ViewThatFits(in: .horizontal) {
                    regularHeaderRow
                    compactHeaderLayout
                }

                Text(detail)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)

                if isExpanded {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Быстрый отдых")
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.textSecondary)

                        HStack(spacing: FFSpacing.xs) {
                            ForEach(presetSeconds, id: \.self) { value in
                                timerChip(title: formattedPreset(value)) {
                                    onRestartWithPreset(value)
                                }
                            }
                        }

                        HStack(spacing: FFSpacing.xs) {
                            timerChip(title: "+15") { onAddTime(15) }
                            timerChip(title: "+30") { onAddTime(30) }
                            timerChip(title: "+60") { onAddTime(60) }
                            timerChip(title: "Сброс", action: onReset)
                            Spacer(minLength: 0)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.top, FFSpacing.xs)
        .background(FFColors.background.opacity(0.96))
    }

    private var regularHeaderRow: some View {
        HStack(spacing: FFSpacing.xs) {
            headerText

            Spacer(minLength: FFSpacing.xs)

            timeValue

            capsuleButton(title: isRunning ? "Пауза" : "Продолжить", tint: FFColors.gray700, action: onPauseResume)
            capsuleButton(title: "Пропустить", tint: FFColors.danger, action: onSkip)
            expandButton
        }
    }

    private var compactHeaderLayout: some View {
        VStack(spacing: FFSpacing.xs) {
            HStack(spacing: FFSpacing.xs) {
                headerText
                Spacer(minLength: FFSpacing.xs)
                timeValue
                expandButton
            }

            HStack(spacing: FFSpacing.xs) {
                capsuleButton(title: isRunning ? "Пауза" : "Продолжить", tint: FFColors.gray700, action: onPauseResume)
                capsuleButton(title: "Пропустить", tint: FFColors.danger, action: onSkip)
            }
        }
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            Label(title, systemImage: "timer")
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .lineLimit(1)
            Text(isRunning ? "Таймер идёт" : "Таймер на паузе")
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
        }
    }

    private var timeValue: some View {
        Text(formattedTime(remainingSeconds))
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(FFColors.textPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var expandButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(FFColors.textSecondary)
                .frame(width: 30, height: 30)
                .background(FFColors.surface)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(FFColors.gray700, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func capsuleButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, FFSpacing.xs)
                .frame(minHeight: 36)
                .background(tint)
                .clipShape(Capsule())
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
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack(spacing: FFSpacing.sm) {
                    VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                        Label(title, systemImage: "figure.strengthtraining.traditional")
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.textPrimary)
                        Text(detail)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }

                    Spacer(minLength: FFSpacing.xs)

                    Button("Скрыть", action: onDismiss)
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(FFColors.textSecondary)
                }

                HStack(spacing: FFSpacing.xs) {
                    ForEach(presetSeconds, id: \.self) { value in
                        Button {
                            onAddTime(value)
                        } label: {
                            Text("+\(value) сек")
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
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.top, FFSpacing.xs)
        .background(FFColors.background.opacity(0.96))
    }
}
