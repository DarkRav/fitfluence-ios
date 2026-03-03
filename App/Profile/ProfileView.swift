import SwiftUI
import UIKit

struct ProfileScreen: View {
    @State var viewModel: ProfileViewModel
    let onLogout: () -> Void
    let onOpenProgram: (String) -> Void
    let onOpenActiveSession: (ActiveWorkoutSession) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                if !viewModel.isOnline {
                    offlineCard
                }

                switch viewModel.loadState {
                case .loading:
                    FFLoadingState(title: "Загружаем профиль")

                case let .error(error):
                    FFErrorState(
                        title: error.title,
                        message: error.message,
                        retryTitle: "Повторить",
                    ) {
                        Task { await viewModel.reload() }
                    }

                case .loaded:
                    headerCard
                    metricsGrid
                    activeProgramCard
                    settingsCard
                    dataCard
                    helpCard
                    versionCard
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .navigationTitle("Профиль")
        .task {
            await viewModel.onAppear()
        }
    }

    private var offlineCard: some View {
        FFCard {
            Text("Оффлайн: данные профиля загружены из локального хранилища.")
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.primary)
        }
    }

    private var headerCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack(spacing: FFSpacing.sm) {
                    ZStack {
                        Circle()
                            .fill(FFColors.primary)
                            .frame(width: 56, height: 56)
                        Text(viewModel.avatarInitials)
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.background)
                    }
                    .accessibilityLabel("Аватар профиля")

                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text(viewModel.displayName)
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)
                        Text(viewModel.email)
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textSecondary)
                        Text("\(viewModel.syncStatusTitle) • \(viewModel.syncStatus)")
                            .font(FFTypography.caption)
                            .foregroundStyle(viewModel.isOnline ? FFColors.accent : FFColors.primary)
                    }
                    Spacer(minLength: FFSpacing.xs)
                }

                FFButton(title: "Выйти", variant: .secondary, action: onLogout)
                    .accessibilityLabel("Выйти из аккаунта")
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: FFSpacing.sm) {
            ForEach(viewModel.metrics) { item in
                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text(item.title)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                        Text(item.value)
                            .font(FFTypography.h1)
                            .foregroundStyle(FFColors.textPrimary)
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.gray300)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.title): \(item.value) \(item.subtitle ?? "")")
            }
        }
    }

    @ViewBuilder
    private var activeProgramCard: some View {
        if let activeProgram = viewModel.activeProgram {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Активная программа")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)

                    Text(activeProgram.title)
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)

                    if let completed = activeProgram.completedWorkouts, let total = activeProgram.totalWorkouts {
                        Text("Прогресс: \(completed)/\(total) тренировок")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    } else {
                        Text("Прогресс появится после загрузки тренировок.")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }

                    if let nextWorkoutTitle = activeProgram.nextWorkoutTitle {
                        Text("Следующая: \(nextWorkoutTitle)")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.accent)
                    }

                    if let nextWorkoutSubtitle = activeProgram.nextWorkoutSubtitle {
                        Text(nextWorkoutSubtitle)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }

                    if let programId = activeProgram.programId {
                        FFButton(title: "Открыть программу", variant: .primary) {
                            onOpenProgram(programId)
                        }
                        .accessibilityLabel("Открыть активную программу")
                    }
                }
            }
        } else {
            FFCard {
                FFEmptyState(
                    title: "Активная программа не выбрана",
                    message: "Откройте каталог и начните программу, чтобы видеть прогресс здесь.",
                )
            }
        }
    }

    private var settingsCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Настройки тренировки")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                Picker("Единицы веса", selection: Binding(
                    get: { viewModel.settings.weightUnit },
                    set: { newValue in
                        viewModel.settings.weightUnit = newValue
                        Task { await viewModel.persistSettings() }
                    },
                )) {
                    ForEach(TrainingWeightUnit.allCases, id: \.self) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Единицы веса")

                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Шаг веса: \(String(format: "%.1f", viewModel.settings.weightStep))")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                    Stepper(
                        value: Binding(
                            get: { viewModel.settings.weightStep },
                            set: { newValue in
                                viewModel.settings.weightStep = max(0.5, min(newValue, 10.0))
                                Task { await viewModel.persistSettings() }
                            },
                        ),
                        in: 0.5 ... 10.0,
                        step: 0.5,
                    ) {
                        Text("Изменить шаг веса")
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textPrimary)
                    }
                }

                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Rest timer: \(viewModel.settings.defaultRestSeconds) сек")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                    Stepper(
                        value: Binding(
                            get: { viewModel.settings.defaultRestSeconds },
                            set: { newValue in
                                viewModel.settings.defaultRestSeconds = max(15, min(newValue, 600))
                                Task { await viewModel.persistSettings() }
                            },
                        ),
                        in: 15 ... 600,
                        step: 15,
                    ) {
                        Text("Изменить таймер отдыха")
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textPrimary)
                    }
                }

                Toggle(
                    isOn: Binding(
                        get: { viewModel.settings.timerVibrationEnabled },
                        set: { newValue in
                            viewModel.settings.timerVibrationEnabled = newValue
                            Task { await viewModel.persistSettings() }
                        },
                    ),
                    label: {
                        Text("Вибрация таймера")
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textPrimary)
                    },
                )
                .tint(FFColors.accent)

                Toggle(
                    isOn: Binding(
                        get: { viewModel.settings.timerSoundEnabled },
                        set: { newValue in
                            viewModel.settings.timerSoundEnabled = newValue
                            Task { await viewModel.persistSettings() }
                        },
                    ),
                    label: {
                        Text("Звук таймера")
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textPrimary)
                    },
                )
                .tint(FFColors.accent)

                Toggle(
                    isOn: Binding(
                        get: { viewModel.settings.showRPE },
                        set: { newValue in
                            viewModel.settings.showRPE = newValue
                            Task { await viewModel.persistSettings() }
                        },
                    ),
                    label: {
                        Text("Показывать RPE")
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textPrimary)
                    },
                )
                .tint(FFColors.accent)
            }
        }
    }

    private var dataCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Данные и офлайн")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                Text("Кэш: \(viewModel.diagnostics.cacheSizeLabel)")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textPrimary)

                Text("Локальные данные тренировок: \(viewModel.diagnostics.localStorageLabel)")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)

                FFButton(
                    title: viewModel.isClearingCache ? "Очищаем..." : "Очистить кэш",
                    variant: viewModel.isClearingCache ? .disabled : .secondary,
                ) {
                    Task { await viewModel.clearCache() }
                }
                .accessibilityLabel("Очистить кэш")
                .accessibilityHint("Удаляет кэш программ и изображений, не удаляет прогресс")

                if let activeSession = viewModel.activeSession {
                    Divider().overlay(FFColors.gray700)
                    Text("Незавершённая тренировка")
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                    Text(activeSession.subtitle)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)

                    FFButton(title: "Открыть", variant: .primary) {
                        onOpenActiveSession(activeSession.session)
                    }
                    .accessibilityLabel("Открыть незавершённую тренировку")

                    FFButton(title: "Сбросить", variant: .destructive) {
                        Task { await viewModel.resetActiveSession() }
                    }
                    .accessibilityLabel("Сбросить незавершённую тренировку")
                }

                if let infoMessage = viewModel.infoMessage {
                    Text(infoMessage)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.accent)
                        .accessibilityLabel(infoMessage)
                }
            }
        }
    }

    private var helpCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Помощь")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                FFButton(title: "Сообщить о проблеме", variant: .secondary) {
                    if let url = URL(string: "mailto:support@fitfluence.app?subject=Fitfluence%20iOS%20Issue") {
                        openURL(url)
                    }
                }
                .accessibilityLabel("Сообщить о проблеме")

                FFButton(title: "Скопировать диагностику", variant: .secondary) {
                    UIPasteboard.general.string = viewModel.diagnosticsText
                    viewModel.infoMessage = "Диагностика скопирована"
                }
                .accessibilityLabel("Скопировать диагностику")
            }
        }
    }

    private var versionCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Версия приложения: \(viewModel.diagnostics.versionLabel)")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                Text("Build: \(viewModel.diagnostics.buildLabel)")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.gray300)
            }
        }
    }
}

#Preview("Профиль: online") {
    NavigationStack {
        ProfileScreen(
            viewModel: ProfileViewModel(
                me: MeResponse(
                    subject: "athlete-preview",
                    email: "athlete@fitfluence.local",
                    roles: ["ATHLETE"],
                    requiresAthleteProfile: false,
                    requiresInfluencerProfile: false,
                    athleteProfile: .init(id: "athlete-1"),
                    influencerProfile: nil,
                ),
                userSub: "athlete-preview",
                isOnline: true,
            ),
            onLogout: {},
            onOpenProgram: { _ in },
            onOpenActiveSession: { _ in },
        )
    }
}

#Preview("Профиль: offline") {
    NavigationStack {
        ProfileScreen(
            viewModel: ProfileViewModel(
                me: MeResponse(
                    subject: "athlete-offline",
                    email: "offline@fitfluence.local",
                    roles: ["ATHLETE"],
                    requiresAthleteProfile: false,
                    requiresInfluencerProfile: false,
                    athleteProfile: .init(id: "athlete-2"),
                    influencerProfile: nil,
                ),
                userSub: "athlete-offline",
                isOnline: false,
            ),
            onLogout: {},
            onOpenProgram: { _ in },
            onOpenActiveSession: { _ in },
        )
    }
}
