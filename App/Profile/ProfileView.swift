import Observation
import SwiftUI

@Observable
@MainActor
final class ProfileViewModel {
    private let me: MeResponse
    let userSub: String
    private let trainingStore: TrainingStore
    private let cacheStore: CacheStore
    private let calendar: Calendar

    var isOnline: Bool
    var activeProgramTitle = "Не выбрана"
    var workoutsThisWeek = 0
    var streakDays = 0
    var templatesCount = 0
    var lastWorkoutTitle = "—"
    var lastWorkoutDate = "—"
    var storageMB = "0.00"

    init(
        me: MeResponse,
        userSub: String,
        isOnline: Bool,
        trainingStore: TrainingStore = LocalTrainingStore(),
        cacheStore: CacheStore = CompositeCacheStore(),
        calendar: Calendar = .current,
    ) {
        self.me = me
        self.userSub = userSub
        self.isOnline = isOnline
        self.trainingStore = trainingStore
        self.cacheStore = cacheStore
        self.calendar = calendar
    }

    var emailTitle: String {
        me.email ?? "Email не предоставлен"
    }

    var rolesTitle: String {
        if me.roles.isEmpty {
            return "Роль: атлет"
        }
        return "Роли: \(me.roles.joined(separator: ", "))"
    }

    var syncStatusTitle: String {
        isOnline ? "Синхронизация активна" : "Оффлайн: сохранение только на устройстве"
    }

    func updateNetworkStatus(_ value: Bool) {
        isOnline = value
    }

    func onAppear() async {
        guard !userSub.isEmpty else { return }

        let size = await trainingStore.storageSizeBytes(userSub: userSub)
        storageMB = String(format: "%.2f", Double(size) / (1024 * 1024))

        templatesCount = await trainingStore.templates(userSub: userSub).count

        let history = await trainingStore.history(userSub: userSub, source: nil, limit: 90)
        if let last = history.first {
            lastWorkoutTitle = last.workoutTitle
            lastWorkoutDate = last.finishedAt.formatted(date: .abbreviated, time: .shortened)
            await resolveActiveProgramTitle(from: last.programId)
        } else {
            await resolveFallbackProgramTitle()
        }

        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))
            ?? Date()
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        workoutsThisWeek = history.count(where: { $0.finishedAt >= weekStart && $0.finishedAt < weekEnd })

        let weekly = await trainingStore.weeklySummary(userSub: userSub, weekStart: weekStart)
        streakDays = weekly.streakDays
    }

    private func resolveActiveProgramTitle(from programId: String) async {
        if let details = await cacheStore.get(
            "program.details:\(programId)",
            as: ProgramDetails.self,
            namespace: userSub,
        ) {
            activeProgramTitle = details.title
            return
        }

        if let catalog = await cacheStore.get(
            "programs.list?q=&page=0",
            as: CatalogViewModel.CachedCatalogPage.self,
            namespace: userSub,
        ),
            let card = catalog.cards.first(where: { $0.id == programId })
        {
            activeProgramTitle = card.title
            return
        }

        activeProgramTitle = "Программа \(programId.prefix(6))"
    }

    private func resolveFallbackProgramTitle() async {
        if let catalog = await cacheStore.get(
            "programs.list?q=&page=0",
            as: CatalogViewModel.CachedCatalogPage.self,
            namespace: userSub,
        ),
            let first = catalog.cards.first
        {
            activeProgramTitle = first.title
            return
        }

        activeProgramTitle = "Не выбрана"
    }
}

struct ProfileScreen: View {
    @State var viewModel: ProfileViewModel
    let onLogout: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                accountCard
                trainingCard
                syncCard
                FFButton(title: "Выйти", variant: .secondary, action: onLogout)
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

    private var accountCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Аккаунт")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Text(viewModel.emailTitle)
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textPrimary)
                Text(viewModel.rolesTitle)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                Text("ID: \(viewModel.userSub)")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.gray300)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var trainingCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Тренировочный профиль")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Text("Активная программа: \(viewModel.activeProgramTitle)")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textPrimary)
                Text("Тренировок за неделю: \(viewModel.workoutsThisWeek)")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                Text("Серия тренировок: \(viewModel.streakDays) дн")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.accent)
                Text("Шаблонов: \(viewModel.templatesCount)")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                Text("Последняя тренировка: \(viewModel.lastWorkoutTitle)")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                Text(viewModel.lastWorkoutDate)
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.gray300)
            }
        }
    }

    private var syncCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Синхронизация и данные")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Text(viewModel.syncStatusTitle)
                    .font(FFTypography.body)
                    .foregroundStyle(viewModel.isOnline ? FFColors.accent : FFColors.primary)
                Text("Локальное хранилище: \(viewModel.storageMB) МБ")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
                Text("Namespace: \(viewModel.userSub)")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.gray300)
            }
        }
    }
}

#Preview("Профиль") {
    NavigationStack {
        ProfileScreen(
            viewModel: ProfileViewModel(
                me: MeResponse(
                    subject: "preview-user",
                    email: "preview@fitfluence.app",
                    roles: ["ATHLETE"],
                    requiresAthleteProfile: false,
                    requiresInfluencerProfile: false,
                    athleteProfile: .init(id: "athlete-1"),
                    influencerProfile: nil,
                ),
                userSub: "preview-user",
                isOnline: true,
            ),
            onLogout: {},
        )
    }
}
