Создать базовую структуру backend сервиса на Golang с инфраструктурой для разработки и развертывания.

## Задача

Разработать backend сервис на Golang в директории `backend/` внутри текущего репозитория. На первом этапе реализовать только базовую инфраструктуру с простым healthcheck endpoint.

Files to reference:
- @docs/database.md (схема БД для миграций)
- @docs/api.md (будущие API endpoints)

Files to create:
- backend/cmd/server/main.go
- backend/go.mod
- backend/Dockerfile
- backend/docker-compose.yml
- backend/Justfile
- backend/.golangci.yml
- backend/config.yaml (пример конфигурации)
- backend/migrations/ (директория для миграций БД)

Функциональные требования:

**1. Базовая структура проекта**
- Создать директорию `backend/` в корне репозитория
- Инициализировать Go модуль: `go mod init github.com/avalarin/livlog/backend`
- Создать файл cmd/server/main.go с HTTP сервером
- Реализовать endpoint `/api/v1/health` который возвращает полный статус системы:
  ```json
  {
    "status": "ok",
    "timestamp": "2026-01-31T12:00:00Z",
    "version": "1.0.0",
    "uptime": "2h30m15s",
    "database": {
      "status": "connected",
      "ping_ms": 5
    }
  }
  ```
- Добавить .gitignore который исключает все зависимости, бинарники и др. что нужно исключить

**2. Конфигурация**
- Поддержка чтения конфигурации из YAML файла
- Использовать библиотеку viper или аналог
- Параметры конфигурации:
  - server.port (HTTP порт)
  - server.host (адрес для прослушивания)
  - logging.format (json или console для переключения формата логов)
  - database.host
  - database.port
  - database.name
  - database.user
  - database.password
  - database.sslmode
- Создать файл `config.yaml` с примером конфигурации
- Поддержка переопределения параметров через environment variables

**3. Линтер**
- Добавить golangci-lint конфигурацию (.golangci.yml)
- Включить рекомендованные линтеры: errcheck, gosimple, govet, ineffassign, staticcheck, unused
- Добавить команду в Justfile: `just lint`

**4. Команды сборки и тестирования**
- Justfile с командами:
  - `just build` - компиляция бинарника
  - `just test` - запуск тестов
  - `just lint` - запуск линтера
  - `just run` - запуск локально
  - `just docker-build` - сборка Docker образа
  - `just docker-up` - запуск через docker-compose
  - `just docker-down` - остановка docker-compose

**5. Dockerfile**
- Multi-stage build для оптимизации размера образа
- Базовый образ: golang:1.22-alpine
- Финальный образ: alpine
- Expose порт для HTTP сервера (например, 8080)
- Использовать non-root пользователя для запуска

**6. Docker Compose**
- Сервис backend с портом 8080
- Сервис PostgreSQL:
  - Image: postgres:15-alpine или новее
  - Конфигурация: database
  - Volume для персистентности данных
  - Expose порт 5432
- Healthcheck для обоих сервисов
- Backend должен зависеть от PostgreSQL (depends_on)

**7. База данных PostgreSQL**
- Добавить библиотеку для миграций (golang-migrate/migrate или goose)
- Создать директорию `backend/migrations/`
- Создать первую миграцию с таблицей users из @docs/database.md:
  - `001_create_users_table.up.sql`
  - `001_create_users_table.down.sql`
- Добавить команду в Justfile: `just migrate-up` и `just migrate-down`
- Миграции должны запускаться автоматически при старте сервиса

**8. Логирование**
- Использовать библиотеку zap для структурированного логирования
- Поддержка двух форматов вывода через конфиг:
  - `logging.format: json` - JSON формат для production (structured logging)
  - `logging.format: console` - human-readable формат для разработки
- Логировать основные события: запуск сервера, подключение к БД, HTTP запросы

**9. Prometheus метрики**
- Реализовать endpoint `/metrics` с базовыми метриками:
  - HTTP запросы: счетчик запросов по методу, пути и статусу
  - HTTP latency: histogram задержки запросов
  - Go runtime метрики: goroutines, память, GC
- Использовать библиотеку prometheus/client_golang
- Добавить middleware для автоматического сбора HTTP метрик

**10. Роутинг API**
- Все API endpoints должны использовать префикс `/api/v1`
- Примеры:
  - `/api/v1/health` - healthcheck
  - `/api/v1/users` - пользователи (будущий endpoint)
  - `/api/v1/entries` - записи (будущий endpoint)
- Endpoint `/metrics` не должен иметь префикса `/api/v1`

**11. Структура проекта**
```
backend/
├── cmd/
│   └── server/
│       └── main.go        # Entry point
├── go.mod                 # Go modules
├── go.sum
├── migrations/            # DB migrations
│   ├── 001_create_users_table.up.sql
│   └── 001_create_users_table.down.sql
├── internal/              # Private code
│   ├── config/            # Config loading
│   ├── handler/           # HTTP handlers
│   └── repository/        # DB access layer
├── Dockerfile             # Container image
├── docker-compose.yml     # Local development
├── .golangci.yml          # Linter config
├── config.yaml            # Example config
└── Justfile               # Build commands
```

Stack and tech requirements:
- Go 1.22
- PostgreSQL: 15, pgx/v5, sqlc, golang-migrate
- HTTP Server: net/http + роутер chi
- Logging & Metrics: zap, prometheus client, /metrics endpoint
- Configuration: viper yaml config
- Code Quality: gofmt, goimports, gci, golangci-lint
- Testing: testing, testify/require, mockery
- Docker + Docker Compose
- Building: Just (Justfile)

Dependencies:
- Эта задача является основой для последующей разработки backend функционала
- Схема БД должна соответствовать @docs/database.md
- После выполнения этой задачи можно будет реализовывать API из @docs/api.md

Important:
- Check Definition of Done from ./CLAUDE.md
- Бэкенд находится в директории backend/ внутри iOS репозитория
- Все команды Justfile должны запускаться из директории backend/
- Docker compose должен использовать именованные volumes для PostgreSQL
- Аутентификация и авторизация остаются на будущую задачу

## Result

Backend infrastructure has been successfully created with all requested features:

### Created Files

```
backend/
├── cmd/server/main.go           # Entry point with HTTP server
├── go.mod                        # Go module (github.com/avalarin/livlog/backend)
├── go.sum                        # Dependencies lock file
├── migrations/                   # DB migrations
│   ├── 001_create_users_table.up.sql
│   └── 001_create_users_table.down.sql
├── internal/                     # Private code
│   ├── config/config.go          # Viper configuration
│   ├── config/config_test.go     # Config tests
│   ├── handler/health.go         # Health endpoint handler
│   ├── logger/logger.go          # Zap logger setup
│   ├── middleware/logging.go     # HTTP logging middleware
│   ├── middleware/metrics.go     # Prometheus metrics middleware
│   └── repository/
│       ├── db.go                 # PostgreSQL connection pool
│       └── migrate.go            # Migration runner
├── Dockerfile                    # Multi-stage build
├── docker-compose.yml            # PostgreSQL + backend services
├── .golangci.yml                 # Linter config
├── .gitignore                    # Git ignore rules
├── config.yaml                   # Example configuration
└── Justfile                      # Build commands
```

### Implementation Details

1. **HTTP Server**: chi router with `/api/v1/health` and `/metrics` endpoints
2. **Configuration**: Viper with YAML file support and `LIVLOG_*` env var overrides
3. **Database**: pgx/v5 connection pool with golang-migrate for migrations
4. **Logging**: zap with json/console format switching via config
5. **Metrics**: Prometheus with http_requests_total counter and http_request_duration_seconds histogram
6. **Docker**: Multi-stage build with non-root user, PostgreSQL 16-alpine with healthchecks
7. **Justfile**: All requested commands (build, test, lint, run, docker-*, migrate-*)

### Verification

- `go build`: Passes
- `go vet`: Passes
- `go test`: 4 tests pass
- `gofmt`: No issues

Note: golangci-lint not installed on system, but .golangci.yml configured with errcheck, gosimple, govet, ineffassign, staticcheck, unused, gofmt, goimports, misspell.
