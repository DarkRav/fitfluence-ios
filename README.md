# Fitfluence iOS

Production-grade каркас iOS-приложения на SwiftUI + TCA.

## Требования

- macOS с Xcode 26.2+ (рекомендуется актуальная стабильная версия Xcode 26)
- iOS Simulator (iOS 17.0+)
- Homebrew (для установки formatter-инструментов)

## Запуск проекта

1. Сгенерировать проект:
   ```bash
   xcodegen generate
   ```
2. Открыть проект:
   ```bash
   open Fitfluence.xcodeproj
   ```
3. Выбрать схему `FitfluenceApp` и симулятор iOS 17+, затем `Run`.

## Конфигурации сборки (Dev / Stage / Prod)

Конфиги находятся в `/Configs`:

- `Backend.xcconfig`
- `Dev.xcconfig`
- `Stage.xcconfig`
- `Prod.xcconfig`

Сейчас backend один для всех конфигураций. Он задаётся в `Backend.xcconfig`.
`Dev`, `Stage` и `Prod` различаются только профилем сборки и значением `APP_ENVIRONMENT_NAME` в приложении.

Ключи конфигурации:

- `BASE_URL` — backend base URL
- `APP_ENVIRONMENT_NAME`

Подключение выполнено через `Info.plist` и `AppEnvironment` в коде (`/App/Support/Environment.swift`).

## Privacy Manifest

В приложении есть [PrivacyInfo.xcprivacy](/Users/ravil/work/fitfluence/fitfluence-ios/App/PrivacyInfo.xcprivacy) с declaration для `NSPrivacyAccessedAPICategoryUserDefaults`.
Он должен оставаться в app target и обновляться, если в runtime-коде появятся другие required-reason API.

Переключение окружения:

1. В Xcode: `Product` -> `Scheme` -> `Edit Scheme...`
2. Для `Run` выбрать нужную конфигурацию (`Dev`, `Stage`, `Prod`).

## Auth + Onboarding

iOS-клиент использует:

- нативный `Sign in with Apple`
- backend mobile auth endpoints:
  - `POST /v1/auth/apple/native`
  - `POST /v1/auth/refresh`
  - `POST /v1/auth/logout`

Keycloak больше не участвует в mobile login flow. Он остается только для web/admin-контура.

### Troubleshooting

- Постоянный `401`:
  - проверьте доступность backend URL из `Backend.xcconfig` (для телефона это должен быть домен или IP, доступный с устройства, не `localhost`)
  - проверьте, что backend mobile issuer включен и `/v1/auth/refresh` принимает refresh token
  - проверьте, что access token, выданный backend, принимается resource server-конфигурацией
- Apple login не завершает вход:
  - проверьте, что `Sign in with Apple` capability включен у `com.fitfluence.ios`
  - проверьте, что backend настроен на ваш Apple client id и валидирует `identityToken` / `authorizationCode`

## Форматирование

Установить formatter:

```bash
brew install swiftformat
```

Запуск:

```bash
make format
```

или

```bash
./scripts/format.sh
```

## Тесты

Запуск тестов:

```bash
make test
```

Тесты находятся в `/Tests`.
