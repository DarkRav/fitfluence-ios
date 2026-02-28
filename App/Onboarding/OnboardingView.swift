import ComposableArchitecture
import SwiftUI

struct OnboardingView: View {
    let store: StoreOf<OnboardingFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ScrollView {
                VStack(spacing: FFSpacing.md) {
                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text("Создание профиля атлета")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)
                            Text("Проверьте имя профиля и продолжайте к тренировкам.")
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
                        helperText: "Имя можно изменить позже",
                    )

                    FFButton(
                        title: viewStore.isSubmitting ? "Создаём профиль..." : "Создать профиль",
                        variant: viewStore.isSubmitting ? .disabled : .primary,
                    ) {
                        viewStore.send(.createAthleteTapped)
                    }

                    if let error = viewStore.errorMessage {
                        FFErrorState(
                            title: "Не удалось создать профиль",
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
}
