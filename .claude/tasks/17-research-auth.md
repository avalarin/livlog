Провести исследование как сделать авторизацию пользователя в API

## Задача

Исследовать и задокументировать архитектуру системы авторизации для livlogios с поддержкой:
1. **Текущая реализация**: Вход только через Apple ID (Sign in with Apple)
2. **Будущее расширение**: Возможность добавить вход по email без переделки архитектуры

Files:
- @docs/api.md - текущая документация API (нужно обновить секцию Authentication)

## Что нужно исследовать

### 1. Sign in with Apple Flow

Описать полный flow авторизации через Apple ID:
- Как происходит авторизация на iOS клиенте (AuthenticationServices framework)
- Какие данные отправляет Apple (identity token, authorization code, user data)
- Как верифицировать Apple identity token на backend
- Как получить email пользователя (с учетом privacy relay)
- Token lifetime и refresh механизм

### 2. JWT Structure

Описать структуру JWT tokens для API:
- Access token structure (payload, claims, expiration)
- Refresh token structure
- Token signing algorithm (HS256 vs RS256)
- Token rotation strategy
- Где хранить secret keys (environment variables, key management service)

### 3. API Endpoints для Authentication

Описать необходимые endpoints:
- `POST /auth/apple` - вход через Apple ID (получение identity token с iOS)
- `POST /auth/refresh` - обновление access token через refresh token
- `POST /auth/logout` - инвалидация токенов
- `GET /auth/me` - получение информации о текущем пользователе

Для каждого endpoint описать:
- Request body structure
- Response format
- Error cases
- Security considerations

### 4. Database Schema для Users

Описать схему БД с поддержкой multiple auth providers:

```sql
-- Примерная структура (уточнить детали)
users (
  id UUID PRIMARY KEY,
  email VARCHAR UNIQUE,
  email_verified BOOLEAN,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
)

user_auth_providers (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  provider VARCHAR (apple, email, google),
  provider_user_id VARCHAR,  -- Apple user ID или email
  created_at TIMESTAMP,
  UNIQUE(provider, provider_user_id)
)

user_tokens (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  refresh_token_hash VARCHAR,
  expires_at TIMESTAMP,
  created_at TIMESTAMP
)
```

### 5. Расширение на Email Auth (будущее)

Описать как добавить email auth в будущем БЕЗ breaking changes:
- Регистрация через email + password
- Email verification flow
- Password reset flow
- Как хранить passwords (bcrypt, argon2)
- Как это интегрируется с текущей схемой user_auth_providers

### 6. Security Best Practices

Описать важные аспекты безопасности:
- HTTPS only для всех auth endpoints
- Token storage на клиенте (Keychain для iOS)
- CSRF protection
- Rate limiting для auth endpoints
- Token expiration policies (короткий access token, длинный refresh token)
- Защита от brute force атак

## Требования к документации

Создать новый файл `docs/auth.md` со следующей структурой:

```markdown
# Authentication System

## Overview
[Краткое описание системы авторизации]

## Architecture
[Схема взаимодействия iOS app <-> Backend <-> Apple]

## Sign in with Apple Flow

### iOS Client Side
[Код примеры и объяснение]

### Backend Verification
[Как верифицировать Apple token]

### User Creation/Login
[Flow создания/входа пользователя]

## JWT Tokens

### Access Token
[Структура, claims, expiration]

### Refresh Token
[Структура, rotation strategy]

## API Endpoints

### POST /auth/apple
[Request, Response, Examples]

### POST /auth/refresh
[Request, Response, Examples]

### POST /auth/logout
[Request, Response, Examples]

### GET /auth/me
[Request, Response, Examples]

## Database Schema

### Users Table
[Описание полей]

### User Auth Providers Table
[Описание полей]

### User Tokens Table
[Описание полей]

## Future: Email Authentication

### Registration Flow
[Email + password registration]

### Email Verification
[Verification flow]

### Password Reset
[Reset flow]

### Integration with Current System
[Как добавить без breaking changes]

## Security Considerations

### Token Storage
### Rate Limiting
### Password Handling
### CSRF Protection

## Implementation Checklist
- [ ] iOS: Integrate Sign in with Apple
- [ ] Backend: Apple token verification endpoint
- [ ] Backend: JWT token generation
- [ ] Backend: Database schema migration
- [ ] Backend: Auth middleware
- [ ] iOS: Token storage in Keychain
- [ ] iOS: Token refresh logic
- [ ] Testing: Auth flows
```

Также обновить файл `@docs/api.md` секцию Authentication:
- Заменить текущий email/password auth на Apple Sign In
- Добавить все новые auth endpoints
- Добавить примеры с curl
- Описать Authorization header format

## Дополнительные требования

- Все описания должны быть детальными с примерами кода
- Для iOS использовать SwiftUI + AuthenticationServices framework
- Для backend предположить использование любого современного фреймворка (можно несколько вариантов)
- Привести примеры curl запросов для всех endpoints
- Описать edge cases и error handling

Dependencies:
- Зависит от задачи @.claude/tasks/16-research-backend-api.md (общая backend архитектура)

Important:
- Check Definition of Done from ./CLAUDE.md
- This is a RESEARCH task, NOT implementation
- Focus on extensible architecture
- Apple Sign In должен работать полностью
- Email auth только описать как future extension

## Result

Создана полная документация системы авторизации.

### Созданные файлы

**docs/auth.md** (~600 строк):
- Overview и архитектура системы
- Полный Sign in with Apple flow (iOS + Backend)
- Примеры кода на Swift, Python, JavaScript
- JWT структура (access + refresh tokens)
- Все API endpoints с примерами
- Database schema (users, user_auth_providers, user_tokens)
- Future: Email authentication design
- Security considerations (Keychain, rate limiting, HTTPS)
- Implementation checklist

**docs/api.md** (обновлено):
- Заменена секция Authentication
- Добавлены endpoints: `/auth/apple`, `/auth/refresh`, `/auth/logout`, `/auth/me`, `/auth/account`
- Добавлена ссылка на docs/auth.md
- Обновлен changelog

### Ключевые решения

1. **Multi-provider architecture**: Таблица `user_auth_providers` позволяет добавлять новые auth методы без изменения схемы users

2. **Token strategy**: RS256 JWT (1 hour) + refresh token rotation (30 days)

3. **Apple token verification**: Проверка через Apple public keys + JWT decode

4. **Future extensibility**: Описан email auth flow с таблицей `user_passwords`

5. **Security**: Keychain storage, rate limiting, HTTPS only
