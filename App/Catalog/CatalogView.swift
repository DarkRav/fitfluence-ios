import ComposableArchitecture
import SwiftUI

struct CatalogView: View {
    let store: StoreOf<CatalogFeature>
    let environment: AppEnvironment

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ScrollView {
                VStack(spacing: FFSpacing.md) {
                    if viewStore.isShowingCachedData {
                        cachedDataBadge
                    }

                    FFTextField(
                        label: "Поиск",
                        placeholder: "Название программы",
                        text: viewStore.binding(
                            get: \.query,
                            send: CatalogFeature.Action.searchQueryChanged,
                        ),
                        helperText: "Введите название программы",
                    )
                    .accessibilityLabel("Поиск программы по названию")

                    if viewStore.isLoading, viewStore.programs.isEmpty {
                        loadingSkeleton
                    } else if let error = viewStore.error {
                        FFErrorState(
                            title: error.title,
                            message: error.message,
                            retryTitle: "Повторить",
                            onRetry: { viewStore.send(.retry) },
                        )
                    } else if viewStore.programs.isEmpty {
                        FFEmptyState(
                            title: "Пока нет опубликованных программ",
                            message: "Попробуйте изменить запрос или обновить экран позже.",
                        )
                    } else {
                        LazyVStack(spacing: FFSpacing.sm) {
                            ForEach(viewStore.programs) { program in
                                programCard(program: program) {
                                    viewStore.send(.programTapped(program.id))
                                }
                                .onAppear {
                                    if program.id == viewStore.programs.last?.id {
                                        viewStore.send(.loadNextPage)
                                    }
                                }
                            }

                            if viewStore.isLoading {
                                FFLoadingState(title: "Загружаем ещё программы")
                            }
                        }
                    }
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.top, FFSpacing.md)
                .padding(.bottom, FFSpacing.lg)
            }
            .background(FFColors.background)
            .refreshable {
                viewStore.send(.refresh)
            }
            .onAppear {
                viewStore.send(.onAppear)
            }
        }
    }

    private var cachedDataBadge: some View {
        FFCard {
            Text("Оффлайн. Показаны сохранённые данные.")
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.primary)
        }
    }

    private var loadingSkeleton: some View {
        VStack(spacing: FFSpacing.sm) {
            FFLoadingState(title: "Загружаем программы")
            FFLoadingState(title: "Подбираем лучшие варианты")
        }
    }

    private func programCard(program: CatalogFeature.ProgramCard, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    if let imageURL = resolvedImageURL(from: program.coverURL) {
                        FFRemoteImage(url: imageURL) {
                            placeholderImage
                        }
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                    } else {
                        placeholderImage
                    }

                    HStack(alignment: .top, spacing: FFSpacing.xs) {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text(program.title)
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)
                                .multilineTextAlignment(.leading)
                            Text(program.description)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                        }
                        Spacer(minLength: FFSpacing.sm)
                        if program.isPublished {
                            FFBadge(status: .published)
                        }
                    }

                    if let influencerName = program.influencerName {
                        Text("Автор: \(influencerName)")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.gray300)
                    }

                    if !program.goals.isEmpty {
                        Text(program.goals.joined(separator: " • "))
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.accent)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("Открыть программу \(program.title)")
        .accessibilityHint("Откроет детальную страницу программы")
    }

    private var placeholderImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .fill(FFColors.gray700)
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(FFColors.accent)
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
    }

    private func resolvedImageURL(from pathOrURL: String?) -> URL? {
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
