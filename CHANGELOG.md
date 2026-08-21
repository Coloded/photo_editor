# Changelog / История изменений

## 1.4.1 — 2026-08-21

### English

- Fixed launch failure on clean Apple Silicon Macs caused by a missing embedded-framework runtime path.
- Added the standard `@executable_path/../Frameworks` runtime search path for Sparkle.
- Added a mandatory build check that prevents publishing an app without the embedded-framework path.
- Confirmed the target remains native ARM64 for macOS 13 and later, including current Apple Silicon Macs and macOS releases.

### Русский

- Исправлен сбой запуска на чистых Mac с Apple Silicon из-за отсутствующего пути загрузки встроенного framework.
- Для Sparkle добавлен стандартный путь `@executable_path/../Frameworks`.
- В сборочный скрипт добавлена обязательная проверка, не позволяющая опубликовать приложение без этого пути.
- Подтверждена нативная ARM64-совместимость с macOS 13 и новее, включая актуальные Mac с Apple Silicon и версии macOS.

## 1.4 — 2026-08-21

### English

- Added secure in-app updates with Sparkle 2.9.2.
- Added a bilingual custom About window with update controls.
- Added manual and automatic stable update checks.
- Added EdDSA signing for update archives and the appcast feed.
- Added a permanent `releases/latest/download/Photo_Editor-stable.dmg` download URL.
- The saved RU/EN language is applied to the About and update interface.

### Русский

- Добавлено безопасное самообновление через Sparkle 2.9.2.
- Добавлено двуязычное окно «О программе» с управлением обновлениями.
- Добавлена ручная и автоматическая проверка стабильных обновлений.
- Добавлена EdDSA-подпись образов обновлений и ленты appcast.
- Добавлена постоянная ссылка `releases/latest/download/Photo_Editor-stable.dmg`.
- Сохранённый язык RU/EN применяется в окне «О программе» и интерфейсе обновлений.

## 1.3 — 2026-08-19

### English

- The build script now creates and verifies an installable DMG by default.
- The DMG contains Photo_Editor and an Applications folder shortcut.
- Added GitHub Actions automation for ARM64 DMG artifacts and tagged releases.
- ZIP creation remains available as the optional `--archive` output.
- Local builds install the app into `/Applications` after confirmation; CI uses `--no-install`.

### Русский

- Скрипт сборки теперь по умолчанию создаёт и проверяет установочный DMG.
- В DMG находятся Photo_Editor и ярлык папки Applications.
- Добавлена автоматическая сборка ARM64-DMG и релизов через GitHub Actions.
- Создание ZIP оставлено дополнительным параметром `--archive`.
- Локальная сборка после подтверждения устанавливает приложение в `/Applications`; для CI предусмотрен `--no-install`.

## 1.2 — 2026-08-19

### English

- Added image paste from the macOS clipboard with Command–V and Edit → Paste.
- Clipboard paste works in both single-photo and mosaic modes.
- Mosaic mode accepts multiple clipboard image providers when available.
- Added bilingual clipboard hints to the empty editor states.
- Reworked the build script with dependency checks, compatible SDK discovery, actionable errors, archive verification, and optional confirmed installation.

### Русский

- Добавлена вставка изображений из буфера обмена macOS через Command–V и «Правка → Вставить».
- Вставка работает в режимах «Одно фото» и «Мозаика».
- Режим мозаики принимает несколько изображений из буфера, когда они доступны.
- В пустые состояния редактора добавлены подсказки на русском и английском языках.
- Переработан скрипт сборки: добавлены проверка зависимостей, поиск совместимого SDK, понятные ошибки, проверка архива и установка только после подтверждения.

## 1.1 — 2026-08-19

### English

- Renamed the application to Photo_Editor.
- Added Russian and English interface languages with persistent selection.
- Added the custom About panel.
- Added single-photo print sizing and standard presets.
- Added Metal-accelerated blur and vector annotation tools.
- Added mosaic grid and free-layout modes.
- Added A0–A6 paper formats, automatic arrangement, snapping, and neighbor pushing.
- Preserved full source photos during automatic mosaic arrangement.
- Added PDF, JPG, PNG, HEIC, and TIFF export workflows.
- Added Apple Photos drag-and-drop support.

### Русский

- Приложение переименовано в Photo_Editor.
- Добавлены русский и английский языки с запоминанием выбора.
- Добавлено собственное окно «О программе».
- Добавлены размеры печати и стандартные форматы фотографий.
- Добавлены ускоренное через Metal размытие и инструменты разметки.
- Добавлены режимы ровной сетки и свободной мозаики.
- Добавлены листы A0–A6, авторасстановка, прилипание и раздвигание соседей.
- Автоматическая мозаика сохраняет фотографии целиком без обрезки.
- Добавлен экспорт в PDF, JPG, PNG, HEIC и TIFF.
- Добавлено перетаскивание из приложения Apple «Фото».
