import ComposableArchitecture
import SwiftUI

struct RootView: View {
    let store: StoreOf<RootFeature>
    let environment: AppEnvironment

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(spacing: 0) {
                if !viewStore.isOnline {
                    OfflineBannerView()
                }

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

                    case .needsOnboarding:
                        if let onboardingStore = store.scope(state: \.onboarding, action: \.onboarding) {
                            OnboardingView(store: onboardingStore)
                                .padding(.horizontal, FFSpacing.md)
                        } else {
                            FFLoadingState(title: "Подготавливаем профиль")
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FFColors.background)
            .onAppear {
                viewStore.send(.onAppear)
            }
        }
    }
}

private struct OfflineBannerView: View {
    var body: some View {
        Text("Нет подключения. Показаны сохранённые данные.")
            .font(FFTypography.caption.weight(.semibold))
            .foregroundStyle(FFColors.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, FFSpacing.xs)
            .background(FFColors.primary)
            .accessibilityLabel("Оффлайн режим")
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
                    Text("Войдите, чтобы начать тренировки в Fitfluence.")
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

private struct MainTabsView: View {
    let store: StoreOf<RootFeature>
    let environment: AppEnvironment
    let me: MeResponse
    let onLogout: () -> Void

    private struct ViewState: Equatable {
        var selectedTab: RootFeature.MainTab
        var isProgramDetailsPresented: Bool
    }

    var body: some View {
        WithViewStore(
            store,
            observe: {
                ViewState(
                    selectedTab: $0.selectedMainTab,
                    isProgramDetailsPresented: $0.programDetails != nil,
                )
            },
        ) { viewStore in
            TabView(
                selection: Binding(
                    get: { viewStore.selectedTab },
                    set: { store.send(.tabSelected($0)) },
                ),
            ) {
                NavigationStack {
                    HomeView(
                        store: store.scope(
                            state: \.home,
                            action: \.home,
                        ),
                    )
                    .navigationTitle("Главная")
                }
                .tabItem {
                    Label("Главная", systemImage: "house")
                }
                .tag(RootFeature.MainTab.home)

                NavigationStack {
                    CatalogView(
                        store: store.scope(
                            state: \.catalog,
                            action: \.catalog,
                        ),
                        environment: environment,
                    )
                    .navigationTitle("Каталог")
                    .navigationDestination(
                        isPresented: Binding(
                            get: { viewStore.isProgramDetailsPresented },
                            set: { isPresented in
                                if !isPresented {
                                    store.send(.programDetailsDismissed)
                                }
                            },
                        ),
                    ) {
                        if let detailsStore = store.scope(state: \.programDetails, action: \.programDetails) {
                            ProgramDetailsView(
                                store: detailsStore,
                                environment: environment,
                            )
                            .navigationTitle("Программа")
                        }
                    }
                }
                .tabItem {
                    Label("Каталог", systemImage: "sparkles.rectangle.stack")
                }
                .tag(RootFeature.MainTab.catalog)

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
            }
            .tint(FFColors.accent)
        }
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
