# Claude Setup

Обзор конфигурации agents, skills и hooks в этом проекте.

## Skills

### `/feature-dev`
Главный оркестратор, разрабатывает фичи в 6 фаз:
1. **Discovery** — понять запрос, уточнить у пользователя
2. **Exploration** — 2–3 параллельных `system-analyst` агента исследуют кодовую базу
3. **Clarifying Questions** — задать все неоднозначные вопросы до начала дизайна
4. **Architecture Design** — несколько `system-analyst` предлагают подходы, оркестратор рекомендует один
5. **Implementation** — `software-engineer` реализует после явного одобрения пользователя
6. **Summary** — итог: что сделано, какие файлы изменены

Код-ревью после реализации обрабатывается **автоматически через хуки** — явно запускать ревьюера не нужно.

---

### `/plan-creator`
Старый более простой подход. Нужно вручную попросить описать задачу, а потом попросить software-engineer реализовать ее. Возможно в будущем переделаю этот скилл тоже в оркестратора, только который будет ресерчи по коду делать, а не сразу реализовывать.

Создаёт файл плана в `.claude/plans/` по шаблону.

**Шаблоны** (в `.claude/skills/plan-creator/templates/`):
- `task.md` — задача для разработчика
- `research.md` — исследование/отчёт

Выбор шаблона зависит от запроса: «опиши задачу» → task.md, «исследуй» → research.md.

---

## Агенты

Агентов созданы только для тех ролей, которым действительно нужна отдельная память.

### `code-reviewer`
Проверяет качество и корректность кода после реализации. Запускается через stop trigger. Так сделано чтобы 

**Что делает:**
- Читает свою память с известными recurring issues
- Проверяет diff изменённых файлов по чеклисту (Critical → Warnings → Suggestions)
- Обновляет память: если проблема встречается 3+ раз — рекомендует `software-engineer` добавить правило в свою память

---

### `software-engineer`
Реализует изменения в коде. Перед написанием кода консультируется с памятью и документацией.

**Workflow:** понять задачу → проверить память → исследовать (WebFetch/WebSearch) → реализовать → проверить (build/lint/tests) → обновить память

**Инструменты:** Read, Grep, Glob, Bash, WebFetch, WebSearch, AskUserQuestion, Edit, Write
**Память:** `.claude/agent-memory/software-engineer/` (MEMORY.md + topic files: swiftui-recipes.md и др.)

---

### `system-analyst`
Исследует и анализирует кодовую базу. **Не вносит изменений** — только читает, описывает архитектуру, находит связанные компоненты.

**Используется для:** разведки перед реализацией фичи, поиска существующих паттернов, анализа влияния изменений.

**Инструменты:** Read, Grep, Glob, Bash, WebFetch, AskUserQuestion, Edit
**Память:** `.claude/agent-memory/system-analyst/` (MEMORY.md + architecture.md, backend.md)

---

## Hooks

### Code Review

2 hooks работают в паре: 
- `PostToolUse` вызывает `.claude/hooks/track-modified-files.sh`
- `Stop` вызывает `.claude/hooks/trigger-code-review.sh`

Скрипт `track-modified-files.sh` запускается периодически и добавляет изменныенные файлы в `.claude/modified-files-pending-review.txt`.

Скрипт `.claude/hooks/trigger-code-review.sh`:
1. Проверяет `modified-files-pending-review.txt`
2. Если файлы есть — очищает список и возвращает **exit code 2** (блокирует остановку), выдавая инструкцию запустить `code-reviewer` с конкретными файлами
3. Если список пуст — разрешает остановку (exit code 0)
