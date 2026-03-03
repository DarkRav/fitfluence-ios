import SwiftUI

struct ProfileScreen: View {
    @State var viewModel: ProfileViewModel
    let onLogout: () -> Void
    let onOpenActiveSession: (ActiveWorkoutSession) -> Void

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
                    menuCard
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
            Text("Оффлайн: данные доступны на устройстве.")
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.primary)
                .accessibilityLabel("Оффлайн режим. Данные доступны на устройстве.")
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
                            .font(FFTypography.caption)
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

    private var menuCard: some View {
        FFCard {
            VStack(spacing: 0) {
                NavigationLink {
                    WorkoutSettingsView(viewModel: viewModel)
                } label: {
                    ProfileMenuRow(title: "Настройки тренировки", icon: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityLabel("Настройки тренировки")

                Divider().overlay(FFColors.gray700)

                NavigationLink {
                    DataAndOfflineView(viewModel: viewModel, onOpenActiveSession: onOpenActiveSession)
                } label: {
                    ProfileMenuRow(title: "Данные и офлайн", icon: "externaldrive")
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityLabel("Данные и офлайн")

                Divider().overlay(FFColors.gray700)

                NavigationLink {
                    HelpAndDiagnosticsView(viewModel: viewModel)
                } label: {
                    ProfileMenuRow(title: "Помощь и диагностика", icon: "lifepreserver")
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityLabel("Помощь и диагностика")
            }
        }
    }
}

private struct ProfileMenuRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: FFSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(FFColors.accent)
                .frame(width: 24, height: 24)

            Text(title)
                .font(FFTypography.body)
                .foregroundStyle(FFColors.textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FFColors.gray300)
        }
        .padding(.vertical, FFSpacing.sm)
        .contentShape(Rectangle())
    }
}

#Preview("Профиль: online") {
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
            isOnline: true,
        )
        vm.loadState = .loaded
        vm.displayName = "Athlete Preview"
        vm.avatarInitials = "AP"
        return vm
    }()

    NavigationStack {
        ProfileScreen(
            viewModel: viewModel,
            onLogout: {},
            onOpenActiveSession: { _ in },
        )
    }
}

#Preview("Профиль: offline") {
    let viewModel: ProfileViewModel = {
        let vm = ProfileViewModel(
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
        )
        vm.loadState = .loaded
        vm.displayName = "Offline Athlete"
        vm.avatarInitials = "OA"
        return vm
    }()

    NavigationStack {
        ProfileScreen(
            viewModel: viewModel,
            onLogout: {},
            onOpenActiveSession: { _ in },
        )
    }
}
