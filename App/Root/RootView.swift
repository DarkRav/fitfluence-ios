import ComposableArchitecture
import SwiftUI

struct RootView: View {
    let store: StoreOf<RootFeature>
    let environment: AppEnvironment

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            TabView(
                selection: Binding(
                    get: { viewStore.selectedTab },
                    set: { viewStore.send(.tabSelected($0)) },
                ),
            ) {
                NavigationStack {
                    CatalogPlaceholderView(environment: environment)
                        .padding(.horizontal, FFSpacing.md)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(FFColors.background)
                        .navigationTitle("Каталог")
                }
                .tabItem {
                    Label("Каталог", systemImage: "sparkles.rectangle.stack")
                }
                .tag(RootFeature.Tab.catalog)

                NavigationStack {
                    WorkoutsPlaceholderView()
                        .padding(.horizontal, FFSpacing.md)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(FFColors.background)
                        .navigationTitle("Мои тренировки")
                }
                .tabItem {
                    Label("Мои тренировки", systemImage: "figure.run")
                }
                .tag(RootFeature.Tab.workouts)

                NavigationStack {
                    ProfilePlaceholderView()
                        .padding(.horizontal, FFSpacing.md)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(FFColors.background)
                        .navigationTitle("Профиль")
                }
                .tabItem {
                    Label("Профиль", systemImage: "person.crop.circle")
                }
                .tag(RootFeature.Tab.profile)

                #if DEBUG
                NavigationStack {
                    DiagnosticsView(
                        store: store.scope(
                            state: \.diagnostics,
                            action: \.diagnostics,
                        ),
                    )
                    .padding(.horizontal, FFSpacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(FFColors.background)
                    .navigationTitle("Диагностика")
                }
                .tabItem {
                    Label("Диагностика", systemImage: "waveform.path.ecg")
                }
                .tag(RootFeature.Tab.diagnostics)
                #endif
            }
            .tint(FFColors.accent)
        }
    }
}

private struct CatalogPlaceholderView: View {
    let environment: AppEnvironment

    var body: some View {
        VStack(spacing: FFSpacing.md) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    FFBadge(status: .draft)
                    Text("Каталог программ")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Скоро здесь появятся программы тренировок с подборками по целям.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                    Text("Окружение: \(environment.name)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.gray300)
                }
            }
            FFEmptyState(title: "Каталог формируется", message: "Добавим первые программы в ближайших итерациях")
        }
        .padding(.top, FFSpacing.md)
    }
}

private struct WorkoutsPlaceholderView: View {
    var body: some View {
        VStack(spacing: FFSpacing.md) {
            FFLoadingState(title: "Готовим ваши тренировки")
            FFCard {
                Text("Здесь будет история выполнений, план на неделю и прогресс.")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
            }
        }
        .padding(.top, FFSpacing.md)
    }
}

private struct ProfilePlaceholderView: View {
    var body: some View {
        VStack(spacing: FFSpacing.md) {
            FFErrorState(
                title: "Профиль пока не настроен",
                message: "Настройки и персонализация появятся на следующем этапе",
                retryTitle: "Обновить",
            )
            FFCard {
                HStack {
                    Text("Статус аккаунта")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textPrimary)
                    Spacer()
                    FFBadge(status: .archived)
                }
            }
        }
        .padding(.top, FFSpacing.md)
    }
}
