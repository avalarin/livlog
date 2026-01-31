Переделать AI помощника в AddEntryView: вместо автоматического поиска при нажатии на sparkles открывать bottom sheet с возможностью ввода поискового запроса и отображением топ 5 результатов

Функциональные требования:
- При нажатии на кнопку sparkles в AddEntryView должен открываться bottom sheet;
- В bottom sheet должно быть текстовое поле с плейсхолдером "Tell me what you want to discover";
- Справа от текстового поля кнопка с иконкой лупы (magnifyingglass) для запуска поиска;
- При нажатии на кнопку запускается поиск через метод `OpenAIService.searchOptions(for:)`;
- Пока идет поиск:
  - Текстовое поле должно быть заблокировано (disabled);
  - Кнопка с лупой должна превратиться в кнопку стоп (xmark.circle.fill) для остановки поиска;
  - Должна быть возможность отменить/остановить поиск;
  - Во время поиска дожен показываться текст "Exploring options…" и какой-то стандартный iOS способ показать анимацию прогресса;
- После завершения поиска:
  - Ниже поля поиска должны появиться топ 5 найденных вариантов;
  - Каждый вариант - это title, description, image (если есть)
- При выборе варианта из списка:
  - Данные применяются к текущей форме (title, description, images)
  - Bottom sheet закрывается

Визуальные требования:
- Bottom sheet должен открываться снизу с плавной анимацией;
- Использовать стандартные `.presentationDetents([.medium, .large])` для bottom sheet;
- Поле поиска и кнопка должны быть в горизонтальном HStack;
- Кнопка поиска: круглая кнопка с иконкой на accent color;
- Список результатов должен использовать существующий `AIHelperOptionCard` компонент;
- UI должен соответствовать общему дизайну приложения (скругленные углы, тени.

Files:
- @livlogios/Views/AddEntryView.swift

Важные моменты:
- Не должно быть автоматического поиска при открытии bottom sheet
- Пользователь должен явно ввести текст и нажать кнопку поиска
- Поиск должен быть отменяемым через Task cancellation
- Bottom sheet должен оставаться открытым после выбора результата только если пользователь не нажал на вариант
- После применения выбранного варианта bottom sheet должен закрываться

Important:
- Check Definition of Done from ./CLAUDE.md

## Result

Implemented AI search bottom sheet in AddEntryView:

### Changes to AddEntryView.swift

**Removed:**
- `isLoadingOptions` state variable
- `showOptionsSheet` state variable
- `foundOptions` state variable
- `canUseAIHelper` computed property
- `searchWithAI()` function
- `LoadingSheet` component
- `OptionsSelectionSheet` component

**Added:**
- `showAISearchSheet` state variable
- New `AISearchBottomSheet` component with:
  - Text field with placeholder "Tell me what you want to discover"
  - Search button (magnifying glass) that transforms to stop button (xmark.circle.fill) during search
  - Progress indicator with "Exploring options…" text during search
  - Task cancellation support via `searchTask` state
  - Display of top 5 search results using existing `AIHelperOptionCard`
  - Error message display
  - Initial query pre-filled from entry title

**Modified:**
- Sparkles button action now opens `showAISearchSheet` instead of calling `searchWithAI()` directly
- Bottom sheet uses `.presentationDetents([.medium, .large])`

### Behavior
1. User taps sparkles button → bottom sheet opens with title pre-filled
2. User can edit search query and tap search button
3. During search: text field disabled, button shows stop icon, progress shown
4. User can tap stop button to cancel search
5. Results appear below search field (max 5)
6. Tapping a result applies it to the entry and closes the sheet
