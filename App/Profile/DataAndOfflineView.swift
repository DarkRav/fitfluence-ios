import SwiftUI

struct DataAndOfflineView: View {
    @Bindable var viewModel: ProfileViewModel
    let onOpenActiveSession: (ActiveWorkoutSession) -> Void

    @State private var isResetConfirmationPresented = false

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                if !viewModel.isOnline {
                    FFCard {
                        Text("Оффлайн: данные доступны на устройстве.")
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.primary)
                            .accessibilityLabel("Оффлайн: данные доступны на устройстве.")
                    }
                }

                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.sm) {
                        Text("Хранилище")
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
                        .accessibilityHint("Удаляет кэш каталога и изображений, не удаляет прогресс")

                        if let infoMessage = viewModel.infoMessage {
                            Text(infoMessage)
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.accent)
                                .accessibilityLabel(infoMessage)
                        }
                    }
                }

                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.sm) {
                        Text("Незавершённая тренировка")
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)

                        if let activeSession = viewModel.activeSession {
                            Text(activeSession.subtitle)
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)

                            FFButton(title: "Открыть", variant: .primary) {
                                onOpenActiveSession(activeSession.session)
                            }
                            .accessibilityLabel("Открыть незавершённую тренировку")

                            FFButton(title: "Сбросить", variant: .destructive) {
                                isResetConfirmationPresented = true
                            }
                            .accessibilityLabel("Сбросить незавершённую тренировку")
                        } else {
                            Text("Активных сессий нет.")
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .navigationTitle("Данные и офлайн")
        .alert("Сбросить тренировку?", isPresented: $isResetConfirmationPresented) {
            Button("Отмена", role: .cancel) {}
            Button("Сбросить", role: .destructive) {
                Task { await viewModel.resetActiveSession() }
            }
        } message: {
            Text("Текущая незавершённая сессия будет удалена. История завершённых тренировок останется.")
        }
    }
}

#Preview("Data+Offline: active session") {
    let viewModel: ProfileViewModel = {
        let vm = ProfileViewModel(
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
            isOnline: false,
        )
        vm.loadState = .loaded
        vm.activeSession = ProfileSessionSnapshot(
            session: ActiveWorkoutSession(
                userSub: "athlete-preview",
                programId: "program-1",
                workoutId: "workout-1",
                source: .program,
                status: .inProgress,
                currentExerciseIndex: 2,
                lastUpdated: Date(),
            ),
            subtitle: "Обновлено только что",
        )
        vm.diagnostics = ProfileDiagnosticsSnapshot(
            isOnline: false,
            cacheSizeLabel: "12.30 МБ",
            localStorageLabel: "1.20 МБ",
            versionLabel: "1.0",
            buildLabel: "42",
            pendingSyncOperations: 3,
            lastSyncAttemptLabel: "Сегодня, 10:42",
            lastSyncError: "Нет сети",
        )
        return vm
    }()

    NavigationStack {
        DataAndOfflineView(
            viewModel: viewModel,
            onOpenActiveSession: { _ in },
        )
    }
}

#Preview("Data+Offline: no session") {
    let viewModel: ProfileViewModel = {
        let vm = ProfileViewModel(
            me: MeResponse(
                subject: "athlete-no-session",
                email: "athlete@fitfluence.local",
                roles: ["ATHLETE"],
                requiresAthleteProfile: false,
                requiresInfluencerProfile: false,
                athleteProfile: .init(id: "athlete-2"),
                influencerProfile: nil,
            ),
            userSub: "athlete-no-session",
            isOnline: true,
        )
        vm.loadState = .loaded
        vm.activeSession = nil
        vm.diagnostics = ProfileDiagnosticsSnapshot(
            isOnline: true,
            cacheSizeLabel: "4.10 МБ",
            localStorageLabel: "0.40 МБ",
            versionLabel: "1.0",
            buildLabel: "42",
            pendingSyncOperations: 0,
            lastSyncAttemptLabel: "Сегодня, 09:05",
            lastSyncError: nil,
        )
        return vm
    }()

    NavigationStack {
        DataAndOfflineView(
            viewModel: viewModel,
            onOpenActiveSession: { _ in },
        )
    }
}
