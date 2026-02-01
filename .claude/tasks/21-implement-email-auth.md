# Реализовать email-аутентификацию с кодом подтверждения

Реализовать систему входа через email с 6-значным кодом верификации. На первом этапе код всегда будет 000000 (без отправки реальных email).

## Functional requirements

Frontend:
- На экране LoginView есть поле Email и кнопка "Sign In with email"
- После ввода валидного Email и нажатия на кнопку "Sign In with email" пользователь должен ввести 6-значный код 
- На этом этапе выполняется запрос на backend, но фактически код не отправляется
- Если пользователя нет, то выполняется auto create
- Также должна быть создана запись в user_auth_providers с provider='email'
- Пользователь должен вводить код на втором экране EmailVerificationView, там:
  - 6-значное поле для ввода кода
  - Кнопка "Sign In" для подтверждения кода
  - Кнопка "Resend code" (доступна раз в минуту)
  - Таймер, показывающий время до возможности повторной отправки

Безопасность:
- Время жизни кода: 5 минут
- Rate limiting для resend: 1 запрос в минуту на один email

Обработка ошибок:
- Нужна валидация email на клиенте и на бэкенде перед отправкой запроса
- Валидация кода выполняется на клиента (пользователь не должен ввести пустой код) и на бэкенде - что код совпадает
- Валидация периода переотправки и на клиенте и на бэкенде
- Отображение ошибок в случае неверного кода или проблем с сетью

Детали Backend:
- Endpoint `POST /api/v1/auth/email/send-code` для отправки кода верификации
  - Принимает email
  - Генерирует код (пока всегда 000000)
  - Сохраняет код с временем жизни (5 минут)
  - Возвращает успешный ответ
- Endpoint `POST /api/v1/auth/email/verify` для проверки кода
  - Принимает email и код
  - Проверяет корректность кода и срок действия
  - Если пользователь не существует - автоматически создает нового
  - Возвращает access_token и refresh_token (JWT)
- Endpoint `POST /api/v1/auth/email/resend-code` для повторной отправки кода
  - Rate limiting: не чаще одного раза в минуту для одного email
  - Генерирует новый код и обновляет в БД
- Если пользователь уже существует (по email) - выполнить вход
- Если пользователя нет - создать нового с provider='email'

## Visual requirements

LoginView:
- Email input field с placeholder "Email address"
- Кнопка "Sign In with email" с тем же стилем что и Apple button
- Новое поле email и кнопка "Sign In with email" расположена выше Apple buttin и отделена тонкой серой линией c надписью or серым шрифтом
- Email field и кнопка размещены в VStack перед SignInWithAppleButton

EmailVerificationView:
- Заголовок "Enter verification code"
- Подзаголовок с email адресом куда был отправлен код
- 6 полей для ввода кода (каждое на одну цифру)
- Кнопка "Sign In" (disabled пока не введены все 6 цифр)
- Кнопка "Resend code" (disabled с таймером обратного отсчета)
- Кнопка "Back" для возврата на LoginView
- Индикатор загрузки при проверке кода

## Files

Frontend:
- @livlogios/Views/Auth/LoginView.swift - добавить email input и кнопку
- @livlogios/Views/Auth/EmailVerificationView.swift - новый файл
- @livlogios/Services/AuthService.swift - добавить методы для email auth
- @livlogios/Models/User.swift - проверить модель
- @livlogios/Services/KeychainManager.swift - использовать существующий

Backend:
- @backend/internal/handler/auth.go - добавить endpoints
- @backend/internal/service/auth_service.go - бизнес-логика
- @backend/internal/repository/user_repository.go - создание пользователя
- @backend/internal/middleware/rate_limiter.go - возможно новый файл
- @backend/migrations/003_create_verification_codes_table.up.sql - новая миграция
- @backend/migrations/003_create_verification_codes_table.down.sql - откат миграции

## Database schema

Создать новую таблицу `verification_codes`:

```sql
CREATE TABLE verification_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL,
    code VARCHAR(6) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    used_at TIMESTAMP WITH TIME ZONE,

    INDEX idx_verification_codes_email (email),
    INDEX idx_verification_codes_cleanup (expires_at) WHERE used_at IS NULL
);
```

## API specification

### POST /api/v1/auth/email/send-code

Request:
```json
{
  "email": "user@example.com"
}
```

Response 200:
```json
{
  "message": "Verification code sent",
  "expires_in": 300
}
```

Response 429 (rate limit):
```json
{
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Please wait before requesting another code",
    "details": {
      "retry_after": 45
    }
  }
}
```

### POST /api/v1/auth/email/verify

Request:
```json
{
  "email": "user@example.com",
  "code": "000000"
}
```

Response 200:
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "refresh_token": "dGhpcyBpcyBhIHJlZnJlc2g...",
  "expires_in": 3600,
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "email_verified": true,
    "display_name": null,
    "auth_providers": ["email"],
    "created_at": "2025-02-01T10:00:00Z",
    "updated_at": "2025-02-01T10:00:00Z"
  }
}
```

Response 401 (invalid code):
```json
{
  "error": {
    "code": "INVALID_CODE",
    "message": "Verification code is invalid or expired"
  }
}
```

### POST /api/v1/auth/email/resend-code

Request:
```json
{
  "email": "user@example.com"
}
```

Response 200:
```json
{
  "message": "Verification code resent",
  "expires_in": 300
}
```

Response 429:
```json
{
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Please wait before requesting another code",
    "details": {
      "retry_after": 45
    }
  }
}
```

## Implementation notes

Frontend:
- Использовать TextField для email с keyboardType(.emailAddress)
- Для кода использовать 6 отдельных TextField с focusState для автоперехода
- Хранить токены через KeychainManager (уже существует)
- Обработать все ошибки от backend (invalid code, rate limit, network)

Backend:
- Использовать существующую JWT инфраструктуру из Apple Sign In
- Rate limiting через middleware или in-memory map с мьютексом
- Cleanup job для удаления старых verification codes (expires_at < now - 1 day)
- Код всегда "000000" - захардкодить в auth_service.go
- При создании пользователя: email_verified = true, display_name = null

Security:
- Валидация email формата на backend
- Проверка expires_at при верификации кода
- Один код может быть использован только один раз (used_at != null)
- Rate limiting строго один раз в минуту для одного email

## Dependencies

- Требуется работающая Apple Sign In инфраструктура (JWT, tokens, users table)
- Миграция базы данных для verification_codes
- Документация: @docs/auth.md, @docs/api.md, @docs/database.md

## Important

- Check Definition of Done from ./CLAUDE.md

## Result

<hint>Describe what have you done and delete this line</hint>
