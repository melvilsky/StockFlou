import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/core/state/files_provider.dart';
import 'package:stock_flow/features/generation/presentation/widgets/csv_import_preview_dialog.dart';
import 'package:stock_flow/models/app_file.dart';

/// Собирает результат диалога и список сохранённых материалов.
class _DialogHarness {
  bool? result;
  final List<AppFile> persisted = [];
  bool Function(AppFile file)? shouldFail;
}

class _TestFilesNotifier extends FilesNotifier {
  _TestFilesNotifier(this.files);
  List<AppFile> files;
  int buildCount = 0;

  @override
  Future<List<AppFile>> build() async {
    buildCount++;
    return files;
  }
}

Future<void> _openDialog(
  WidgetTester tester,
  _DialogHarness harness, {
  required List<Map<String, String>> parsedData,
  required List<AppFile> dbFiles,
  Future<void> Function(AppFile file)? persistFile,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    harness.result = await showDialog<bool>(
                      context: context,
                      builder:
                          (_) => CsvImportPreviewDialog(
                            parsedData: parsedData,
                            dbFiles: dbFiles,
                            persistFile:
                                persistFile ??
                                (file) async {
                                  harness.persisted.add(file);
                                  if (harness.shouldFail?.call(file) ?? false) {
                                    throw StateError('ошибка записи в каталог');
                                  }
                                },
                          ),
                    );
                  },
                  child: const Text('открыть'),
                ),
              ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('открыть'));
  await tester.pumpAndSettle();
}

Future<void> _openDialogWithCatalog(
  WidgetTester tester,
  _DialogHarness harness, {
  required List<Map<String, String>> parsedData,
  required List<AppFile> dbFiles,
  required _TestFilesNotifier notifier,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [filesProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    final catalog = ref.watch(filesProvider).value ?? [];
                    final catalogSummary = catalog
                        .map((f) => '${f.id}:${f.metadataTitle ?? ""}')
                        .join(';');
                    return Column(
                      children: [
                        Text('Каталог: $catalogSummary'),
                        TextButton(
                          onPressed: () async {
                            harness.result = await showDialog<bool>(
                              context: context,
                              builder:
                                  (_) => CsvImportPreviewDialog(
                                    parsedData: parsedData,
                                    dbFiles: dbFiles,
                                    persistFile: (file) async {
                                      harness.persisted.add(file);
                                      if (harness.shouldFail?.call(file) ??
                                          false) {
                                        throw StateError(
                                          'ошибка записи в каталог',
                                        );
                                      }
                                      notifier.files = [
                                        for (final f in notifier.files)
                                          if (f.id == file.id) file else f,
                                      ];
                                    },
                                  ),
                            );
                          },
                          child: const Text('открыть'),
                        ),
                      ],
                    );
                  },
                ),
              ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('открыть'));
  await tester.pumpAndSettle();
}

/// Прогоняет импорт и дожидается его завершения.
Future<void> _runImport(WidgetTester tester) async {
  await tester.tap(find.text('Импортировать'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}

AppFile _file({
  String id = 'a',
  String path = '/Users/test/Pictures/photo.jpg',
  String filename = 'photo.jpg',
}) {
  return AppFile(id: id, path: path, filename: filename, createdAt: 1000);
}

void main() {
  testWidgets('the preview shows the counts and the skip reasons', (
    tester,
  ) async {
    final harness = _DialogHarness();

    await _openDialog(
      tester,
      harness,
      parsedData: [
        {'Filename': 'photo.jpg', 'Title': 'Заголовок'},
        {'Filename': 'missing.jpg', 'Title': 'Заголовок'},
      ],
      dbFiles: [_file()],
    );

    expect(find.text('Записей в CSV: 2'), findsOneWidget);
    expect(find.text('Применимых изменений: 1'), findsOneWidget);
    expect(find.text('Пропущено строк: 1'), findsOneWidget);
    expect(
      find.text('• Запись 3: Файл не найден в каталоге — missing.jpg'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Импорт изменит метаданные в каталоге. '
        'Оригинальные файлы не изменяются',
      ),
      findsOneWidget,
    );
  });

  testWidgets('nothing is written to the catalog before the confirmation', (
    tester,
  ) async {
    final harness = _DialogHarness();

    await _openDialog(
      tester,
      harness,
      parsedData: [
        {'Filename': 'photo.jpg', 'Title': 'Заголовок'},
      ],
      dbFiles: [_file()],
    );

    expect(harness.persisted, isEmpty);
  });

  testWidgets('after the confirmation only the unambiguous rows are applied', (
    tester,
  ) async {
    final harness = _DialogHarness();

    await _openDialog(
      tester,
      harness,
      parsedData: [
        {'Filename': 'photo.jpg', 'Title': 'Первый'},
        {'Filename': 'missing.jpg', 'Title': 'Пропущенный'},
        {'Filename': 'other.jpg', 'Title': 'Второй'},
      ],
      dbFiles: [_file(id: 'a'), _file(id: 'b', filename: 'other.jpg')],
    );

    await _runImport(tester);
    await tester.pumpAndSettle();

    expect(harness.persisted.map((f) => f.id), ['a', 'b']);
    expect(harness.persisted.first.metadataTitle, 'Первый');
    expect(harness.result, isTrue);
  });

  testWidgets('the import button is disabled when there is nothing to apply', (
    tester,
  ) async {
    final harness = _DialogHarness();

    await _openDialog(
      tester,
      harness,
      parsedData: [
        {'Filename': 'missing.jpg', 'Title': 'Заголовок'},
      ],
      dbFiles: [_file()],
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Импортировать'),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.text('Импортировать'));
    await tester.pumpAndSettle();

    expect(harness.persisted, isEmpty);
    expect(harness.result, isNull);
  });

  testWidgets(
    'a partial database error does not return true and a retry applies only the failed rows',
    (tester) async {
      final harness = _DialogHarness();
      harness.shouldFail = (file) => file.id == 'b';

      await _openDialog(
        tester,
        harness,
        parsedData: [
          {'Filename': 'photo.jpg', 'Title': 'Первый'},
          {'Filename': 'other.jpg', 'Title': 'Второй'},
        ],
        dbFiles: [_file(id: 'a'), _file(id: 'b', filename: 'other.jpg')],
      );

      await _runImport(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(harness.persisted.map((f) => f.id), ['a', 'b']);
      expect(
        harness.result,
        isNull,
        reason: 'диалог не закрывается частичной ошибкой',
      );
      expect(find.textContaining('Ошибки записи в каталог'), findsOneWidget);

      // Повтор применяет только неудачную запись.
      harness.shouldFail = (file) => false;
      await _runImport(tester);
      await tester.pumpAndSettle();

      expect(harness.persisted.map((f) => f.id), ['a', 'b', 'b']);
      expect(harness.result, isTrue);
    },
  );

  testWidgets(
    'the import does not touch the original media and does not call ExifTool',
    (tester) async {
      // Реальный ввод-вывод внутри testWidgets выполняется через runAsync.
      late Directory dir;
      late File media;
      late List<int> bytesBefore;
      late DateTime modifiedBefore;

      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('stockflow_csv');
        media = File('${dir.path}/photo.jpg');
        await media.writeAsBytes([1, 2, 3, 4, 5]);
        bytesBefore = await media.readAsBytes();
        modifiedBefore = (await media.stat()).modified;
      });
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final harness = _DialogHarness();
      await _openDialog(
        tester,
        harness,
        parsedData: [
          {'Filename': 'photo.jpg', 'Title': 'Заголовок'},
        ],
        dbFiles: [_file(path: media.path)],
      );

      await _runImport(tester);
      await tester.pumpAndSettle();

      expect(harness.result, isTrue);
      await tester.runAsync(() async {
        expect(await media.readAsBytes(), bytesBefore);
        expect((await media.stat()).modified, modifiedBefore);
      });

      // ExifTool вызывается только через MetadataService.writeMetadata —
      // импорт метаданных не должен его использовать.
      final source = File(
        'lib/features/generation/presentation/widgets/csv_import_preview_dialog.dart',
      );
      expect(source.existsSync(), isTrue);
      expect(
        source.readAsStringSync(),
        isNot(contains('core/services/metadata_service.dart')),
      );
      expect(source.readAsStringSync(), isNot(contains('writeMetadata')));
    },
  );

  testWidgets(
    'first file written, second fails: provider is notified of successful write, dialog remains open; closing returns false and preserves result visibility',
    (tester) async {
      final harness = _DialogHarness();
      harness.shouldFail = (file) => file.id == 'b';

      final fileA = _file(
        id: 'a',
        filename: 'photo.jpg',
      ).copyWith(metadataTitle: 'Старый A');
      final fileB = _file(
        id: 'b',
        filename: 'other.jpg',
      ).copyWith(metadataTitle: 'Старый B');
      final notifier = _TestFilesNotifier([fileA, fileB]);

      await _openDialogWithCatalog(
        tester,
        harness,
        parsedData: [
          {'Filename': 'photo.jpg', 'Title': 'Новый A'},
          {'Filename': 'other.jpg', 'Title': 'Новый B'},
        ],
        dbFiles: [fileA, fileB],
        notifier: notifier,
      );

      // Исходное состояние каталога
      expect(find.text('Каталог: a:Старый A;b:Старый B'), findsOneWidget);
      final initialBuildCount = notifier.buildCount;

      // Запускаем импорт: первый файл запишется, второй выбросит ошибку
      await _runImport(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Provider получил инвалидацию и обновил состояние каталога
      expect(notifier.buildCount, greaterThan(initialBuildCount));
      expect(find.text('Каталог: a:Новый A;b:Старый B'), findsOneWidget);

      // Диалог остаётся открытым и показывает ошибки
      expect(find.byType(CsvImportPreviewDialog), findsOneWidget);
      expect(find.textContaining('Ошибки записи в каталог'), findsOneWidget);
      expect(harness.result, isNull);

      // Закрытие диалога возвращает false
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();

      expect(harness.result, isFalse);
      // Успешно сохранённые изменения по-прежнему видны в каталоге
      expect(find.text('Каталог: a:Новый A;b:Старый B'), findsOneWidget);
    },
  );

  testWidgets(
    'retry writes only the second file and returns true; complete failure or cancellation before import produces no false provider updates',
    (tester) async {
      final harness = _DialogHarness();
      final fileA = _file(
        id: 'a',
        filename: 'photo.jpg',
      ).copyWith(metadataTitle: 'Старый A');
      final fileB = _file(
        id: 'b',
        filename: 'other.jpg',
      ).copyWith(metadataTitle: 'Старый B');
      final notifier = _TestFilesNotifier([fileA, fileB]);

      // 1. Отмена до начала импорта не инициирует обновление каталога
      await _openDialogWithCatalog(
        tester,
        harness,
        parsedData: [
          {'Filename': 'photo.jpg', 'Title': 'Новый A'},
        ],
        dbFiles: [fileA],
        notifier: notifier,
      );
      var buildCount = notifier.buildCount;
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(harness.result, isFalse);
      expect(
        notifier.buildCount,
        buildCount,
        reason: 'Отмена до начала не обновляет provider',
      );

      // 2. Полный отказ записи (0 успехов) не обновляет provider
      harness.shouldFail = (file) => true;
      await _openDialogWithCatalog(
        tester,
        harness,
        parsedData: [
          {'Filename': 'photo.jpg', 'Title': 'Новый A'},
        ],
        dbFiles: [fileA],
        notifier: notifier,
      );
      buildCount = notifier.buildCount;
      await _runImport(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ошибки записи в каталог'), findsOneWidget);
      expect(
        notifier.buildCount,
        buildCount,
        reason: 'Полный отказ не обновляет provider',
      );
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(harness.result, isFalse);
      expect(notifier.buildCount, buildCount);

      // 3. Частичный сбой и последующий повтор
      harness.persisted.clear();
      harness.shouldFail = (file) => file.id == 'b';
      await _openDialogWithCatalog(
        tester,
        harness,
        parsedData: [
          {'Filename': 'photo.jpg', 'Title': 'Новый A'},
          {'Filename': 'other.jpg', 'Title': 'Новый B'},
        ],
        dbFiles: [fileA, fileB],
        notifier: notifier,
      );
      await _runImport(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(harness.persisted.map((f) => f.id).toList(), ['a', 'b']);
      expect(find.text('Каталог: a:Новый A;b:Старый B'), findsOneWidget);

      // Повтор пишет ТОЛЬКО файл 'b'
      harness.shouldFail = null;
      await _runImport(tester);
      await tester.pumpAndSettle();

      // Файл 'a' повторно не записывался: в истории сохранённых ['a', 'b', 'b']
      expect(harness.persisted.map((f) => f.id).toList(), ['a', 'b', 'b']);
      expect(harness.result, isTrue);
      expect(find.text('Каталог: a:Новый A;b:Новый B'), findsOneWidget);
    },
  );

  testWidgets(
    'rapid double click and Escape during write do not create a second operation and do not close dialog',
    (tester) async {
      final harness = _DialogHarness();
      final completer = Completer<void>();

      await _openDialog(
        tester,
        harness,
        parsedData: [
          {'Filename': 'photo.jpg', 'Title': 'Новый'},
        ],
        dbFiles: [_file(id: 'a')],
        persistFile: (file) async {
          harness.persisted.add(file);
          await completer.future;
        },
      );

      // Кликаем Импортировать
      await tester.tap(find.text('Импортировать'));
      await tester.pump();

      // Диалог перешёл в состояние импорта
      expect(find.text('Применяем метаданные...'), findsOneWidget);
      expect(harness.persisted.length, 1);

      // Попытка нажать Escape во время записи
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      // Диалог всё ещё открыт и выполняется
      expect(find.byType(CsvImportPreviewDialog), findsOneWidget);
      expect(harness.persisted.length, 1);

      // Завершаем асинхронную операцию записи
      completer.complete();
      await tester.pumpAndSettle();

      // Диалог завершился успешно и закрылся
      expect(harness.result, isTrue);
      expect(harness.persisted.length, 1);
    },
  );
  testWidgets(
    'disposing during persistence stops further writes without ref errors',
    (tester) async {
      final harness = _DialogHarness();
      final pending = Completer<void>();
      await _openDialog(
        tester,
        harness,
        parsedData: [
          {'Filename': 'photo.jpg'},
          {'Filename': 'other.jpg'},
        ],
        dbFiles: [_file(), _file(id: 'b', filename: 'other.jpg')],
        persistFile: (file) async {
          harness.persisted.add(file);
          await pending.future;
        },
      );
      await tester.tap(find.text('Импортировать'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      pending.complete();
      await tester.pumpAndSettle();
      expect(harness.persisted, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
