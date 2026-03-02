import 'package:flutter/material.dart';
import '../../../../models/app_file.dart';
import '../../../../models/qc_report.dart';

class QcReportDialog extends StatelessWidget {
  final List<AppFile> files;
  final Map<String, QcReport> reports;

  const QcReportDialog({super.key, required this.files, required this.reports});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalIssues = reports.values
        .map((r) => r.issues.length)
        .fold(0, (a, b) => a + b);

    final bool hasErrors = reports.values.any((r) => r.hasErrors);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasErrors ? Icons.error_outline : Icons.warning_amber_rounded,
                  color: hasErrors ? Colors.red : Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasErrors ? 'Ошибки проверки (QC)' : 'Предупреждения (QC)',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Найдено $totalIssues проблем в ${reports.length} файлах. '
              '${hasErrors ? 'Их необходимо исправить перед загрузкой.' : 'Вы уверены, что хотите продолжить?'}',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Builder(
                builder: (context) {
                  final filesWithReports = files
                      .where((f) => reports.containsKey(f.id))
                      .toList();
                  return ListView.builder(
                    itemCount: filesWithReports.length,
                    itemBuilder: (context, index) {
                      final file = filesWithReports[index];
                      final report = reports[file.id]!;
                      return _FileReportCard(file: file, report: report);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: hasErrors
                      ? null
                      : () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: hasErrors ? Colors.grey : Colors.orange,
                  ),
                  child: Text(
                    hasErrors ? 'Заблокировано' : 'Продолжить загрузку',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FileReportCard extends StatelessWidget {
  final AppFile file;
  final QcReport report;

  const _FileReportCard({required this.file, required this.report});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              file.filename,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...report.issues.map(
              (issue) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      issue.isError ? Icons.cancel : Icons.warning,
                      size: 14,
                      color: issue.isError ? Colors.red : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '[${issue.field}] ${issue.message}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
