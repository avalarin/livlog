# Миграция хранилища коллекций и записей с iOS на backend

Перевести хранение коллекций и записей с локального SwiftData в iOS на backend базу данных. Подготовить схему БД для будущей возможности шаринга коллекций между пользователями (но саму функцию шаринга НЕ реализовывать).

Функциональные требования:
- Когда пользователь первый раз входит (создает учетную запись), у него появляются collections по умолчанию
- Когда пользователь создает или удаляет collections в ios - сохранение и удаление отражается на бэкенде
- Когда пользователь создает или удаляет entries в ios - это сохраняется на бэкенде
- Когда пользователь ищет записи через поиск - поиск происходит на бэкенде
- Пользователь в момент когда приложение взаимодействует с бэкендом получает обратную связь - получилось или нет
- Все изображения также хранятся на бэкенде
- iCloud storage больше не используется

Важный workaround:
- На экран списка коллекций в empty state нужно добавить кнопку "Create default collections"
- По нажатию на кнопку делается запрос на бэкенд и бэкенд создает коллекции по умолчанию
- Затем экран обновляется
- Это работает только если у пользователя нет коллекций, проверка должна быть и на фронте и не бэкенде

Компромисы:
- Пока нет шаринга коллекций между пользователями (но будет)
- Не будем делать логику переноса текущих данных ищ iOS storage, потерять не страшно
- AI поиск пока остается на фронте

Визуальные требования:
- Если по нажатию на кнопку происходит запрос на бэкенд - то на кнопке появляется ProgressView
- Переход на следующей экран (напр. при сохранении item) происходит только после успеха на бэкенде
- Если произошла ошибка, то появляется alert об ошибке
- Дизейблить кнопки во время операций
- Показывать loading state при первой загрузке данных

Валидация и на ios и на backend:
- Проверять что у колекции есть название и длина в диапазоне от 1 до 50 символов
- Проверять что у записи есть название и длина в диапазоне от 1 до 200 символов
- Проверять что у записи есть описание и длина в диапазоне от 1 до 2000 символов
- Проверять что icon всегда не больше 20 символов
- Проверять что score это всегда 0-3

Что сделать на Backend:
- Создать таблицы БД для коллекций и записей
- Схема должна поддерживать будущий функционал: пользователи могут делиться коллекциями (НЕ реализовывать сейчас, только подготовить схему)
- Реализовать CRUD API endpoints согласно спецификации в @docs/api.md
- Поддержка загрузки изображений (base64 или multipart/form-data)
- Реализовать хранение изображений: пока в postgresql, но предусмотреть загрузку в CDN в будущем
- Добавить миграции БД

iOS:
- Заменить SwiftData на вызовы backend API
- Удалить использование SwiftData для Collection и Item
- Создать/обновить сервисные классы для работы с backend API
- Добавить состояния загрузки (loading indicators) для всех кнопок save/delete
- Добавить обработку ошибок с Alert для всех сетевых операций
- При нажатии кнопки "Fill with Test Data" данные должны сохраняться на backend

Database:
- `collections` таблица: id (uuid), user_id (uuid), name, icon, created_at, updated_at
    - name is required, max 50 chars
    - icon is required
- `collection_shares` таблица (для будущего шаринга): id, collection_id, owner_id, shared_with_user_id, permission_level, created_at
- `entries` таблица: id (uuid), collection_id (nullable), user_id (uuid), title, description, score (0-3), date, created_at, updated_at, additional_fields (jsonb)
    - title is required, max 200 chars
    - description is required, max 2000 chars
- `entry_images` таблица: id (uuid), entry_id (uuid), url, is_cover (boolean), position (int), created_at

Backend API Endpoints:
- GET /collections - список коллекций пользователя
- GET /collections/{id} - одна коллекция
- POST /collections - создать коллекцию
- PUT /collections/{id} - обновить коллекцию
- DELETE /collections/{id} - удалить коллекцию (каскадное удаление entries)
- GET /entries - список записей с пагинацией и фильтрами
- GET /entries/{id} - одна запись
- POST /entries - создать запись (с изображениями)
- PUT /entries/{id} - обновить запись
- DELETE /entries/{id} - удалить запись
- PUT /entries/{id}/images - управление изображениями записи

iOS Changes:
- Обновить модели Collection и Item: убрать @Model, добавить Codable
- Создать CollectionService для работы с /collections endpoints
- Создать EntryService для работы с /entries endpoints
- Добавить ImageService для загрузки/скачивания изображений
- Обновить @ContentView.swift: добавить loading states и error handling
- Обновить @AddEntryView.swift: добавить loading states и error handling
- Обновить @SmartAddEntryView.swift: сохранение на backend
- Обновить @EntryDetailView.swift: загрузка/обновление через API
- Обновить @CollectionsView.swift: CRUD через API

Error Handling:
- Network errors (no connection, timeout)
- API errors (4xx, 5xx)
- Validation errors
- Image upload errors
- Показывать Alert с описанием ошибки пользователю

Files:
- @docs/api.md (API specification - reference)

Important:
- Check Definition of Done from @CLAUDE.md

## Result

### Issue Identified and Fixed

The iOS app was unable to read data from the backend due to incorrect date format handling:

**Problem:**
- Backend sends `date` field as "YYYY-MM-DD" (e.g., "2024-02-01")
- Backend sends `created_at` and `updated_at` as RFC3339/ISO8601 timestamps (e.g., "2024-02-01T10:30:45Z" or "2024-02-01T10:30:45+00:00")
- iOS was using `.iso8601` date decoding strategy globally, which expects full datetime strings for ALL Date fields
- This caused decoding to fail when parsing the simple "YYYY-MM-DD" date format

**Solution:**
1. Removed automatic ISO8601 date decoding strategy from `CollectionService` and `EntryService`
2. Implemented custom `Codable` conformance for `CollectionModel` and `EntryModel` in Item.swift:67,75
   - Added custom `init(from decoder:)` to manually decode each date field
   - Date field uses `DateFormatter` with "yyyy-MM-dd" format
   - Timestamp fields use `ISO8601DateFormatter` with proper fallback handling
   - Added `encode(to encoder:)` for symmetric encoding
3. Added comprehensive unit tests in livlogiosTests.swift:19,47,75 to verify:
   - Collection decoding with ISO8601 timestamps
   - Entry decoding with "YYYY-MM-DD" date and ISO8601 timestamps
   - Support for both "Z" and "+00:00" timezone formats

**Testing:**
- All unit tests pass (4/4 tests in livlogiosTests)
- Build succeeds with no compilation errors
- Date parsing now correctly handles:
  - Simple dates: "2024-02-01" → Date
  - UTC timestamps: "2024-02-01T10:30:45Z" → Date
  - Timezone timestamps: "2024-02-01T10:30:45+00:00" → Date

**Files Modified:**
- livlogios/Models/Item.swift - Added custom Codable implementations
- livlogios/Services/CollectionService.swift - Removed automatic date decoding strategy
- livlogios/Services/EntryService.swift - Removed automatic date decoding strategy
- livlogiosTests/livlogiosTests.swift - Added JSON decoding tests
