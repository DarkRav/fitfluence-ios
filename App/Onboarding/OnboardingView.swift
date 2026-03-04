import ComposableArchitecture
import SwiftUI

struct OnboardingView: View {
    let store: StoreOf<OnboardingFeature>

    var body: some View {
        WithPerceptionTracking {
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
                        text: Binding(
                            get: { store.athleteDisplayName },
                            set: { store.send(.athleteDisplayNameChanged($0)) },
                        ),
                        helperText: "Имя можно изменить позже",
                    )

                    FFButton(
                        title: store.isSubmitting ? "Создаём профиль..." : "Создать профиль",
                        variant: store.isSubmitting ? .disabled : .primary,
                    ) {
                        store.send(.createAthleteTapped)
                    }

                    if let error = store.errorMessage {
                        FFErrorState(
                            title: "Не удалось создать профиль",
                            message: error,
                            retryTitle: "Скрыть",
                        ) {
                            store.send(.clearMessage)
                        }
                    }
                }
                .padding(.top, FFSpacing.lg)
            }
        }
    }
}
