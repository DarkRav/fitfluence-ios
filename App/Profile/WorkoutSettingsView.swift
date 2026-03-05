import SwiftUI

struct WorkoutSettingsView: View {
    @Bindable var viewModel: ProfileViewModel

    var body: some View {
        ScrollView {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    Text("Настройки тренировки")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)

                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Шаг веса: \(String(format: "%.1f", viewModel.settings.weightStep)) кг")
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
                        Text("Таймер отдыха: \(viewModel.settings.defaultRestSeconds) сек")
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
                            Text("Показывать субъективную нагрузку")
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textPrimary)
                        },
                    )
                    .tint(FFColors.accent)

                    Text("Используется метрическая система (кг).")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)

                    if let infoMessage = viewModel.infoMessage {
                        Text(infoMessage)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.accent)
                            .accessibilityLabel(infoMessage)
                    }
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .navigationTitle("Настройки тренировки")
    }
}
