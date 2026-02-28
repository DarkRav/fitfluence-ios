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

- `BASE_URL` — backend base URL
- `KEYCLOAK_URL` — base URL Keycloak
- `KEYCLOAK_REALM`
- `KEYCLOAK_CLIENT_ID`
- `KEYCLOAK_REDIRECT_URI` (например `fitfluence://oauth/callback`)
- `KEYCLOAK_SCOPES` (для DEV по умолчанию `openid`)
- `KEYCLOAK_REGISTRATION_HINT_MODE` (`kc_action` или `loginOnly`)
- `APP_ENVIRONMENT_NAME`

Подключение выполнено через `Info.plist` и `AppEnvironment` в коде (`/App/Support/Environment.swift`).

Переключение окружения:

1. В Xcode: `Product` -> `Scheme` -> `Edit Scheme...`
2. Для `Run` выбрать нужную конфигурацию (`Dev`, `Stage`, `Prod`).

## Auth + Onboarding (Keycloak)

### Настройка Keycloak для локальной проверки

1. Realm:
   - включить `User registration` (self-registration)
2. Client (`fitfluence-ios`):
   - тип: public
   - Standard Flow (Authorization Code) включён
   - PKCE: `S256`
   - Valid redirect URI: `fitfluence://oauth/callback`
   - Web origins: `*` (для локальной отладки)
3. Для режима кнопки `Создать аккаунт`:
   - `KEYCLOAK_REGISTRATION_HINT_MODE=kc_action` — пробует добавить `kc_action=register`
   - `loginOnly` — всегда открывает обычный login screen

### Demo пользователи (пример)

- `athlete.demo` / `password`
- `influencer.demo` / `password`

Создайте их в realm вручную, если локальный стенд пустой.

### Troubleshooting

- Не открывается callback:
  - проверьте `KEYCLOAK_REDIRECT_URI` и URL scheme `fitfluence`
- Постоянный `401`:
  - проверьте доступность backend URL из `Dev.xcconfig` (для телефона это должен быть IP, не `localhost`)
  - проверьте `spring.security.oauth2.resourceserver.jwt.issuer-uri` в backend: issuer должен совпадать с `iss` в access token
  - если backend запущен с локальным профилем и IP-хостом Keycloak, задайте `KEYCLOAK_ISSUER_URI=http://<ваш-ip>:9990/realms/fitfluence`
- Не работает регистрация из кнопки:
  - переключите `KEYCLOAK_REGISTRATION_HINT_MODE` на `loginOnly`
- `invalid_scope` в логине:
  - оставьте `KEYCLOAK_SCOPES=openid` для DEV или добавьте `profile/email` в scopes клиента Keycloak

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
