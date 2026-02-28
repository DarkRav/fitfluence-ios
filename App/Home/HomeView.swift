import ComposableArchitecture
import SwiftUI

struct HomeView: View {
    let store: StoreOf<HomeFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ScrollView {
                VStack(spacing: FFSpacing.md) {
                    hero(viewStore)

                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text("Ваш фокус")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)

                            if let programTitle = viewStore.programTitle, !programTitle.isEmpty {
                                Text("Программа: \(programTitle)")
                                    .font(FFTypography.body)
                                    .foregroundStyle(FFColors.textSecondary)
                            }

                            Text(viewStore.subtitle)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text("Режим данных")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)
                            Text("Оффлайн: изменения тренировки сохраняются на устройстве.")
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.md)
            }
            .background(FFColors.background)
            .onAppear { viewStore.send(.onAppear) }
        }
    }

    private func hero(_ viewStore: ViewStore<HomeFeature.State, HomeFeature.Action>) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.md) {
                Text("Сегодня")
                    .font(FFTypography.h1)
                    .foregroundStyle(FFColors.textPrimary)

                if viewStore.isLoading {
                    FFLoadingState(title: "Проверяем прогресс")
                } else {
                    FFButton(title: viewStore.primaryTitle, variant: .primary) {
                        viewStore.send(.primaryTapped)
                    }
                    .accessibilityLabel(viewStore.primaryTitle)

                    Text(viewStore.activeSession == nil
                        ? "Главный сценарий: выбрать программу и начать тренировку."
                        : "Главный сценарий: продолжить тренировку без потери прогресса.")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.gray300)
                }
            }
        }
    }
}
