import Observation
import SwiftUI

@Observable
@MainActor
final class ProgramDetailsViewModel {
    struct SelectedWorkout: Equatable, Identifiable {
        let userSub: String
        let programId: String
        let workoutId: String

        var id: String {
            "\(programId)::\(workoutId)"
        }
    }

    let programId: String
    let userSub: String

    private let programsClient: ProgramsClientProtocol?
    private let cacheStore: CacheStore
    private let networkMonitor: NetworkMonitoring
    private let progressStore: WorkoutProgressStore
    private let trainingStore: TrainingStore

    var details: ProgramDetails?
    var isShowingCachedData = false
    var isLoading = false
    var isStartingProgram = false
    var error: UserFacingError?
    var successMessage: String?
    var isWorkoutsPresented = false
    var selectedWorkout: SelectedWorkout?
    var completedWorkoutsCount = 0
    var totalWorkoutsCount = 0
    var upcomingWorkoutTitle: String?
    var lastCompletionTitle: String?

    init(
        programId: String,
        userSub: String,
        programsClient: ProgramsClientProtocol?,
        cacheStore: CacheStore = CompositeCacheStore(),
        networkMonitor: NetworkMonitoring = StaticNetworkMonitor(currentStatus: true),
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
        trainingStore: TrainingStore = LocalTrainingStore(),
    ) {
        self.programId = programId
        self.userSub = userSub
        self.programsClient = programsClient
        self.cacheStore = cacheStore
        self.networkMonitor = networkMonitor
        self.progressStore = progressStore
        self.trainingStore = trainingStore
    }

    func onAppear() async {
        guard details == nil, !isLoading else { return }
        await load()
    }

    func retry() async {
        await load()
    }

    func startProgram() async {
        guard let versionID = details?.currentPublishedVersion?.id, !isStartingProgram else { return }
        isStartingProgram = true
        defer { isStartingProgram = false }

        let result: Result<ProgramEnrollment, APIError> = if let programsClient {
            await programsClient.startProgram(programVersionId: versionID)
        } else {
            .failure(.invalidURL)
        }

        switch result {
        case .success:
            successMessage = "Программа успешно начата."
            error = nil
        case let .failure(apiError):
            error = apiError.userFacing(context: .programDetails)
        }
    }

    func openWorkouts() {
        isWorkoutsPresented = true
    }

    func workoutPicked(_ workoutID: String) {
        selectedWorkout = SelectedWorkout(userSub: userSub, programId: programId, workoutId: workoutID)
    }

    func dismissSelectedWorkout() {
        selectedWorkout = nil
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        if let cached = await cacheStore.get(cacheKey, as: ProgramDetails.self, namespace: userSub) {
            details = cached
            isShowingCachedData = true
        }

        let result: Result<ProgramDetails, APIError> = if let programsClient {
            await programsClient.getProgramDetails(programId: programId)
        } else {
            .failure(.invalidURL)
        }

        switch result {
        case let .success(details):
            self.details = details
            isShowingCachedData = false
            error = nil
            await cacheStore.set(cacheKey, value: details, namespace: userSub, ttl: 60 * 30)
            await refreshProgress(with: details)

        case let .failure(apiError):
            if apiError == .offline || !networkMonitor.currentStatus, details != nil {
                error = nil
                isShowingCachedData = true
                if let details {
                    await refreshProgress(with: details)
                }
                return
            }
            error = apiError.userFacing(context: .programDetails)
        }
    }

    private func refreshProgress(with details: ProgramDetails) async {
        let workouts = details.workouts ?? []
        totalWorkoutsCount = workouts.count

        let statuses = await progressStore.statuses(
            userSub: userSub,
            programId: programId,
            workoutIds: workouts.map(\.id),
        )
        completedWorkoutsCount = statuses.values.count(where: { $0 == .completed })
        upcomingWorkoutTitle = workouts
            .sorted(by: { $0.dayOrder < $1.dayOrder })
            .first(where: { statuses[$0.id] != .completed })?
            .title ?? workouts.sorted(by: { $0.dayOrder < $1.dayOrder }).first?.title

        if let last = await trainingStore.history(userSub: userSub, source: nil, limit: 40)
            .first(where: { $0.programId == programId })
        {
            let minutes = max(1, last.durationSeconds / 60)
            let volume = last.volume > 0 ? " • объём \(Int(last.volume)) кг" : ""
            lastCompletionTitle = "\(last.finishedAt.formatted(date: .abbreviated, time: .shortened)) • \(minutes) мин\(volume)"
        } else {
            lastCompletionTitle = nil
        }
    }

    private var cacheKey: String {
        "program.details:\(programId)"
    }
}

struct ProgramDetailsScreen: View {
    @State var viewModel: ProgramDetailsViewModel
    let apiClient: APIClientProtocol?

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                if viewModel.isShowingCachedData {
                    FFCard {
                        Text("Оффлайн. Показаны сохранённые данные.")
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.primary)
                    }
                }

                if viewModel.isLoading, viewModel.details == nil {
                    loadingState
                } else if let error = viewModel.error, viewModel.details == nil {
                    FFErrorState(
                        title: error.title,
                        message: error.message,
                        retryTitle: "Повторить",
                        onRetry: { Task { await viewModel.retry() } },
                    )
                } else if let details = viewModel.details {
                    header(details: details)
                    progress(details: details)
                    about(details: details)
                    workouts(details: details)
                    startProgramBlock(details: details)
                    if let successMessage = viewModel.successMessage {
                        FFCard {
                            Text(successMessage)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.accent)
                                .multilineTextAlignment(.leading)
                        }
                    }
                } else {
                    FFEmptyState(title: "Программа не найдена", message: "Попробуйте открыть другую программу.")
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .task {
            await viewModel.onAppear()
        }
        .navigationDestination(isPresented: $viewModel.isWorkoutsPresented) {
            if let programsClient = apiClient as? ProgramsClientProtocol {
                WorkoutsListScreen(
                    viewModel: WorkoutsListViewModel(
                        programId: viewModel.programId,
                        userSub: viewModel.userSub,
                        workoutsClient: WorkoutsClient(programsClient: programsClient),
                    ),
                    onWorkoutTap: { workoutID in
                        viewModel.workoutPicked(workoutID)
                    },
                )
                .navigationTitle("Тренировки")
            } else {
                FFErrorState(
                    title: "Тренировки недоступны",
                    message: "Проверьте конфигурацию API-клиента для загрузки тренировок.",
                    retryTitle: "Назад",
                ) {
                    viewModel.isWorkoutsPresented = false
                }
            }
        }
        .navigationDestination(item: $viewModel.selectedWorkout) { selectedWorkout in
            WorkoutLaunchView(
                userSub: selectedWorkout.userSub,
                programId: selectedWorkout.programId,
                workoutId: selectedWorkout.workoutId,
                apiClient: apiClient,
            )
            .navigationTitle("Тренировка")
        }
    }

    private var loadingState: some View {
        VStack(spacing: FFSpacing.sm) {
            FFLoadingState(title: "Загружаем описание программы")
            FFLoadingState(title: "Подготавливаем структуру тренировок")
        }
    }

    private func header(details: ProgramDetails) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                if let imageURL = resolveImageURL(details.cover?.url ?? details.media?.first?.url) {
                    FFRemoteImage(url: imageURL) {
                        placeholderImage
                    }
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                } else {
                    placeholderImage
                }

                HStack(alignment: .center) {
                    Text(details.title)
                        .font(FFTypography.h1)
                        .foregroundStyle(FFColors.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: FFSpacing.sm)
                    FFBadge(status: .published)
                }

                if let shortDescription = details.description, !shortDescription.isEmpty {
                    Text(shortDescription)
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                if let author = details.influencer?.displayName {
                    Text("Автор: \(author)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.gray300)
                }
            }
        }
    }

    private func about(details: ProgramDetails) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("О программе")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                if let version = details.currentPublishedVersion {
                    Text("\(version.levelTitle) • \(version.frequencyTitle)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                    Text(version.equipmentTitle)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
                Text(details.description ?? "Описание программы пока недоступно.")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
            }
        }
    }

    private func progress(details _: ProgramDetails) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Ваш прогресс")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                if viewModel.totalWorkoutsCount > 0 {
                    Text("Пройдено \(viewModel.completedWorkoutsCount) из \(viewModel.totalWorkoutsCount) тренировок")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textPrimary)
                } else {
                    Text("Прогресс появится после загрузки списка тренировок.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
                if let upcomingWorkoutTitle = viewModel.upcomingWorkoutTitle {
                    Text("Следующая: \(upcomingWorkoutTitle)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                }
                if let lastCompletionTitle = viewModel.lastCompletionTitle {
                    Text("Последнее выполнение: \(lastCompletionTitle)")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.accent)
                }
            }
        }
    }

    private func workouts(details: ProgramDetails) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Тренировки")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                if let workouts = details.workouts, !workouts.isEmpty {
                    FFButton(
                        title: "Открыть тренировки",
                        variant: .secondary,
                        action: { viewModel.openWorkouts() },
                    )

                    ForEach(workouts.sorted(by: { $0.dayOrder < $1.dayOrder })) { workout in
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text("День \(workout.dayOrder)")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.accent)
                            Text(workout.title ?? "Тренировка")
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                            if let workoutTitle = viewModel.upcomingWorkoutTitle,
                               workoutTitle == (workout.title ?? "Тренировка")
                            {
                                Text("Следующая по плану")
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.accent)
                            }
                            if let note = workout.coachNote, !note.isEmpty {
                                Text(note)
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                        }
                        .padding(.vertical, FFSpacing.xs)
                    }
                } else {
                    Text("Состав тренировок будет доступен после начала программы.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func startProgramBlock(details: ProgramDetails) -> some View {
        if details.currentPublishedVersion?.id != nil {
            FFButton(
                title: viewModel.isStartingProgram ? "Запускаем программу..." : "Начать программу",
                variant: viewModel.isStartingProgram ? .disabled : .primary,
                action: { Task { await viewModel.startProgram() } },
            )
            .accessibilityLabel("Начать программу")
            .accessibilityHint("Создаст активное прохождение программы для вашего профиля")
        } else {
            FFCard {
                Text("Скоро можно будет начать программу в приложении.")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
            }
        }
    }

    private var placeholderImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .fill(FFColors.gray700)
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(FFColors.primary)
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
    }

    private func resolveImageURL(_ pathOrURL: String?) -> URL? {
        guard let pathOrURL, !pathOrURL.isEmpty else { return nil }
        if let absolute = URL(string: pathOrURL), absolute.scheme != nil {
            return absolute
        }
        guard let baseURL = viewModel.details?.media?.first?.url else {
            return URL(string: pathOrURL)
        }
        if let absolute = URL(string: baseURL), absolute.scheme != nil {
            return absolute.deletingLastPathComponent().appendingPathComponent(pathOrURL)
        }
        return URL(string: pathOrURL)
    }
}
