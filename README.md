# Fitfluence iOS

Стартовый production-grade каркас iOS-приложения на SwiftUI + TCA.

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

## Окружения (Dev / Stage / Prod)

Конфиги находятся в `/Configs`:

- `Dev.xcconfig`
- `Stage.xcconfig`
- `Prod.xcconfig`

Ключи окружения:

- `BASE_URL`
- `KEYCLOAK_URL`
- `APP_ENVIRONMENT_NAME`

Подключение выполнено через `Info.plist` и `AppEnvironment` в коде (`/App/Support/Environment.swift`).

Переключение окружения:

1. В Xcode: `Product` -> `Scheme` -> `Edit Scheme...`
2. Для `Run` выбрать нужную конфигурацию (`Dev`, `Stage`, `Prod`).

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

Минимальный набор тестов находится в `/Tests/DesignSystemTests.swift`.
