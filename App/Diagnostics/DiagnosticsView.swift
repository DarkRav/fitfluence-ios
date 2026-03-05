import ComposableArchitecture
import SwiftUI

struct DiagnosticsView: View {
    let store: StoreOf<DiagnosticsFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(spacing: FFSpacing.md) {
                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Диагностика сервера")
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)
                        Text("Проверка выполняет безопасный запрос `/v1/programs/published/search`.")
                            .font(FFTypography.body)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }

                FFButton(title: "Проверить соединение", variant: .primary) {
                    viewStore.send(.checkConnectionTapped)
                }

                switch viewStore.phase {
                case .idle:
                    FFEmptyState(
                        title: "Ожидаем проверку",
                        message: "Нажмите кнопку, чтобы проверить доступность сервера",
                    )

                case .loading:
                    FFLoadingState(title: "Выполняем запрос к серверу")

                case let .success(response):
                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            FFBadge(status: .published)
                            Text("Соединение установлено")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)
                            Text("Статус сервиса: \(response.status)")
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }

                case let .failure(error):
                    FFErrorState(
                        title: "Проверка не пройдена",
                        message: error.userMessage,
                        retryTitle: "Повторить",
                    ) {
                        viewStore.send(.checkConnectionTapped)
                    }
                }

                Spacer()
            }
            .padding(.top, FFSpacing.md)
        }
    }
}

private extension APIError {
    var userMessage: String {
        switch self {
        case .offline:
            "Нет подключения к интернету"
        case .timeout, .transportError, .httpError:
            "Сервер недоступен"
        case .unauthorized:
            "Требуется авторизация"
        case .forbidden:
            "Доступ запрещён"
        case .serverError:
            "Ошибка сервера"
        case .decodingError:
            "Не удалось обработать ответ"
        case .cancelled, .invalidURL, .unknown:
            "Неизвестная ошибка"
        }
    }
}
