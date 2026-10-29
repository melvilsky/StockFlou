import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_flow/core/services/csv_metadata_service.dart';
import 'package:stock_flow/models/app_file.dart';
import 'package:stock_flow/models/csv_import_plan.dart';
import 'package:stock_flow/models/workflow_status.dart';

AppFile _file({
  String id = 'a',
  String path = '/Users/test/Pictures/photo.jpg',
  String filename = 'photo.jpg',
  String? title,
  String? description,
  String? keywords,
  bool isEditorial = false,
  String? city,
  String? country,
  int? editorialDate,
  List<String> tags = const [],
  int createdAt = 1000,
}) {
  return AppFile(
    id: id,
    path: path,
    filename: filename,
    metadataTitle: title,
    metadataDescription: description,
    metadataKeywords: keywords,
    isEditorial: isEditorial,
    editorialCity: city,
    editorialCountry: country,
    editorialDate: editorialDate,
    tags: tags,
    createdAt: createdAt,
  );
}

void main() {
  group('export', () {
    test('keeps the seven legacy columns and appends Description and Path', () {
      final csv = CsvMetadataService.exportToCsv([_file()]);

      final header = csv.split('\r\n').first;
      expect(
        header,
        'Filename,Title,Keywords,IsEditorial,EditorialCity,EditorialCountry,'
        'EditorialDate,Description,Path',
      );
    });

    test('writes the current full path into the Path column', () {
      final csv = CsvMetadataService.exportToCsv([
        _file(path: '/Users/test/Pictures/sub/photo.jpg'),
      ]);

      expect(csv, contains('/Users/test/Pictures/sub/photo.jpg'));
    });
  });

  group('round trip', () {
    test(
      'export → parse → plan keeps title, description, keywords and editorial values',
      () {
        final source = _file(
          title: 'Заголовок',
          description: 'Описание материала',
          keywords: 'a, b, c',
          isEditorial: true,
          city: 'Berlin',
          country: 'Germany',
          editorialDate: DateTime(2024, 5, 17, 10, 30).millisecondsSinceEpoch,
        );

        final rows = CsvMetadataService.parseCsv(
          CsvMetadataService.exportToCsv([source]),
        );
        final plan = CsvMetadataService.buildImportPlan(rows, [source]);

        expect(plan.problems, isEmpty);
        expect(plan.changes, hasLength(1));

        final updated = plan.changes.single.file;
        expect(updated.metadataTitle, 'Заголовок');
        expect(updated.metadataDescription, 'Описание материала');
        expect(updated.metadataKeywords, 'a, b, c');
        expect(updated.isEditorial, isTrue);
        expect(updated.editorialCity, 'Berlin');
        expect(updated.editorialCountry, 'Germany');
        expect(updated.editorialDate, source.editorialDate);
      },
    );

    test(
      'export → parse → plan keeps id, path, filename, createdAt and workflow status',
      () {
        final source = _file(title: 'Заголовок');

        final rows = CsvMetadataService.parseCsv(
          CsvMetadataService.exportToCsv([source]),
        );
        final updated =
            CsvMetadataService.buildImportPlan(rows, [
              source,
            ]).changes.single.file;

        expect(updated.id, source.id);
        expect(updated.path, source.path);
        expect(updated.filename, source.filename);
        expect(updated.createdAt, source.createdAt);
        expect(updated.workflowStatus, source.workflowStatus);
        expect(updated.workflowStatus, isNot(WorkflowStatus.readyToUpload));
      },
    );

    test(
      'quotes, commas, unicode, multiline values and leading zeros survive',
      () {
        final source = _file(
          filename: '007.jpg',
          path: '/Users/test/Pictures/007.jpg',
          title: 'Кавычки "внутри", и запятая',
          description: 'Первая строка\nВторая строка',
          keywords: '007, 42, лид-нули',
        );

        final csv = CsvMetadataService.exportToCsv([source]);
        final rows = CsvMetadataService.parseCsv(csv);
        final plan = CsvMetadataService.buildImportPlan(rows, [source]);

        expect(plan.problems, isEmpty);
        final updated = plan.changes.single.file;
        expect(updated.filename, '007.jpg');
        expect(updated.metadataTitle, 'Кавычки "внутри", и запятая');
        expect(updated.metadataDescription, 'Первая строка\nВторая строка');
        expect(updated.metadataKeywords, '007, 42, лид-нули');
      },
    );
  });

  group('parsing', () {
    test('reads CRLF and LF documents the same way', () {
      const crlf = 'Filename,Title\r\nphoto.jpg,Заголовок\r\n';
      const lf = 'Filename,Title\nphoto.jpg,Заголовок\n';

      expect(CsvMetadataService.parseCsv(crlf), [
        {'Filename': 'photo.jpg', 'Title': 'Заголовок'},
      ]);
      expect(CsvMetadataService.parseCsv(lf), [
        {'Filename': 'photo.jpg', 'Title': 'Заголовок'},
      ]);
    });

    test(
      'keeps a newline inside a quoted value and counts it as one record',
      () {
        const csv = 'Filename,Description\nphoto.jpg,"строка1\nстрока2"\n';

        final rows = CsvMetadataService.parseCsv(csv);

        expect(rows, hasLength(1));
        expect(rows.single['Description'], 'строка1\nстрока2');
      },
    );

    test('keeps a CRLF inside a quoted value', () {
      const csv = 'Filename,Description\r\nphoto.jpg,"строка1\r\nстрока2"\r\n';

      final rows = CsvMetadataService.parseCsv(csv);

      expect(rows, hasLength(1));
      expect(rows.single['Description'], 'строка1\r\nстрока2');
    });

    test('removes the UTF-8 BOM only at the start of the document', () {
      final csv = '\uFEFFFilename,Title\nphoto.jpg,Заголовок\n';

      final rows = CsvMetadataService.parseCsv(csv);

      expect(rows.single['Filename'], 'photo.jpg');
    });

    test('keeps leading zeros in names and text', () {
      const csv = 'Filename,Title\n007.jpg,007\n';

      final rows = CsvMetadataService.parseCsv(csv);

      expect(rows.single['Filename'], '007.jpg');
      expect(rows.single['Title'], '007');
    });

    test('trims only the header names, not the values', () {
      const csv = ' Filename , Title \nphoto.jpg, Заголовок \n';

      final rows = CsvMetadataService.parseCsv(csv);

      expect(rows.single['Title'], ' Заголовок ');
    });

    test('an empty file and a header-only file give an empty data list', () {
      expect(CsvMetadataService.parseCsv(''), isEmpty);
      expect(CsvMetadataService.parseCsv('\r\n\r\n'), isEmpty);
      expect(CsvMetadataService.parseCsv('Filename,Title\r\n'), isEmpty);
    });

    test('fully empty rows are skipped', () {
      const csv = 'Filename,Title\r\n\r\nphoto.jpg,Заголовок\r\n';

      final rows = CsvMetadataService.parseCsv(csv);

      expect(rows, hasLength(1));
      expect(rows.single['Filename'], 'photo.jpg');
    });

    test('keeps unknown columns in the parsed maps', () {
      const csv = 'Filename,Custom\r\nphoto.jpg,значение\r\n';

      final rows = CsvMetadataService.parseCsv(csv);

      expect(rows.single['Custom'], 'значение');
    });

    test('an old CSV without Description and Path is imported', () {
      const csv =
          'Filename,Title,Keywords,IsEditorial,EditorialCity,'
          'EditorialCountry,EditorialDate\r\n'
          'photo.jpg,Заголовок,ключи,false,,,\r\n';

      final rows = CsvMetadataService.parseCsv(csv);
      expect(rows.single.containsKey('Description'), isFalse);
      expect(rows.single.containsKey('Path'), isFalse);

      final plan = CsvMetadataService.buildImportPlan(rows, [
        _file(title: 'Старый', description: 'Старое описание'),
      ]);

      expect(plan.problems, isEmpty);
      final updated = plan.changes.single.file;
      expect(updated.metadataTitle, 'Заголовок');
      expect(updated.metadataKeywords, 'ключи');
      expect(updated.metadataDescription, 'Старое описание');
      expect(updated.editorialCity, isNull);
    });

    test(
      'a wrong number of columns, a missing Filename, empty or repeated headers are errors',
      () {
        expect(
          () => CsvMetadataService.parseCsv('Filename,Title\r\nphoto.jpg\r\n'),
          throwsFormatException,
        );
        expect(
          () => CsvMetadataService.parseCsv(
            'Title,Description\r\nфото,описание\r\n',
          ),
          throwsFormatException,
        );
        expect(
          () => CsvMetadataService.parseCsv('Filename,\r\nphoto.jpg,x\r\n'),
          throwsFormatException,
        );
        expect(
          () =>
              CsvMetadataService.parseCsv('Filename,Title,Title\r\na,b,c\r\n'),
          throwsFormatException,
        );
      },
    );

    test('a broken CSV structure is an error', () {
      expect(
        () => CsvMetadataService.parseCsv(
          'Filename,Title\r\nphoto.jpg,"без кавычки\r\n',
        ),
        throwsFormatException,
      );
    });
  });

  group('import plan', () {
    test(
      'a missing column keeps the field, a present empty column clears it',
      () {
        final source = _file(
          title: 'Старый заголовок',
          description: 'Старое описание',
          keywords: 'старые ключи',
          city: 'Berlin',
          country: 'Germany',
        );

        final rows = CsvMetadataService.parseCsv(
          'Filename,Description\r\nphoto.jpg,\r\n',
        );
        final updated =
            CsvMetadataService.buildImportPlan(rows, [
              source,
            ]).changes.single.file;

        expect(updated.metadataTitle, 'Старый заголовок');
        expect(updated.metadataKeywords, 'старые ключи');
        expect(updated.editorialCity, 'Berlin');
        expect(updated.editorialCountry, 'Germany');
        expect(updated.metadataDescription, '');
      },
    );

    test('a present empty editorial value clears the optional field', () {
      final source = _file(city: 'Berlin', country: 'Germany');

      final rows = CsvMetadataService.parseCsv(
        'Filename,EditorialCity,EditorialCountry\r\nphoto.jpg,,\r\n',
      );
      final updated =
          CsvMetadataService.buildImportPlan(rows, [
            source,
          ]).changes.single.file;

      expect(updated.editorialCity, isNull);
      expect(updated.editorialCountry, isNull);
    });

    test('the first data record is number 2 (the header is number 1)', () {
      final source = _file();

      final rows = CsvMetadataService.parseCsv(
        'Filename,Title\r\nphoto.jpg,Заголовок\r\n',
      );
      final plan = CsvMetadataService.buildImportPlan(rows, [source]);

      expect(plan.totalRecords, 1);
      expect(plan.changes.single.recordNumber, 2);
    });

    test(
      'the same filename in different folders: without Path neither file changes',
      () {
        final files = [
          _file(id: 'a', path: '/one/photo.jpg'),
          _file(id: 'b', path: '/two/photo.jpg'),
        ];

        final rows = CsvMetadataService.parseCsv(
          'Filename,Title\r\nphoto.jpg,Заголовок\r\n',
        );
        final plan = CsvMetadataService.buildImportPlan(rows, files);

        expect(plan.changes, isEmpty);
        expect(plan.problems, hasLength(1));
        expect(plan.problems.single.reason, CsvImportReason.ambiguousName);
      },
    );

    test(
      'the same filename in different folders: with an exact Path only one file changes',
      () {
        final files = [
          _file(id: 'a', path: '/one/photo.jpg'),
          _file(id: 'b', path: '/two/photo.jpg'),
        ];

        final rows = CsvMetadataService.parseCsv(
          'Filename,Title,Path\r\nphoto.jpg,Заголовок,/two/photo.jpg\r\n',
        );
        final plan = CsvMetadataService.buildImportPlan(rows, files);

        expect(plan.problems, isEmpty);
        expect(plan.changes, hasLength(1));
        expect(plan.changes.single.file.id, 'b');
        expect(plan.changes.single.file.metadataTitle, 'Заголовок');
      },
    );

    test('an unknown Path does not fall back to a name match', () {
      final files = [_file(id: 'a', path: '/one/photo.jpg')];

      final rows = CsvMetadataService.parseCsv(
        'Filename,Title,Path\r\nphoto.jpg,Заголовок,/other/photo.jpg\r\n',
      );
      final plan = CsvMetadataService.buildImportPlan(rows, files);

      expect(plan.changes, isEmpty);
      expect(plan.problems, hasLength(1));
      expect(plan.problems.single.reason, CsvImportReason.pathNotFound);
    });

    test('a relative Path is a problem of the row', () {
      final files = [_file(id: 'a', path: '/one/photo.jpg')];

      final rows = CsvMetadataService.parseCsv(
        'Filename,Title,Path\r\nphoto.jpg,Заголовок,one/photo.jpg\r\n',
      );
      final plan = CsvMetadataService.buildImportPlan(rows, files);

      expect(plan.changes, isEmpty);
      expect(plan.problems.single.reason, CsvImportReason.relativePath);
    });

    test('a Path that points to another file name is a problem of the row', () {
      final files = [_file(id: 'a', path: '/one/photo.jpg')];

      final rows = CsvMetadataService.parseCsv(
        'Filename,Title,Path\r\nother.jpg,Заголовок,/one/photo.jpg\r\n',
      );
      final plan = CsvMetadataService.buildImportPlan(rows, files);

      expect(plan.changes, isEmpty);
      expect(plan.problems.single.reason, CsvImportReason.filenameMismatch);
    });

    test('an unknown file name is a problem of the row', () {
      final files = [_file(id: 'a', path: '/one/photo.jpg')];

      final rows = CsvMetadataService.parseCsv(
        'Filename,Title\r\nmissing.jpg,Заголовок\r\n',
      );
      final plan = CsvMetadataService.buildImportPlan(rows, files);

      expect(plan.changes, isEmpty);
      expect(plan.problems.single.reason, CsvImportReason.fileNotFound);
    });

    test('several rows for one material are not applied at all', () {
      final files = [_file(id: 'a', path: '/one/photo.jpg')];

      final rows = CsvMetadataService.parseCsv(
        'Filename,Title,Path\r\n'
        'photo.jpg,Первый,/one/photo.jpg\r\n'
        'photo.jpg,Второй,/one/photo.jpg\r\n',
      );
      final plan = CsvMetadataService.buildImportPlan(rows, files);

      expect(plan.changes, isEmpty);
      expect(plan.problems, hasLength(2));
      expect(
        plan.problems.every((p) => p.reason == CsvImportReason.duplicateTarget),
        isTrue,
      );
      expect(plan.problems.map((p) => p.recordNumber), [2, 3]);
    });

    test('an invalid IsEditorial value makes the row a problem', () {
      final files = [_file(id: 'a', path: '/one/photo.jpg')];

      final rows = CsvMetadataService.parseCsv(
        'Filename,IsEditorial\r\nphoto.jpg,да\r\n',
      );
      final plan = CsvMetadataService.buildImportPlan(rows, files);

      expect(plan.changes, isEmpty);
      expect(plan.problems.single.reason, CsvImportReason.invalidBoolean);
    });

    test('an empty IsEditorial value makes the row a problem', () {
      final files = [_file(id: 'a', path: '/one/photo.jpg')];

      final rows = CsvMetadataService.parseCsv(
        'Filename,IsEditorial\r\nphoto.jpg,\r\n',
      );
      final plan = CsvMetadataService.buildImportPlan(rows, files);

      expect(plan.changes, isEmpty);
      expect(plan.problems.single.reason, CsvImportReason.invalidBoolean);
    });

    test('IsEditorial accepts true/false in any case with outer spaces', () {
      final files = [_file(id: 'a', path: '/one/photo.jpg')];

      final rows = CsvMetadataService.parseCsv(
        'Filename,IsEditorial\r\nphoto.jpg, TRUE \r\n',
      );
      final plan = CsvMetadataService.buildImportPlan(rows, files);

      expect(plan.problems, isEmpty);
      expect(plan.changes.single.file.isEditorial, isTrue);
    });

    test('an unparsable EditorialDate makes the row a problem', () {
      final files = [_file(id: 'a', path: '/one/photo.jpg')];

      final rows = CsvMetadataService.parseCsv(
        'Filename,EditorialDate\r\nphoto.jpg,вчера\r\n',
      );
      final plan = CsvMetadataService.buildImportPlan(rows, files);

      expect(plan.changes, isEmpty);
      expect(plan.problems.single.reason, CsvImportReason.invalidDate);
    });

    test('an empty EditorialDate clears the date', () {
      final files = [
        _file(
          id: 'a',
          path: '/one/photo.jpg',
          editorialDate: DateTime(2024, 5, 17).millisecondsSinceEpoch,
        ),
      ];

      final rows = CsvMetadataService.parseCsv(
        'Filename,EditorialDate\r\nphoto.jpg,\r\n',
      );
      final updated =
          CsvMetadataService.buildImportPlan(rows, files).changes.single.file;

      expect(updated.editorialDate, isNull);
    });

    test('IsEditorial updates the flag and the editorial tag consistently', () {
      final files = [
        _file(
          id: 'a',
          path: '/one/photo.jpg',
          tags: const [AppTags.aiGenerated, 'пользовательский'],
        ),
      ];

      final rows = CsvMetadataService.parseCsv(
        'Filename,IsEditorial\r\nphoto.jpg,true\r\n',
      );
      final updated =
          CsvMetadataService.buildImportPlan(rows, files).changes.single.file;

      expect(updated.isEditorial, isTrue);
      expect(updated.hasEditorialTag, isTrue);
      expect(updated.isAiGenerated, isTrue);
      expect(updated.tags, contains('пользовательский'));
    });

    test(
      'IsEditorial=false removes the editorial tag and keeps the other tags',
      () {
        final files = [
          _file(
            id: 'a',
            path: '/one/photo.jpg',
            isEditorial: true,
            tags: const [AppTags.editorial, AppTags.aiGenerated],
          ),
        ];

        final rows = CsvMetadataService.parseCsv(
          'Filename,IsEditorial\r\nphoto.jpg,false\r\n',
        );
        final updated =
            CsvMetadataService.buildImportPlan(rows, files).changes.single.file;

        expect(updated.isEditorial, isFalse);
        expect(updated.hasEditorialTag, isFalse);
        expect(updated.isAiGenerated, isTrue);
      },
    );

    test(
      'without IsEditorial the flag and the editorial tag stay as they were',
      () {
        final files = [
          _file(
            id: 'a',
            path: '/one/photo.jpg',
            isEditorial: true,
            tags: const [AppTags.editorial],
          ),
        ];

        final rows = CsvMetadataService.parseCsv(
          'Filename,Title\r\nphoto.jpg,Заголовок\r\n',
        );
        final updated =
            CsvMetadataService.buildImportPlan(rows, files).changes.single.file;

        expect(updated.isEditorial, isTrue);
        expect(updated.hasEditorialTag, isTrue);
      },
    );

    test(
      'two rows targeting same id where one has invalid boolean: both excluded, 0 changes, 2 duplicateTarget',
      () {
        final files = [_file(id: 'a', filename: 'photo.jpg')];
        final rows = CsvMetadataService.parseCsv(
          'Filename,Title,IsEditorial\r\n'
          'photo.jpg,first,true\r\n'
          'photo.jpg,second,invalid\r\n',
        );
        final plan = CsvMetadataService.buildImportPlan(rows, files);

        expect(plan.changes, isEmpty);
        expect(plan.problems, hasLength(2));
        expect(plan.problems[0].reason, CsvImportReason.duplicateTarget);
        expect(plan.problems[0].recordNumber, 2);
        expect(plan.problems[1].reason, CsvImportReason.duplicateTarget);
        expect(plan.problems[1].recordNumber, 3);
      },
    );

    test(
      'two rows targeting same id where one has invalid date: both excluded, order does not matter',
      () {
        final files = [_file(id: 'a', filename: 'photo.jpg')];
        final rows1 = CsvMetadataService.parseCsv(
          'Filename,Title,EditorialDate\r\n'
          'photo.jpg,first,2024-05-17\r\n'
          'photo.jpg,second,2026-02-31\r\n',
        );
        final plan1 = CsvMetadataService.buildImportPlan(rows1, files);

        expect(plan1.changes, isEmpty);
        expect(plan1.problems, hasLength(2));
        expect(plan1.problems[0].reason, CsvImportReason.duplicateTarget);
        expect(plan1.problems[1].reason, CsvImportReason.duplicateTarget);

        // Перестановка строк не меняет результат
        final rows2 = CsvMetadataService.parseCsv(
          'Filename,Title,EditorialDate\r\n'
          'photo.jpg,second,2026-02-31\r\n'
          'photo.jpg,first,2024-05-17\r\n',
        );
        final plan2 = CsvMetadataService.buildImportPlan(rows2, files);

        expect(plan2.changes, isEmpty);
        expect(plan2.problems, hasLength(2));
        expect(plan2.problems[0].reason, CsvImportReason.duplicateTarget);
        expect(plan2.problems[1].reason, CsvImportReason.duplicateTarget);
      },
    );

    test(
      'matching by filename and by Path targeting same id: both excluded as duplicateTarget',
      () {
        final files = [
          _file(id: 'a', filename: 'photo.jpg', path: '/dir/photo.jpg'),
        ];
        final rows = CsvMetadataService.parseCsv(
          'Filename,Title,Path\r\n'
          'photo.jpg,Первый,\r\n'
          'photo.jpg,Второй,/dir/photo.jpg\r\n',
        );
        final plan = CsvMetadataService.buildImportPlan(rows, files);

        expect(plan.changes, isEmpty);
        expect(plan.problems, hasLength(2));
        expect(plan.problems[0].reason, CsvImportReason.duplicateTarget);
        expect(plan.problems[1].reason, CsvImportReason.duplicateTarget);
      },
    );

    test('same filename with different exact Path/id do not conflict', () {
      final files = [
        _file(id: 'a', filename: 'photo.jpg', path: '/dir1/photo.jpg'),
        _file(id: 'b', filename: 'photo.jpg', path: '/dir2/photo.jpg'),
      ];
      final rows = CsvMetadataService.parseCsv(
        'Filename,Title,Path\r\n'
        'photo.jpg,Первый,/dir1/photo.jpg\r\n'
        'photo.jpg,Второй,/dir2/photo.jpg\r\n',
      );
      final plan = CsvMetadataService.buildImportPlan(rows, files);

      expect(plan.problems, isEmpty);
      expect(plan.changes, hasLength(2));
      expect(plan.changes[0].file.id, 'a');
      expect(plan.changes[0].file.metadataTitle, 'Первый');
      expect(plan.changes[1].file.id, 'b');
      expect(plan.changes[1].file.metadataTitle, 'Второй');
    });

    test(
      'strict date validation: 2026-02-31, 2026-02-29, month 13, day 00, hour 25, minute/second 61, invalid offset give invalidDate',
      () {
        final files = [_file(id: 'a', filename: 'photo.jpg')];
        final invalidDates = [
          '2026-02-31',
          '2026-02-29',
          '2024-13-01',
          '2024-05-00',
          '2024-05-17T25:00:00',
          '2024-05-17T10:61:00',
          '2024-05-17T10:00:61',
          '2024-05-17T10:00:00+99:99',
          '2024-05-17T10:00:00+02:60',
          '2024-05-17T10:00:00+02',
          '2024-05-17T10:00:00+25:00',
        ];

        for (final badDate in invalidDates) {
          final rows = CsvMetadataService.parseCsv(
            'Filename,EditorialDate\r\nphoto.jpg,$badDate\r\n',
          );
          final plan = CsvMetadataService.buildImportPlan(rows, files);

          expect(
            plan.changes,
            isEmpty,
            reason: 'Date $badDate must not produce changes',
          );
          expect(
            plan.problems,
            hasLength(1),
            reason: 'Date $badDate must produce 1 problem',
          );
          expect(
            plan.problems.single.reason,
            CsvImportReason.invalidDate,
            reason: 'Date $badDate must have invalidDate reason',
          );
        }
      },
    );

    test(
      'strict date validation: 2024-02-29, calendar date, exported local datetime, UTC, fractional seconds, and valid offset are accepted and verify time value',
      () {
        final files = [_file(id: 'a', filename: 'photo.jpg')];

        // 1. 2024-02-29 (високосный год)
        var rows = CsvMetadataService.parseCsv(
          'Filename,EditorialDate\r\nphoto.jpg,2024-02-29\r\n',
        );
        var plan = CsvMetadataService.buildImportPlan(rows, files);
        expect(plan.problems, isEmpty);
        expect(
          plan.changes.single.file.editorialDate,
          DateTime(2024, 2, 29).millisecondsSinceEpoch,
        );

        // 2. Обычная календарная дата
        rows = CsvMetadataService.parseCsv(
          'Filename,EditorialDate\r\nphoto.jpg,2024-05-17\r\n',
        );
        plan = CsvMetadataService.buildImportPlan(rows, files);
        expect(plan.problems, isEmpty);
        expect(
          plan.changes.single.file.editorialDate,
          DateTime(2024, 5, 17).millisecondsSinceEpoch,
        );

        // 3. Экспортируемая локальная дата со временем
        final localDt = DateTime(2024, 5, 17, 10, 30, 45, 123);
        final exportedStr = localDt.toIso8601String();
        rows = CsvMetadataService.parseCsv(
          'Filename,EditorialDate\r\nphoto.jpg,$exportedStr\r\n',
        );
        plan = CsvMetadataService.buildImportPlan(rows, files);
        expect(plan.problems, isEmpty);
        expect(
          plan.changes.single.file.editorialDate,
          localDt.millisecondsSinceEpoch,
        );

        // 4. UTC дата (Z)
        rows = CsvMetadataService.parseCsv(
          'Filename,EditorialDate\r\nphoto.jpg,2024-05-17T12:00:00Z\r\n',
        );
        plan = CsvMetadataService.buildImportPlan(rows, files);
        expect(plan.problems, isEmpty);
        expect(
          plan.changes.single.file.editorialDate,
          DateTime.utc(2024, 5, 17, 12, 0, 0).millisecondsSinceEpoch,
        );

        // 5. Дробные секунды (1-6 цифр)
        rows = CsvMetadataService.parseCsv(
          'Filename,EditorialDate\r\nphoto.jpg,2024-05-17T12:00:00.5Z\r\n',
        );
        plan = CsvMetadataService.buildImportPlan(rows, files);
        expect(plan.problems, isEmpty);
        expect(
          plan.changes.single.file.editorialDate,
          DateTime.utc(2024, 5, 17, 12, 0, 0, 500).millisecondsSinceEpoch,
        );

        // 6. Допустимое смещение (+02:00) и проверка значения времени (14:30+02:00 == 12:30 UTC)
        rows = CsvMetadataService.parseCsv(
          'Filename,EditorialDate\r\nphoto.jpg,2024-05-17T14:30:00+02:00\r\n',
        );
        plan = CsvMetadataService.buildImportPlan(rows, files);
        expect(plan.problems, isEmpty);
        final epochMs = plan.changes.single.file.editorialDate!;
        final utcParsed = DateTime.fromMillisecondsSinceEpoch(
          epochMs,
          isUtc: true,
        );
        expect(utcParsed.year, 2024);
        expect(utcParsed.month, 5);
        expect(utcParsed.day, 17);
        expect(utcParsed.hour, 12);
        expect(utcParsed.minute, 30);
        expect(utcParsed.second, 0);

        // Смещение ±HHmm без двоеточия
        rows = CsvMetadataService.parseCsv(
          'Filename,EditorialDate\r\nphoto.jpg,2024-05-17T14:30:00+0200\r\n',
        );
        plan = CsvMetadataService.buildImportPlan(rows, files);
        expect(plan.problems, isEmpty);
        expect(plan.changes.single.file.editorialDate, epochMs);
      },
    );

    test(
      'date handling: empty date clears, missing date preserves existing value',
      () {
        final existingDate =
            DateTime(2024, 5, 17, 10, 0).millisecondsSinceEpoch;
        final fileWithDate = _file(
          id: 'a',
          filename: 'photo.jpg',
          editorialDate: existingDate,
        );

        // Пустая дата очищает значение
        var rows = CsvMetadataService.parseCsv(
          'Filename,EditorialDate\r\nphoto.jpg,\r\n',
        );
        var plan = CsvMetadataService.buildImportPlan(rows, [fileWithDate]);
        expect(plan.problems, isEmpty);
        expect(plan.changes.single.file.editorialDate, isNull);

        // Дата из внешних пробелов очищает значение
        rows = CsvMetadataService.parseCsv(
          'Filename,EditorialDate\r\nphoto.jpg,   \r\n',
        );
        plan = CsvMetadataService.buildImportPlan(rows, [fileWithDate]);
        expect(plan.problems, isEmpty);
        expect(plan.changes.single.file.editorialDate, isNull);

        // Отсутствующая колонка EditorialDate сохраняет имеющуюся дату
        rows = CsvMetadataService.parseCsv(
          'Filename,Title\r\nphoto.jpg,Новый заголовок\r\n',
        );
        plan = CsvMetadataService.buildImportPlan(rows, [fileWithDate]);
        expect(plan.problems, isEmpty);
        expect(plan.changes.single.file.editorialDate, existingDate);
      },
    );

    test(
      'Path matching: missing or empty path falls back to unique filename match; path of spaces is relativePath error and 0 changes',
      () {
        final files = [
          _file(id: 'a', filename: 'photo.jpg', path: '/dir/photo.jpg'),
        ];

        // Path отсутствует — сопоставление по имени работает
        var rows = CsvMetadataService.parseCsv(
          'Filename,Title\r\nphoto.jpg,Заголовок\r\n',
        );
        var plan = CsvMetadataService.buildImportPlan(rows, files);
        expect(plan.problems, isEmpty);
        expect(plan.changes, hasLength(1));
        expect(plan.changes.single.file.id, 'a');

        // Path равен пустой строке — сопоставление по имени работает
        rows = CsvMetadataService.parseCsv(
          'Filename,Title,Path\r\nphoto.jpg,Заголовок,\r\n',
        );
        plan = CsvMetadataService.buildImportPlan(rows, files);
        expect(plan.problems, isEmpty);
        expect(plan.changes, hasLength(1));
        expect(plan.changes.single.file.id, 'a');

        // Path из пробелов — ошибка, не допускает fallback по имени, 0 изменений
        rows = CsvMetadataService.parseCsv(
          'Filename,Title,Path\r\nphoto.jpg,Заголовок,   \r\n',
        );
        plan = CsvMetadataService.buildImportPlan(rows, files);
        expect(plan.changes, isEmpty);
        expect(plan.problems, hasLength(1));
        expect(plan.problems.single.reason, CsvImportReason.relativePath);
      },
    );

    test(
      'text preservation: non-empty whitespace-only and multiline text are preserved; truly empty field clears',
      () {
        final file = _file(
          id: 'a',
          filename: 'photo.jpg',
          title: 'Старый заголовок',
          description: 'Старое описание',
          city: 'Berlin',
        );

        // Непустые строки из пробелов сохраняются буквально
        var rows = CsvMetadataService.parseCsv(
          'Filename,Title,Description,EditorialCity\r\nphoto.jpg,"   ","   ","   "\r\n',
        );
        var plan = CsvMetadataService.buildImportPlan(rows, [file]);
        expect(plan.problems, isEmpty);
        expect(plan.changes.single.file.metadataTitle, '   ');
        expect(plan.changes.single.file.metadataDescription, '   ');
        expect(plan.changes.single.file.editorialCity, '   ');

        // Многострочные значения сохраняются буквально
        rows = CsvMetadataService.parseCsv(
          'Filename,Title,Description\r\nphoto.jpg,"Заголовок с \n переходом","Строка 1\nСтрока 2"\r\n',
        );
        plan = CsvMetadataService.buildImportPlan(rows, [file]);
        expect(plan.problems, isEmpty);
        expect(
          plan.changes.single.file.metadataTitle,
          'Заголовок с \n переходом',
        );
        expect(
          plan.changes.single.file.metadataDescription,
          'Строка 1\nСтрока 2',
        );

        // Действительно пустая ячейка очищает
        rows = CsvMetadataService.parseCsv(
          'Filename,Title,Description,EditorialCity\r\nphoto.jpg,,,\r\n',
        );
        plan = CsvMetadataService.buildImportPlan(rows, [file]);
        expect(plan.problems, isEmpty);
        expect(plan.changes.single.file.metadataTitle, '');
        expect(plan.changes.single.file.metadataDescription, '');
        expect(plan.changes.single.file.editorialCity, isNull);
      },
    );
  });

  group('files', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('stockflow_csv_service');
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('exportToFile and importFromFile keep the round trip', () async {
      final source = _file(
        title: 'Заголовок',
        description: 'Описание',
        keywords: 'ключ',
        isEditorial: true,
        city: 'Berlin',
        country: 'Germany',
        editorialDate: DateTime(2024, 5, 17).millisecondsSinceEpoch,
      );
      final csvFile = File('${dir.path}/metadata.csv');

      await CsvMetadataService.exportToFile([source], csvFile.path);
      final rows = await CsvMetadataService.importFromFile(csvFile.path);

      final plan = CsvMetadataService.buildImportPlan(rows, [source]);
      expect(plan.problems, isEmpty);
      final updated = plan.changes.single.file;
      expect(updated.metadataTitle, 'Заголовок');
      expect(updated.metadataDescription, 'Описание');
      expect(updated.metadataKeywords, 'ключ');
      expect(updated.isEditorial, isTrue);
      expect(updated.editorialCity, 'Berlin');
      expect(updated.editorialDate, source.editorialDate);
    });

    test('importFromFile reports a missing file', () async {
      await expectLater(
        CsvMetadataService.importFromFile('${dir.path}/missing.csv'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
