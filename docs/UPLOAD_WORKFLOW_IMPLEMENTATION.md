# Upload Queue + Workflow Statuses — текущая реализация

## Что реализовано

### 1. Workflow-статусы файлов
- В `AppFile` добавлено поле `workflowStatus`.
- Поддерживаемые статусы:
  - `new`
  - `metadata_ready`
  - `qc_failed`
  - `ready_to_upload`
  - `uploaded`
  - `submitted`
- Статус хранится в таблице `files` в колонке `workflow_status`.

### 2. Upload jobs и очередь
- Добавлена таблица `upload_jobs`.
- Для каждой задачи храним:
  - привязку к файлу (`file_id`, `file_path`, `filename`)
  - целевой сток (`stock_key`)
  - протокол (`sftp|ftps`)
  - статус (`pending|uploading|paused|success|error|cancelled`)
  - прогресс и текст ошибки
  - `created_at` / `updated_at`

### 3. UploadQueueNotifier
Реализованы сценарии:
- `enqueueFiles`
- `processQueue`
- `pauseJob`
- `resumeJob`
- `retryJob`
- `cancelJob`
- `cancelAll`

Поведение:
- В очередь попадают только файлы со статусом `metadata_ready` или `ready_to_upload`.
- При enqueue файл переводится в `ready_to_upload`.
- При успешном выполнении upload job файл переводится в `uploaded`.

### 4. Transport phase-1
Сделан `SocketHandshakeUploadGateway`:
- проверяет сетевое соединение с host:port (`22` для SFTP, `21` для FTPS);
- эмулирует пошаговый прогресс upload.

Это **не финальный транспорт файлов**, а безопасный этап для:
- проверки очереди, retry/pause/cancel,
- проверки credentials/доступности сервера,
- интеграции UI и персистентного состояния.

## Что дальше (следующий инкремент)
- Подключить реальный FTPS/SFTP transfer (streaming файла).
- Добавить ограничение параллелизма очереди и приоритеты.
- Добавить upload attempts/history и расширенный error taxonomy.
- Добавить предзагрузочный QC-блокер перед enqueue.
