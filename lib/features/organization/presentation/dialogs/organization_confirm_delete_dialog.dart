import 'package:flutter/material.dart';

/// Диалог подтверждения организационного удаления (проекта, коллекции,
/// ссылки на материал или очистки отбора).
///
/// Чётко объясняет последствия: удаляется только организационная запись;
/// физические файлы на диске, метаданные и история загрузок остаются в сохранности.
class OrganizationConfirmDeleteDialog extends StatelessWidget {
  final String title;
  final String? entityName;
  final String explanation;
  final String confirmButtonText;

  const OrganizationConfirmDeleteDialog({
    super.key,
    required this.title,
    this.entityName,
    this.explanation =
        'Будет удалена только организационная запись. Оригинальные файлы '
        'на диске, их метаданные и история загрузок останутся без изменений.',
    this.confirmButtonText = 'Удалить',
  });

  static Future<bool> show({
    required BuildContext context,
    required String title,
    String? entityName,
    String explanation =
        'Будет удалена только организационная запись. Оригинальные файлы '
        'на диске, их метаданные и история загрузок останутся без изменений.',
    String confirmButtonText = 'Удалить',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => OrganizationConfirmDeleteDialog(
        title: title,
        entityName: entityName,
        explanation: explanation,
        confirmButtonText: confirmButtonText,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entityName != null && entityName!.isNotEmpty) ...[
              Text(
                entityName!,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      explanation,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.9),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          key: const Key('organization_delete_cancel_button'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const Key('organization_delete_confirm_button'),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmButtonText),
        ),
      ],
    );
  }
}
