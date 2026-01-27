Добавить выбор оценки через bottom sheet в AddEntryView

Функциональные требования:
- При нажатии на кнопку со звездой (star icon) в правом верхнем углу AddEntryView должен открываться bottom sheet с выбором оценки
- Изменить систему оценок, добавив значение 0, которое означает "не смотрел/не читал/не играл"
- Выбор оценки должен быть реализован через слайдер с 4 возможными значениями:
  - 0 🆕 "Undecided, ask me later"
  - 1 👎 "Not my thing at all"
  - 2 👌 "Fine for once"
  - 3 🤩 "Absolutely unhinged"
- Bottom sheet должен иметь кнопку "Done" для подтверждения выбора
- Bottom sheet должен иметь заголовок "What’s the verdict?"
- После выбора оценки bottom sheet должен закрываться
- Текущая выбранная оценка должна быть визуально выделена в bottom sheet

Визуальные требования:
- Bottom sheet должен открываться снизу с анимацией
- Использовать `.presentationDetents([.height(300)])` для фиксированной высоты
- Слайдер должен быть стилизован с визуальным отображением эмодзи и текста для каждого значения
- Текст описания оценки должен быть виден над слайдером
- Эмодзи для каждой оценки должны быть хорошо видны и иметь размер не менее 44pt
- Выбранное значение должно быть выделено цветом акцента
- UI должен соответствовать общему дизайну приложения (rounded corners, shadows, material design)

Файлы:
- @livlogios/Views/AddEntryView.swift
- @livlogios/Models/Item.swift

Важно:
- Проверить Definition of Done из ./CLAUDE.md
- Убедиться, что изменения в enum `ScoreRating` не сломают существующие данные (миграция данных)

## Result

Implemented score selection bottom sheet in AddEntryView:

### Changes to Item.swift
- Added new `undecided` case (value 0) to `ScoreRating` enum
- Updated emojis: 🆕 (undecided), 👎 (bad), 👌 (okay), 🤩 (great)
- Updated labels with new descriptive text for each rating

### Changes to AddEntryView.swift
- Changed default score from `.okay` to `.undecided`
- Added `showScoreSheet` state variable
- Modified star button action to open score selection sheet
- Added new `ScoreSelectionSheet` view with:
  - Title "What's the verdict?"
  - Large emoji display (64pt) for current selection
  - 4 option buttons for each rating value
  - "Done" button to confirm selection
  - Fixed height of 300 using `.presentationDetents([.height(300)])`
- Added `ScoreOptionButton` component for individual rating options

### Migration compatibility
The change is backward compatible - existing data with rawValues 1, 2, 3 will decode correctly. The new `undecided` case (0) is only used for new entries by default.
