import ComposableArchitecture
import SwiftUI

struct OnboardingView: View {
    let store: StoreOf<OnboardingFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ScrollView {
                VStack(spacing: FFSpacing.md) {
                    if let success = viewStore.successMessage {
                        FFCard {
                            Text(success)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.accent)
                        }
                    }

                    switch viewStore.step {
                    case .choice:
                        choiceContent(viewStore)
                    case .athleteForm:
                        athleteForm(viewStore)
                    case .influencerForm:
                        influencerForm(viewStore)
                    case .influencerNotSupported:
                        influencerUnavailable(viewStore)
                    }

                    if let error = viewStore.errorMessage {
                        FFErrorState(
                            title: "Не удалось завершить создание профиля",
                            message: error,
                            retryTitle: "Скрыть",
                        ) {
                            viewStore.send(.clearMessage)
                        }
                    }
                }
                .padding(.top, FFSpacing.lg)
            }
        }
    }

    private func choiceContent(_ viewStore: ViewStore<OnboardingFeature.State, OnboardingFeature.Action>) -> some View {
        VStack(spacing: FFSpacing.md) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Создание профиля")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Выберите тип профиля, чтобы продолжить.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }

            FFButton(title: "Я атлет", variant: .primary) {
                viewStore.send(.chooseAthleteTapped)
            }

            FFButton(title: "Я инфлюэнсер", variant: .secondary) {
                viewStore.send(.chooseInfluencerTapped)
            }
        }
    }

    private func athleteForm(_ viewStore: ViewStore<OnboardingFeature.State, OnboardingFeature.Action>) -> some View {
        VStack(spacing: FFSpacing.md) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Профиль атлета")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Заполните обязательные поля для старта тренировок.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }

            FFTextField(
                label: "Имя профиля",
                placeholder: "Например: Алекс",
                text: viewStore.binding(
                    get: \.athleteDisplayName,
                    send: OnboardingFeature.Action.athleteDisplayNameChanged,
                ),
                helperText: "Это имя увидите вы и ваши тренеры",
            )

            FFTextField(
                label: "Цель",
                placeholder: "Например: Набор мышечной массы",
                text: viewStore.binding(
                    get: \.athleteGoal,
                    send: OnboardingFeature.Action.athleteGoalChanged,
                ),
                helperText: "Коротко опишите спортивную цель",
            )

            FFButton(
                title: viewStore.isSubmitting ? "Создаём профиль..." : "Создать профиль",
                variant: viewStore.isSubmitting ? .disabled : .primary,
            ) {
                viewStore.send(.createAthleteTapped)
            }

            FFButton(title: "Назад", variant: .secondary) {
                viewStore.send(.backToChoiceTapped)
            }
        }
    }

    private func influencerForm(_ viewStore: ViewStore<OnboardingFeature.State, OnboardingFeature.Action>)
        -> some View
    {
        VStack(spacing: FFSpacing.md) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Профиль инфлюэнсера")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Заполните данные для публикации программ.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }

            FFTextField(
                label: "Имя профиля",
                placeholder: "Например: Анна Тренер",
                text: viewStore.binding(
                    get: \.influencerDisplayName,
                    send: OnboardingFeature.Action.influencerDisplayNameChanged,
                ),
                helperText: "Публичное имя автора",
            )

            FFTextField(
                label: "О себе",
                placeholder: "Коротко о специализации",
                text: viewStore.binding(
                    get: \.influencerBio,
                    send: OnboardingFeature.Action.influencerBioChanged,
                ),
                helperText: "Описание профиля инфлюэнсера",
            )

            FFButton(
                title: viewStore.isSubmitting ? "Создаём профиль..." : "Создать профиль",
                variant: viewStore.isSubmitting ? .disabled : .primary,
            ) {
                viewStore.send(.createInfluencerTapped)
            }

            FFButton(title: "Назад", variant: .secondary) {
                viewStore.send(.backToChoiceTapped)
            }
        }
    }

    private func influencerUnavailable(_ viewStore: ViewStore<OnboardingFeature.State, OnboardingFeature.Action>)
        -> some View
    {
        VStack(spacing: FFSpacing.md) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Профиль инфлюэнсера")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Создание профиля инфлюэнсера пока недоступно.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }

            FFButton(title: "Назад", variant: .secondary) {
                viewStore.send(.backToChoiceTapped)
            }
        }
    }
}
