import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/app_file.dart';
import '../../../../models/csv_import_plan.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/services/csv_metadata_service.dart';
import '../../../../core/state/files_provider.dart';

class CsvImportPreviewDialog extends ConsumerStatefulWidget {
  final List<Map<String, String>> parsedData;
  final List<AppFile> dbFiles;

  /// Обработчик сохранения изменённого материала.
  ///
  /// По умолчанию используется реальный [DatabaseHelper]. Параметр нужен,
  /// чтобы тесты не трогали пользовательскую базу.
  final Future<void> Function(AppFile file)? persistFile;

  const CsvImportPreviewDialog({
    super.key,
    required this.parsedData,
    required this.dbFiles,
    this.persistFile,
  });

  @override
  ConsumerState<CsvImportPreviewDialog> createState() =>
      _CsvImportPreviewDialogState();
}

class _CsvImportPreviewDialogState
    extends ConsumerState<CsvImportPreviewDialog> {
  late final CsvImportPlan _plan;

  /// Изменения, которые ещё не применены (после частичной ошибки — только
  /// неудачные).
  List<CsvImportChange> _pending = const [];

  bool _isImporting = false;
  int _appliedCount = 0;
  final List<String> _errors = [];

  @override
  void initState() {
    super.initState();
    _plan = CsvMetadataService.buildImportPlan(
      widget.parsedData,
      widget.dbFiles,
    );
    _pending = _plan.changes;
  }

  Future<void> _performImport() async {
    if (_isImporting || _pending.isEmpty) return;

    setState(() {
      _isImporting = true;
      _errors.clear();
    });

    final applied = <CsvImportChange>[];
    final failed = <CsvImportChange>[];
    final errors = <String>[];

    for (final change in _pending) {
      if (!mounted) break;
      try {
        await _persist(change.file);
        applied.add(change);
      } catch (e) {
        failed.add(change);
        errors.add(
          'Запись ${change.recordNumber}: ${change.sourceFilename} — $e',
        );
      }
    }

    if (!mounted) return;

    if (applied.isNotEmpty) {
      ref.invalidate(filesProvider);
    }

    setState(() {
      _appliedCount += applied.length;
      _pending = failed;
      _errors
        ..clear()
        ..addAll(errors);
      _isImporting = false;
    });

    if (failed.isEmpty) {
      Navigator.of(context).pop(true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Применено ${applied.length}, с ошибкой ${failed.length}. '
          'Повторите импорт — он применит только неудачные записи.',
        ),
      ),
    );
  }

  Future<void> _persist(AppFile file) async {
    final handler = widget.persistFile;
    if (handler != null) {
      await handler(file);
      return;
    }
    await DatabaseHelper.instance.updateFile(file);
  }

  String _describeProblem(CsvImportProblem problem) {
    final subject =
        problem.sourceFilename.isNotEmpty
            ? problem.sourceFilename
            : problem.sourcePath;
    if (subject.isEmpty) {
      return 'Запись ${problem.recordNumber}: ${problem.reason}';
    }
    return 'Запись ${problem.recordNumber}: ${problem.reason} — $subject';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_isImporting,
      child: AlertDialog(
        title: const Text('Превью импорта CSV'),
        content: SizedBox(
          width: 520,
          child:
              _isImporting
                  ? const SizedBox(
                    height: 120,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Применяем метаданные...'),
                        ],
                      ),
                    ),
                  )
                  : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Записей в CSV: ${_plan.totalRecords}'),
                      const SizedBox(height: 4),
                      Text(
                        'Применимых изменений: ${_plan.changes.length}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color:
                              _plan.changes.isEmpty ? Colors.red : Colors.green,
                        ),
                      ),
                      Text(
                        'Пропущено строк: ${_plan.problems.length}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color:
                              _plan.problems.isEmpty
                                  ? Colors.green
                                  : Colors.red,
                        ),
                      ),
                      if (_appliedCount > 0)
                        Text('Уже применено: $_appliedCount'),
                      const SizedBox(height: 12),
                      const Text(
                        'Импорт изменит метаданные в каталоге. '
                        'Оригинальные файлы не изменяются',
                        style: TextStyle(color: Colors.orange),
                      ),
                      if (_errors.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Ошибки записи в каталог:',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final error in _errors)
                                  Text(
                                    '• $error',
                                    style: const TextStyle(color: Colors.red),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_plan.problems.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Пропущенные записи:',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 160),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final problem in _plan.problems)
                                  Text('• ${_describeProblem(problem)}'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
        ),
        actions:
            _isImporting
                ? null
                : [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      _errors.isEmpty && _appliedCount == 0
                          ? 'Отмена'
                          : 'Закрыть',
                    ),
                  ),
                  FilledButton(
                    onPressed: _pending.isEmpty ? null : _performImport,
                    child: const Text('Импортировать'),
                  ),
                ],
      ),
    );
  }
}
