Спроектировать полную схему базы данных для livlogios backend на основе существующей документации.

## Задача

Входные данные:
- @docs/user-scenarios.md - пользовательские сценарии
- @docs/api.md - API контракты
- @docs/auth.md - система авторизации (уже содержит схему таблиц auth)

Результат:
- docs/database.md - полная документация схемы БД

Требования к документации:

Для каждой таблицы описать:
1. **Название таблицы** и её назначение
2. **Список колонок** в формате таблицы:
   | Колонка | Тип | Nullable | Default | Индекс | FK | Описание |
3. **Индексы** - какие индексы нужны и почему
4. **Внешние связи (FK)** - связи между таблицами, ON DELETE behavior
5. **Использование данных** - какие операции выполняются с таблицей
6. **Типичные запросы** - примеры SQL запросов
7. **Оптимизация** - как оптимизировать запросы, какие индексы критичны

Таблицы для проектирования:
- users (из auth.md)
- user_auth_providers (из auth.md)
- user_tokens (из auth.md)
- user_passwords (из auth.md, future)
- collections
- entries (items)
- entry_images

Дополнительно описать:
- Стратегию миграций
- Soft delete vs hard delete
- Временные зоны (UTC)
- UUID vs serial для primary keys
- JSON/JSONB поля (additionalFields)
- Хранение изображений (ссылки vs blob)

Технические требования:
- PostgreSQL как целевая БД
- Учесть все поля из API контрактов
- Учесть пагинацию и фильтрацию из GET /entries
- Оптимизировать для типичных use cases:
  * Загрузка списка entries с фильтрацией по коллекции
  * Поиск по title и description
  * Сортировка по date, createdAt, title, score
  * Подсчет entries в коллекции (entriesCount)
  * Каскадное удаление коллекций с entries
  * Каскадное удаление пользователя с данными

Структура документа docs/database.md:
```
# Database Schema

## Overview
- Общая архитектура БД
- Принципы проектирования
- Выбор типов данных

## Tables

### [table]
[Полное описание по формату выше]

## Relationships Diagram
- Mermaid диаграмма связей между таблицами

## Performance Considerations
- Индексы для критичных запросов
- EXPLAIN ANALYZE примеры
- Оптимизация JOIN запросов
- Pagination best practices

## Data Retention
- Soft delete политика
- Cleanup процедуры для устаревших токенов
- GDPR compliance (удаление пользователя)

## Backup Strategy
- Частота бэкапов
- Point-in-time recovery
```

Dependencies:
- Документация должна быть согласована с API контрактами из @docs/api.md
- Схема auth таблиц должна совпадать с @docs/auth.md

Important:
- Check Definition of Done from ./CLAUDE.md

## Result

Created `docs/database.md` with comprehensive database schema documentation:

**Tables documented (7 total):**
- `users` - user accounts with soft delete support
- `user_auth_providers` - multi-provider auth (Apple, future Google/email)
- `user_tokens` - refresh token storage with rotation
- `user_passwords` - future email auth support
- `collections` - user's item groups (Movies, Books, Games)
- `entries` - logged items with JSONB additionalFields
- `entry_images` - CDN image references

**Key design decisions:**
- UUID primary keys for security
- JSONB for flexible `additionalFields` metadata
- GIN index for full-text search on title+description
- Composite indexes for common filter+sort patterns
- Images stored as URLs to external CDN (not blobs)
- Soft delete for users only (GDPR compliance)
- Hard delete with cascade for content

**Documentation includes:**
- Full SQL definitions with indexes
- Mermaid ER diagram
- Typical queries for each table
- Performance optimization recommendations
- Pagination best practices (offset + keyset)
- Data retention and cleanup procedures
- GDPR compliance workflow
- Backup strategy
- Migration workflow
