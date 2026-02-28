import ComposableArchitecture
import SwiftUI

struct ProgramDetailsView: View {
    let store: StoreOf<ProgramDetailsFeature>
    let environment: AppEnvironment
    let apiClient: APIClientProtocol?

    private struct ViewState: Equatable {
        let isWorkoutsPresented: Bool
        let isWorkoutPlayerPresented: Bool
    }

    var body: some View {
        WithViewStore(
            store,
            observe: {
                ViewState(
                    isWorkoutsPresented: $0.workoutsList != nil,
                    isWorkoutPlayerPresented: $0.selectedWorkout != nil,
                )
            },
        ) { navViewStore in
            WithViewStore(store, observe: { $0 }) { viewStore in
                ScrollView {
                    VStack(spacing: FFSpacing.md) {
                        if viewStore.isShowingCachedData {
                            FFCard {
                                Text("Оффлайн. Показаны сохранённые данные.")
                                    .font(FFTypography.caption.weight(.semibold))
                                    .foregroundStyle(FFColors.primary)
                            }
                        }

                        if viewStore.isLoading, viewStore.details == nil {
                            loadingState
                        } else if let error = viewStore.error, viewStore.details == nil {
                            FFErrorState(
                                title: error.title,
                                message: error.message,
                                retryTitle: "Повторить",
                                onRetry: { viewStore.send(.retry) },
                            )
                        } else if let details = viewStore.details {
                            header(details: details)
                            about(details: details)
                            workouts(details: details)
                            startProgramBlock(details: details, viewStore: viewStore)
                            if let successMessage = viewStore.successMessage {
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
                .onAppear {
                    viewStore.send(.onAppear)
                }
                .navigationDestination(
                    isPresented: Binding(
                        get: { navViewStore.isWorkoutsPresented },
                        set: { isPresented in
                            if !isPresented {
                                store.send(.workoutsListDismissed)
                            }
                        },
                    ),
                ) {
                    if let workoutsStore = store.scope(state: \.workoutsList, action: \.workoutsList) {
                        WorkoutsListView(store: workoutsStore)
                            .navigationTitle("Тренировки")
                    }
                }
                .navigationDestination(
                    isPresented: Binding(
                        get: { navViewStore.isWorkoutPlayerPresented },
                        set: { isPresented in
                            if !isPresented {
                                store.send(.selectedWorkoutDismissed)
                            }
                        },
                    ),
                ) {
                    if let playerState = viewStore.selectedWorkout {
                        WorkoutLaunchView(
                            userSub: playerState.userSub,
                            programId: playerState.programId,
                            workoutId: playerState.workoutId,
                            apiClient: apiClient,
                        )
                            .navigationTitle("Тренировка")
                    }
                }
            }
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
                Text(details.description ?? "Описание программы пока недоступно.")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
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
                        action: { store.send(.openWorkoutsTapped) },
                    )

                    ForEach(workouts.sorted(by: { $0.dayOrder < $1.dayOrder })) { workout in
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text("День \(workout.dayOrder)")
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.accent)
                            Text(workout.title ?? "Тренировка")
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
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
    private func startProgramBlock(
        details: ProgramDetails,
        viewStore: ViewStore<ProgramDetailsFeature.State, ProgramDetailsFeature.Action>,
    ) -> some View {
        if details.currentPublishedVersion?.id != nil {
            FFButton(
                title: viewStore.isStartingProgram ? "Запускаем программу..." : "Начать программу",
                variant: viewStore.isStartingProgram ? .disabled : .primary,
                action: { viewStore.send(.startProgramTapped) },
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
        guard let pathOrURL, !pathOrURL.isEmpty else {
            return nil
        }

        if let direct = URL(string: pathOrURL), direct.scheme != nil {
            return direct
        }

        guard let baseURL = environment.backendBaseURL else {
            return nil
        }
        let normalizedPath = pathOrURL.hasPrefix("/") ? String(pathOrURL.dropFirst()) : pathOrURL
        return baseURL.appendingPathComponent(normalizedPath)
    }
}
