import ComposableArchitecture
import SwiftUI

struct RootView: View {
    let store: StoreOf<RootFeature>
    let environment: AppEnvironment

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            Group {
                switch viewStore.sessionState {
                case .unauthenticated:
                    AuthEntryView {
                        viewStore.send(.loginTapped(.login))
                    } onCreateAccount: {
                        viewStore.send(.loginTapped(.createAccount))
                    }

                case .authenticating:
                    FFLoadingState(title: "Проверяем сессию")
                        .padding(.horizontal, FFSpacing.md)

                case let .needsOnboarding(context):
                    if let onboardingStore = store.scope(state: \.onboarding, action: \.onboarding) {
                        OnboardingView(
                            store: onboardingStore,
                        )
                        .padding(.horizontal, FFSpacing.md)
                    } else {
                        OnboardingGateView(context: context)
                            .padding(.horizontal, FFSpacing.md)
                    }

                case let .authenticated(userContext):
                    MainTabsView(
                        store: store,
                        environment: environment,
                        me: userContext.me,
                        onLogout: { viewStore.send(.logoutTapped) },
                    )

                case let .error(error):
                    FFErrorState(
                        title: error.title,
                        message: error.message,
                        retryTitle: "Повторить",
                    ) {
                        viewStore.send(.retryBootstrapTapped)
                    }
                    .padding(.horizontal, FFSpacing.md)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FFColors.background)
            .onAppear {
                viewStore.send(.onAppear)
            }
        }
    }
}

private struct AuthEntryView: View {
    let onLogin: () -> Void
    let onCreateAccount: () -> Void

    var body: some View {
        VStack(spacing: FFSpacing.md) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Добро пожаловать")
                        .font(FFTypography.h1)
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Войдите через Keycloak, чтобы продолжить работу в Fitfluence.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }

            FFButton(title: "Войти", variant: .primary, action: onLogin)

            Button("Создать аккаунт", action: onCreateAccount)
                .font(FFTypography.body.weight(.semibold))
                .foregroundStyle(FFColors.accent)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(FFColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))

            Spacer()
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.top, FFSpacing.lg)
    }
}

private struct OnboardingGateView: View {
    let context: OnboardingContext

    var body: some View {
        VStack(spacing: FFSpacing.md) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Создание профиля")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Подготавливаем onboarding по выбранным типам профиля.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                    if context.requiredProfiles.requiresAthleteProfile {
                        FFBadge(status: .draft)
                    }
                }
            }

            FFEmptyState(
                title: "Требуется onboarding",
                message: "На следующем шаге откроются формы профилей атлета и инфлюэнсера.",
            )

            Spacer()
        }
        .padding(.top, FFSpacing.lg)
    }
}

private struct MainTabsView: View {
    let store: StoreOf<RootFeature>
    let environment: AppEnvironment
    let me: MeResponse
    let onLogout: () -> Void

    var body: some View {
        WithViewStore(store, observe: { $0.selectedMainTab }) { viewStore in
            TabView(
                selection: Binding(
                    get: { viewStore.state },
                    set: { store.send(.tabSelected($0)) },
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
                .tag(RootFeature.MainTab.catalog)

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
                .tag(RootFeature.MainTab.workouts)

                NavigationStack {
                    ProfilePlaceholderView(me: me, onLogout: onLogout)
                        .padding(.horizontal, FFSpacing.md)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(FFColors.background)
                        .navigationTitle("Профиль")
                }
                .tabItem {
                    Label("Профиль", systemImage: "person.crop.circle")
                }
                .tag(RootFeature.MainTab.profile)

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
                .tag(RootFeature.MainTab.diagnostics)
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
    let me: MeResponse
    let onLogout: () -> Void

    var body: some View {
        VStack(spacing: FFSpacing.md) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Пользователь")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Text(me.email ?? "Email не предоставлен")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }

            FFButton(title: "Выйти", variant: .secondary, action: onLogout)

            Spacer()
        }
        .padding(.top, FFSpacing.md)
    }
}
