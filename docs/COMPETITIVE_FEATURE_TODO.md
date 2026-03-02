# StockFlou — TODO roadmap по итогам сравнения с ImStocker Studio

> Цель: зафиксировать, каких фич не хватает StockFlou относительно конкурента, и в каком порядке их внедрять.

## 1) Что уже есть в текущем продукте (кратко)


## 0) Что уже сделано в этой итерации

- [x] Добавлен базовый Upload Queue Manager с персистентными upload jobs в SQLite (`upload_jobs`).
- [x] Добавлено управление задачами: enqueue, start processing, pause/resume, retry, cancel/cancel-all.
- [x] Добавлен workflow-статус в модель файлов и БД (`workflow_status`) с ключевыми этапами pipeline.
- [x] Реализована автоматическая смена статуса файла на `metadata_ready` при сохранении metadata и на `uploaded` после успешной задачи upload queue.
- [x] Экран Upload Queue переведён с моков на реальные данные очереди.
- [~] FTPS/SFTP transport пока реализован как phase-1 gateway: проверка сетевого соединения с хостом/портом + управляемый прогресс; полноценная передача файла будет в следующей итерации.

---

- [x] Desktop-приложение на Flutter с локальным workspace и SQLite state.
- [x] Импорт и отображение локальных файлов из рабочей папки.
- [x] Поддержка изображений (`jpg/jpeg/png`) и видео (`mp4/mov/avi/mkv/m4v`) в основном потоке работы.
- [x] AI-генерация metadata (title/description/keywords) через внешний API.
- [x] Ручное редактирование metadata и запись metadata в файл через exiftool.
- [x] Базовые editorial-поля (city/country/date), автоподстановка гео по GPS.
- [x] Настройки API-ключа и сохранение FTP/SFTP credentials (Adobe/Shutterstock).
- [~] Экран очереди Upload/History есть как UI-концепт, но без реального upload-движка.
- [ ] Отдельные разделы Uploads/Analytics в навигации пока заглушки.

---

## 2) Приоритетный TODO (что внедрять)

## P0 — must have (ядро для выхода в прод)

- [~] **Реальный Upload Manager (FTPS/SFTP) с очередью задач**
  - Что делать:
    - Сделать сервис очереди загрузок: `pending -> uploading -> success/error/paused`.
    - Подключить transport-слой для FTPS/SFTP, использовать сохранённые credentials из Settings.
    - Добавить retry policy, паузу/возобновление, отмену одной задачи и `Cancel all`.
  - Как должно работать:
    - Пользователь выбирает файлы и сток, нажимает Upload.
    - Задачи попадают в очередь и исполняются в фоне с ограничением параллелизма.
    - В UI видны прогресс, скорость, причина ошибки, timestamp и действие Retry.

- [~] **Workflow-статусы файлов и pipeline**
  - Что делать:
    - Добавить в модель/БД статус жизненного цикла: `new`, `metadata_ready`, `qc_failed`, `ready_to_upload`, `uploaded`, `submitted`.
    - Реализовать массовую смену статусов и фильтры по статусу.
  - Как должно работать:
    - Каждый файл имеет понятную стадию.
    - Пользователь в один клик видит, что готово к загрузке и что заблокировано QC.

- [ ] **QC Checker перед upload**
  - Что делать:
    - Встроить валидатор: минимум/максимум keywords, пустые title/description, дубли keywords, запрещённые символы, длины полей под требования стока.
    - Сделать отчёт проверок на файл и batch.
  - Как должно работать:
    - При запуске upload система показывает предупреждения/ошибки.
    - Ошибки блокируют upload, предупреждения допускают upload с подтверждением.

- [ ] **Batch metadata operations (массовое редактирование)**
  - Что делать:
    - Поддержать множественное выделение + массовое применение title/description/keywords/category/template.
    - Добавить режим merge/replace для keywords.
  - Как должно работать:
    - Пользователь выбирает N файлов и применяет изменения один раз.
    - Есть preview изменений перед подтверждением.

- [ ] **Расширение форматов файлов до конкурентного минимума**
  - Что делать:
    - Добавить поддержку `EPS`, `SVG`, популярных RAW-форматов (минимум read/preview metadata pipeline).
    - Продумать fallback для форматов без предпросмотра.
  - Как должно работать:
    - Файлы этих типов импортируются, участвуют в batch-операциях и upload-пайплайне.

## P1 — strong differentiators (следующий слой ценности)

- [ ] **Metadata templates (шаблоны) + пресеты для сценариев**
  - Что делать:
    - Реализовать CRUD шаблонов: title pattern, description blocks, keyword sets, editorial defaults.
    - Поддержать применение шаблона к выборке.
  - Как должно работать:
    - Пользователь сохраняет «шаблон серии» и применяет его к новым партиям за 1 действие.

- [ ] **Keywording Engine v2**
  - Что делать:
    - Добавить ranking/priority keywords, dedupe, ограничение количества слов по стоку, быстрый reorder.
    - Добавить quality-метрики keywords (длина, повторы, покрытие темы).
  - Как должно работать:
    - Ключевые слова автоматически упорядочены и соответствуют лимитам целевого стока.

- [ ] **Разные metadata профили для разных стоков**
  - Что делать:
    - Ввести сущность `stock_profile_metadata` для файла.
    - UI переключения профиля (Adobe/Shutterstock/другие).
  - Как должно работать:
    - Один и тот же ассет может иметь разные title/keywords под конкретный сток.

- [ ] **CSV import/export metadata**
  - Что делать:
    - Экспорт текущих metadata в CSV + импорт с валидацией колонок/ID.
    - Обработка конфликтов (overwrite/skip/merge).
  - Как должно работать:
    - Пользователь редактирует данные в Excel/Sheets и безопасно синхронизирует обратно.

- [ ] **Готовые интеграции upload-профилей по стокам**
  - Что делать:
    - Добавить конфигурации платформ (порт, протокол, папки, лимиты, правила filename).
    - Валидация credentials и кнопка Test Connection.
  - Как должно работать:
    - Подключение нового стока выполняется через мастер, без ручной отладки параметров.

## P2 — scale & pro capabilities

- [ ] **Collections + Lightbox (избранное и тематические наборы)**
  - Что делать:
    - Реализовать коллекции поверх файлов из разных папок/workspaces.
    - Добавить pinned collections, быстрые фильтры и batch actions по коллекции.
  - Как должно работать:
    - Пользователь формирует «пакеты к публикации» независимо от физического расположения файлов.

- [ ] **Translation tools для metadata**
  - Что делать:
    - Добавить автоперевод title/description/keywords на выбранные языки.
    - Поддержать batch translate и ручную правку результата.
  - Как должно работать:
    - На выходе пользователь получает локализованные metadata-пакеты для multi-market.

- [ ] **Сабмит после upload (где поддерживается)**
  - Что делать:
    - Добавить шаг submission (или подготовку файла/CSV по требованиям платформы).
  - Как должно работать:
    - После успешной загрузки файл автоматически проходит в этап submit/ready-to-submit.

- [ ] **ZIP pipeline для векторных наборов**
  - Что делать:
    - Генерировать ZIP-бандлы (EPS+preview JPEG+metadata sidecar при необходимости).
  - Как должно работать:
    - Векторные ассеты автоматически приводятся к формату передачи, принятому стоком.

## P3 — future / roadmap (после стабилизации P0-P2)

- [ ] **AI keyword generation нового поколения** (модели/переранжирование/семантические группы).
- [ ] **AI description/title optimization под конкретный сток.**
- [ ] **Duplicate & similar detection** (визуальные дубликаты, near-duplicates).
- [ ] **Reject analytics** (причины отказов, рекомендации по исправлениям).
- [ ] **Sales/revenue analytics** (если появятся доступные интеграции).
- [ ] **Cloud workspace + collaboration** (мультипользовательский режим).

---

## 3) Техническая декомпозиция (минимум для старта)

- [ ] **Data layer**
  - Миграции БД: статусы workflow, upload_job, upload_attempt, stock_profile_metadata, collection.
- [ ] **Domain layer**
  - Use cases: queue upload, run qc, apply template, batch edit, import/export csv.
- [ ] **UI layer**
  - Полноценные экраны Uploads и Analytics (убрать заглушки), расширить History реальными данными.
- [ ] **Reliability**
  - Логи задач, идемпотентность повторных запусков, восстановление очереди после рестарта.
- [ ] **Observability**
  - Система понятных ошибок + диагностика соединения (network/auth/permission).

---

## 4) Definition of Done для каждой фичи

- [ ] Есть user flow в UI (happy path + ошибки).
- [ ] Есть сохранение состояния (перезапуск приложения не ломает сценарий).
- [ ] Есть batch-поведение на 1k+ файлов без freeze UI.
- [ ] Есть тесты: unit + integration на критический путь.
- [ ] Есть документация в `README/docs`.

---

## 5) Рекомендуемая последовательность релизов

- [ ] **Release 1:** Upload Queue + Workflow statuses + QC + Batch edit.
- [ ] **Release 2:** Templates + Stock-specific metadata + CSV + Test Connection.
- [ ] **Release 3:** Collections/Lightbox + Translation + Vector ZIP + Submission flow.
- [ ] **Release 4:** AI/analytics roadmap (duplicates, reject analysis, revenue/cloud).
