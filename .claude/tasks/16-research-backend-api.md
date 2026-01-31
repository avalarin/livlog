Провести исследование и описать контракты для Backend API

## Задача

Задокументировать API endpoints для интеграции iOS приложения с Backend сервером. Backend должен предоставлять RESTful API для следующих функций:

Files to reference:
- @livlogios/Models/Item.swift (Collection и Item models)
- @livlogios/Services/OpenAIService.swift (EntryOption structure для AI search)

Files to create:
- docs/api.md

Функциональные требования:
**1. AI поиск материалов**
- Endpoint для поиска материалов через AI (фильмы, книги, игры)
- Должен принимать поисковый запрос и возвращать варианты с метаданными
- Структура ответа должна быть совместима с EntryOption из OpenAIService.swift

**2. Получение списка коллекций**
- Endpoint для получения всех коллекций пользователя
- Должен возвращать name, icon, createdAt для каждой коллекции
- Должен поддерживать фильтрацию и сортировку

**3. Получение списка entries**
- Endpoint для получения записей пользователя
- Должен поддерживать фильтрацию по коллекции
- Должен поддерживать пагинацию для больших списков
- Должен возвращать все поля из Item model (title, description, score, date, additionalFields, images)

**4. CRUD операции для entries**
- Create: создание новой записи
- Read: получение одной записи по ID
- Update: обновление существующей записи
- Delete: удаление записи

**5. CRUD операции для collections**
- Create: создание новой коллекции
- Read: получение одной коллекции по ID
- Update: обновление существующей коллекции
- Delete: удаление коллекции

Требования к документации:

Для каждого endpoint описать:
- HTTP метод (GET, POST, PUT, DELETE)
- URL path с параметрами
- Request headers (включая authentication)
- Request body (JSON schema с примерами)
- Response body (JSON schema с примерами)
- Возможные коды ответов:
  - 200 OK (успешный запрос)
  - 201 Created (успешное создание)
  - 400 Bad Request (некорректные данные)
  - 401 Unauthorized (нет авторизации)
  - 404 Not Found (ресурс не найден)
  - 500 Internal Server Error (ошибка сервера)

Дополнительные требования:
- API должен следовать REST principles
- Использовать JSON для request/response bodies
- Описать authentication/authorization механизм (JWT, API Key, etc.)
- Для списковых endpoints предусмотреть pagination (limit, offset)
- Для списковых endpoints предусмотреть filtering и sorting
- Обработка изображений: как загружать (base64 или multipart/form-data)
- Версионирование API (например, /api/v1/)

Формат документации:
- OpenAPI-style markdown
- Примеры curl запросов
- Примеры response bodies
- Описание error responses с примерами

Important:
- Это ИССЛЕДОВАТЕЛЬСКАЯ задача, не реализация кода
- Цель: создать четкую спецификацию для backend разработки
- Документация должна быть понятна backend разработчику
- Check Definition of Done from ./CLAUDE.md

## Result

Создана документация API в файле `docs/api.md`.

### Структура документации

**1. Authentication**
- JWT-based authentication
- Login endpoint для получения токенов
- Refresh token flow

**2. AI Search (`POST /search`)**
- Принимает query string
- Возвращает до 5 вариантов с полной метаинформацией
- Совместим с EntryOption структурой

**3. Collections API**
- `GET /collections` - список с сортировкой
- `GET /collections/{id}` - одна коллекция
- `POST /collections` - создание
- `PUT /collections/{id}` - обновление
- `DELETE /collections/{id}` - удаление (cascade)

**4. Entries API**
- `GET /entries` - список с пагинацией, фильтрацией, сортировкой
- `GET /entries/{id}` - одна запись
- `POST /entries` - создание (JSON или multipart)
- `PUT /entries/{id}` - обновление
- `DELETE /entries/{id}` - удаление
- `PUT /entries/{id}/images` - управление изображениями

**5. Дополнительно**
- Error responses с кодами ошибок
- Score values mapping (0-3)
- Pagination format
- Rate limiting
- curl примеры для всех endpoints

### Файл
- `docs/api.md` - ~400 строк документации в OpenAPI-style markdown
