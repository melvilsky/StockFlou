import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_flow/core/state/active_grid_selection_provider.dart';
import 'package:stock_flow/core/state/editorial_state_provider.dart';
import 'package:stock_flow/core/state/files_provider.dart';
import 'package:stock_flow/core/state/settings_provider.dart';
import 'package:stock_flow/core/state/workspaces_provider.dart';
import 'package:stock_flow/features/generation/presentation/generation_screen.dart';
import 'package:stock_flow/features/generation/presentation/widgets/generation_widgets.dart';
import 'package:stock_flow/models/app_file.dart';
import 'package:stock_flow/models/generation_options.dart';

class FakeFilesNotifier extends FilesNotifier {
  final List<AppFile> files;
  final List<AppFile> addedFiles = [];

  FakeFilesNotifier(List<AppFile> initial) : files = List.of(initial);

  @override
  Future<List<AppFile>> build() async => List.of(files);

  void hideFromCatalog() {
    files.clear();
    state = const AsyncData([]);
  }

  @override
  Future<void> syncWithDisk() async {}

  @override
  Future<void> addFile(AppFile file) async {
    addedFiles.add(file);
    final idx = files.indexWhere((f) => f.id == file.id || f.path == file.path);
    if (idx >= 0) {
      files[idx] = file;
    } else {
      files.add(file);
    }
    state = AsyncData(List.of(files));
  }
}

class FakeSettingsNotifier extends SettingsNotifier {
  final SettingsState _state;
  FakeSettingsNotifier(this._state);

  @override
  Future<SettingsState> build() async => _state;
}

class FakeWorkspacesNotifier extends WorkspacesNotifier {
  final String _currentPath;
  FakeWorkspacesNotifier(this._currentPath);

  @override
  WorkspacesState build() {
    return WorkspacesState(
      entries: [WorkspaceEntry(path: _currentPath)],
      currentIndex: 0,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<String> writtenFiles;

  setUp(() {
    SharedPreferences.setMockInitialValues({'api_key': 'mock-key'});
    final rawTemp = Directory.systemTemp.createTempSync('sf_gen_ctx_test_');
    tempDir = Directory(rawTemp.resolveSymbolicLinksSync());
    writtenFiles = [];
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  File createTestFile(String name) {
    final file = File('${tempDir.path}/$name');
    file.writeAsStringSync('fake content');
    return file;
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<AppFile> initialFiles,
    List<File>? initialLocalFiles,
    required Future<Map<String, dynamic>> Function({
      required String apiKey,
      required String filePath,
      required GenerationOptions options,
    })
    generateMetadata,
    Future<({double? lat, double? lon, DateTime? date, bool hasAudio})>
    Function(String filePath)?
    readExif,
    Future<({String? city, String? country, String? state})> Function(
      double? lat,
      double? lon,
    )?
    resolveGeo,
    Future<bool> Function({
      required String filePath,
      required String title,
      required String keywords,
      String? description,
    })?
    writeMetadata,
    Future<({bool replace, bool applyToAll})?> Function(String filename)?
    showRegenerateDialog,
    void Function(ProviderContainer container)? onContainer,
  }) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final fakeFiles = FakeFilesNotifier(initialFiles);
    final container = ProviderContainer(
      overrides: [
        workspacesProvider.overrideWith(
          () => FakeWorkspacesNotifier(tempDir.path),
        ),
        filesProvider.overrideWith(() => fakeFiles),
        settingsProvider.overrideWith(
          () => FakeSettingsNotifier(
            SettingsState(apiKey: 'test-key', defaultKeywordsCount: 15),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    onContainer?.call(container);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: GenerationScreen(
              initialLocalFiles: initialLocalFiles,
              generateMetadata: generateMetadata,
              readExif:
                  readExif ??
                  (_) async => (
                    lat: null,
                    lon: null,
                    date: null,
                    hasAudio: false,
                  ),
              resolveGeo: resolveGeo,
              writeMetadata:
                  writeMetadata ??
                  ({
                    required filePath,
                    required title,
                    required keywords,
                    description,
                  }) async {
                    writtenFiles.add(filePath);
                    return true;
                  },
              showRegenerateDialog: showRegenerateDialog,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    '1. A starts as Editorial with CityA; B is selected; A preserves CityA and B inspector stays unchanged',
    (tester) async {
      final fileA = createTestFile('a.jpg');
      final fileB = createTestFile('b.jpg');

      final appFileA = AppFile(
        id: 'id-a',
        path: fileA.path,
        filename: 'a.jpg',
        createdAt: 1700000000,
        isEditorial: true,
        editorialCity: 'CityA',
        editorialCountry: 'CountryA',
        tags: const [AppTags.editorial],
      );
      final appFileB = AppFile(
        id: 'id-b',
        path: fileB.path,
        filename: 'b.jpg',
        createdAt: 1700000000,
        isEditorial: false,
        editorialCity: 'CityB',
        editorialCountry: 'CountryB',
        tags: const [],
      );

      final apiCompleterA = Completer<Map<String, dynamic>>();
      ProviderContainer? testContainer;

      await pumpScreen(
        tester,
        initialFiles: [appFileA, appFileB],
        onContainer: (c) => testContainer = c,
        generateMetadata: ({
          required apiKey,
          required filePath,
          required options,
        }) async {
          if (filePath == fileA.path) {
            return apiCompleterA.future;
          }
          return {
            'title': 'Other',
            'keywords': ['k'],
            'description': '',
          };
        },
      );

      // Select A
      await tester.tap(find.text('a.jpg'));
      await tester.pump();

      expect(testContainer!.read(editorialStateProvider).isEditorial, isTrue);
      expect(testContainer!.read(editorialStateProvider).city, 'CityA');

      // Start generation for A
      await tester.tap(find.text('AI метаданные'));
      await tester.pump();

      // While request A is in flight, select B
      await tester.tap(find.text('b.jpg'));
      await tester.pump();

      // Inspector now reflects B
      expect(testContainer!.read(editorialStateProvider).isEditorial, isFalse);
      expect(testContainer!.read(editorialStateProvider).city, 'CityB');

      // Complete API response for A
      apiCompleterA.complete({
        'title': 'Title A',
        'keywords': ['tag1', 'tag2'],
        'description': 'Desc A',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // File A in DB was saved with its original context (CityA)
      final savedFiles = testContainer!.read(filesProvider).value!;
      final savedA = savedFiles.firstWhere((f) => f.id == 'id-a');
      expect(savedA.metadataTitle, 'Title A - CityA, CountryA.');
      expect(savedA.isEditorial, isTrue);
      expect(savedA.editorialCity, 'CityA');
      expect(savedA.tags, contains(AppTags.editorial));

      // Inspector still shows B!
      expect(testContainer!.read(editorialStateProvider).isEditorial, isFalse);
      expect(testContainer!.read(editorialStateProvider).city, 'CityB');
    },
  );

  testWidgets(
    '2. Slow EXIF/geocoding for A finishes after selecting B and does not touch provider B',
    (tester) async {
      final fileA = createTestFile('a.jpg');
      final fileB = createTestFile('b.jpg');

      final appFileA = AppFile(
        id: 'id-a',
        path: fileA.path,
        filename: 'a.jpg',
        createdAt: 1700000000,
        isEditorial: true,
        editorialCity: '',
        editorialCountry: '',
        tags: const [AppTags.editorial],
      );
      final appFileB = AppFile(
        id: 'id-b',
        path: fileB.path,
        filename: 'b.jpg',
        createdAt: 1700000000,
        isEditorial: true,
        editorialCity: 'CityB',
        editorialCountry: 'CountryB',
        tags: const [AppTags.editorial],
      );

      final exifCompleterA =
          Completer<
            ({double? lat, double? lon, DateTime? date, bool hasAudio})
          >();
      final apiCompleterA = Completer<Map<String, dynamic>>();
      ProviderContainer? testContainer;

      await pumpScreen(
        tester,
        initialFiles: [appFileA, appFileB],
        onContainer: (c) => testContainer = c,
        readExif: (path) async {
          if (path == fileA.path) {
            return exifCompleterA.future;
          }
          return (lat: null, lon: null, date: null, hasAudio: false);
        },
        resolveGeo: (lat, lon) async {
          return (
            city: 'ResolvedCityA',
            country: 'ResolvedCountryA',
            state: null,
          );
        },
        generateMetadata: ({
          required apiKey,
          required filePath,
          required options,
        }) async {
          if (filePath == fileA.path) {
            return apiCompleterA.future;
          }
          return {'title': 'B', 'keywords': <String>[], 'description': ''};
        },
      );

      // Select A
      await tester.tap(find.text('a.jpg'));
      await tester.pump();

      // Start generation for A
      await tester.tap(find.text('AI метаданные'));
      await tester.pump();

      // While EXIF for A is pending, user selects B
      await tester.tap(find.text('b.jpg'));
      await tester.pump();

      expect(testContainer!.read(editorialStateProvider).city, 'CityB');

      // Now EXIF for A resolves
      exifCompleterA.complete((
        lat: 10.0,
        lon: 20.0,
        date: DateTime(2026, 3, 1),
        hasAudio: false,
      ));
      await tester.pump();

      // Provider B must STILL be CityB! (NOT overwritten by ResolvedCityA)
      expect(testContainer!.read(editorialStateProvider).city, 'CityB');

      // Now API for A finishes
      apiCompleterA.complete({
        'title': 'Photo A',
        'keywords': ['nature'],
        'description': '',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Provider B is still intact
      expect(testContainer!.read(editorialStateProvider).city, 'CityB');

      // But File A was saved with its resolved location
      final savedA = testContainer!
          .read(filesProvider)
          .value!
          .firstWhere((f) => f.id == 'id-a');
      expect(savedA.editorialCity, 'ResolvedCityA');
      expect(
        savedA.metadataTitle,
        'Photo A - ResolvedCityA, ResolvedCountryA. March 1 2026.',
      );
    },
  );

  testWidgets(
    '3. A starts without Editorial, then Editorial B is selected: A gets no editorial tag or fields',
    (tester) async {
      final fileA = createTestFile('a.jpg');
      final fileB = createTestFile('b.jpg');

      final appFileA = AppFile(
        id: 'id-a',
        path: fileA.path,
        filename: 'a.jpg',
        createdAt: 1700000000,
        isEditorial: false,
        tags: const [],
      );
      final appFileB = AppFile(
        id: 'id-b',
        path: fileB.path,
        filename: 'b.jpg',
        createdAt: 1700000000,
        isEditorial: true,
        editorialCity: 'CityB',
        editorialCountry: 'CountryB',
        tags: const [AppTags.editorial],
      );

      final apiCompleterA = Completer<Map<String, dynamic>>();
      ProviderContainer? testContainer;

      await pumpScreen(
        tester,
        initialFiles: [appFileA, appFileB],
        onContainer: (c) => testContainer = c,
        generateMetadata: ({
          required apiKey,
          required filePath,
          required options,
        }) async {
          if (filePath == fileA.path) {
            return apiCompleterA.future;
          }
          return {'title': 'B', 'keywords': <String>[], 'description': ''};
        },
      );

      // Select A
      await tester.tap(find.text('a.jpg'));
      await tester.pump();

      // Start generation for A
      await tester.tap(find.text('AI метаданные'));
      await tester.pump();

      // User selects Editorial B
      await tester.tap(find.text('b.jpg'));
      await tester.pump();

      expect(testContainer!.read(editorialStateProvider).isEditorial, isTrue);

      // Complete A
      apiCompleterA.complete({
        'title': 'Commercial Skyline',
        'keywords': ['city', 'skyline'],
        'description': '',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final savedA = testContainer!
          .read(filesProvider)
          .value!
          .firstWhere((f) => f.id == 'id-a');
      expect(savedA.isEditorial, isFalse);
      expect(
        savedA.editorialCity == null || savedA.editorialCity!.isEmpty,
        isTrue,
      );
      expect(savedA.metadataTitle, 'Commercial Skyline');
      expect(savedA.tags, isNot(contains(AppTags.editorial)));
    },
  );

  testWidgets(
    '4. Batch with > 3 files: late workers use frozen launch context and own EXIF',
    (tester) async {
      final files = List.generate(5, (i) => createTestFile('item$i.jpg'));
      final appFiles = List<AppFile>.generate(
        5,
        (i) => AppFile(
          id: 'id-$i',
          path: files[i].path,
          filename: 'item$i.jpg',
          createdAt: 1700000000,
          isEditorial: true,
          tags: const [AppTags.editorial],
        ),
      );

      final activeCalls = <String>{};
      int maxConcurrent = 0;
      final completers = {
        for (final f in files) f.path: Completer<Map<String, dynamic>>(),
      };
      final capturedContexts = <String, String?>{};

      ProviderContainer? testContainer;

      await pumpScreen(
        tester,
        initialFiles: appFiles,
        onContainer: (c) => testContainer = c,
        readExif: (path) async {
          final idx = path[path.indexOf('item') + 4];
          return (
            lat: 10.0,
            lon: 20.0,
            date: DateTime(2026, 1, int.parse(idx) + 1),
            hasAudio: false,
          );
        },
        resolveGeo: (lat, lon) async {
          return (city: 'GeoCity', country: 'GeoCountry', state: null);
        },
        generateMetadata: ({
          required apiKey,
          required filePath,
          required options,
        }) async {
          capturedContexts[filePath] = options.contextAndInstructions;
          activeCalls.add(filePath);
          if (activeCalls.length > maxConcurrent) {
            maxConcurrent = activeCalls.length;
          }
          final result = await completers[filePath]!.future;
          activeCalls.remove(filePath);
          return result;
        },
      );

      // Select all files (click select-all icon in toolbar)
      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pump();

      // Set editorial mode true at launch
      testContainer!.read(editorialStateProvider.notifier).setEditorial(true);

      // Set user context
      final contextField = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLines == 3,
      );
      if (contextField.evaluate().isNotEmpty) {
        await tester.enterText(contextField, 'Launch context for batch');
        await tester.pump();
      }

      // Start batch generation via toolbar AI Tag icon
      await tester.tap(
        find.byTooltip('AI метаданные'),
      );
      await tester.pump();

      // At most 3 concurrent tasks should be running in pool
      expect(maxConcurrent, inInclusiveRange(1, 3));
      expect(activeCalls.length, 3);

      // Mutate editorial state and inspector while batch is in progress
      testContainer!.read(editorialStateProvider.notifier).setEditorial(false);
      if (contextField.evaluate().isNotEmpty) {
        await tester.enterText(contextField, 'Mutated context text');
        await tester.pump();
      }

      // Complete the first 3 workers one by one
      for (int i = 0; i < 3; i++) {
        completers[files[i].path]!.complete({
          'title': 'Title $i',
          'keywords': ['tag$i'],
          'description': '',
        });
        await tester.pump();
      }

      // Now remaining workers (3 and 4) have entered the pool
      expect(completers[files[3].path]!.isCompleted, isFalse);
      expect(completers[files[4].path]!.isCompleted, isFalse);

      completers[files[3].path]!.complete({
        'title': 'Title 3',
        'keywords': ['tag3'],
        'description': '',
      });
      await tester.pump();

      completers[files[4].path]!.complete({
        'title': 'Title 4',
        'keywords': ['tag4'],
        'description': '',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Concurrency was strictly capped at 3
      expect(maxConcurrent, 3);

      // All workers used the frozen launch context, not the mutated one
      for (final f in files) {
        if (capturedContexts[f.path] != null) {
          expect(capturedContexts[f.path], 'Launch context for batch');
        }
      }

      // Late workers still got isEditorial=true from snapshot
      final savedFiles = testContainer!.read(filesProvider).value!;
      for (int i = 0; i < 5; i++) {
        final saved = savedFiles.firstWhere((f) => f.id == 'id-$i');
        expect(saved.isEditorial, isTrue);
        expect(saved.editorialCity, 'GeoCity');
        expect(
          saved.metadataTitle,
          contains('Title $i - GeoCity, GeoCountry.'),
        );
      }
    },
  );

  testWidgets(
    '5. Manual AI-tag change on A during API request is preserved upon completion',
    (tester) async {
      final fileA = createTestFile('a.jpg');
      final appFileA = AppFile(
        id: 'id-a',
        path: fileA.path,
        filename: 'a.jpg',
        createdAt: 1700000000,
        isEditorial: false,
        tags: const ['custom_tag'],
      );

      final apiCompleterA = Completer<Map<String, dynamic>>();
      ProviderContainer? testContainer;

      await pumpScreen(
        tester,
        initialFiles: [appFileA],
        onContainer: (c) => testContainer = c,
        generateMetadata:
            ({required apiKey, required filePath, required options}) async =>
                apiCompleterA.future,
      );

      // Select A
      await tester.tap(find.text('a.jpg'));
      await tester.pump();

      // Start generation
      await tester.tap(find.text('AI метаданные'));
      await tester.pump();

      // User manually marks A as AI-generated while request is in flight
      final updatedA = appFileA.copyWith(
        tags: ['custom_tag', AppTags.aiGenerated],
      );
      await testContainer!.read(filesProvider.notifier).addFile(updatedA);
      await tester.pump();

      // Complete API response
      apiCompleterA.complete({
        'title': 'Generated Cat',
        'keywords': ['cat', 'fur'],
        'description': '',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Both custom_tag and ai_generated are preserved!
      final savedA = testContainer!
          .read(filesProvider)
          .value!
          .firstWhere((f) => f.id == 'id-a');
      expect(savedA.tags, contains('custom_tag'));
      expect(savedA.tags, contains(AppTags.aiGenerated));
    },
  );

  testWidgets(
    '6. Local target imported into catalog during request reuses existing id without duplicate',
    (tester) async {
      final fileA = createTestFile('local_a.jpg');

      final apiCompleterA = Completer<Map<String, dynamic>>();
      ProviderContainer? testContainer;

      await pumpScreen(
        tester,
        initialFiles: [], // Initially not in DB
        initialLocalFiles: [fileA],
        onContainer: (c) => testContainer = c,
        generateMetadata:
            ({required apiKey, required filePath, required options}) async =>
                apiCompleterA.future,
      );

      // Tap the local file
      await tester.tap(find.text('local_a.jpg'));
      await tester.pump();

      // Start generation
      await tester.tap(find.text('AI метаданные'));
      await tester.pump();

      // While request is in flight, catalog indexes this file with a specific id
      final importedFile = AppFile(
        id: 'imported-fixed-uuid',
        path: fileA.path,
        filename: 'local_a.jpg',
        createdAt: 1700000000,
        isEditorial: false,
        tags: const ['indexed_tag'],
      );
      await testContainer!.read(filesProvider.notifier).addFile(importedFile);
      await tester.pump();

      // Complete request
      apiCompleterA.complete({
        'title': 'Discovered Lake',
        'keywords': ['lake', 'water'],
        'description': '',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final allFiles = testContainer!.read(filesProvider).value!;
      final matching = allFiles.where((f) => f.path == fileA.path).toList();

      // Exactly ONE record, reusing imported-fixed-uuid
      expect(matching.length, 1);
      expect(matching.first.id, 'imported-fixed-uuid');
      expect(matching.first.metadataTitle, 'Discovered Lake');
      expect(matching.first.tags, contains('indexed_tag'));
    },
  );

  testWidgets(
    '7. Dispose during API/EXIF/dialog safely discards late responses without error or IO',
    (tester) async {
      final fileA = createTestFile('a.jpg');
      final appFileA = AppFile(
        id: 'id-a',
        path: fileA.path,
        filename: 'a.jpg',
        createdAt: 1700000000,
        isEditorial: true,
        editorialCity: '',
        tags: const [AppTags.editorial],
      );

      final exifCompleter =
          Completer<
            ({double? lat, double? lon, DateTime? date, bool hasAudio})
          >();
      final apiCompleter = Completer<Map<String, dynamic>>();
      int apiCalls = 0;
      int writes = 0;

      await pumpScreen(
        tester,
        initialFiles: [appFileA],
        readExif: (_) => exifCompleter.future,
        generateMetadata: ({
          required apiKey,
          required filePath,
          required options,
        }) async {
          apiCalls++;
          return apiCompleter.future;
        },
        writeMetadata: ({
          required filePath,
          required title,
          required keywords,
          description,
        }) async {
          writes++;
          return true;
        },
      );

      // Select A
      await tester.tap(find.text('a.jpg'));
      await tester.pump();

      // Start generation for A
      await tester.tap(find.text('AI метаданные'));
      await tester.pump();

      // Generation started and is waiting on EXIF
      final stateFinder = find.byType(GenerationScreen);
      expect(stateFinder, findsOneWidget);

      // Now unmount / dispose the screen
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Replaced'))),
      );
      await tester.pump();

      // Screen is now disposed
      expect(find.byType(GenerationScreen), findsNothing);

      // Complete EXIF and API after disposal
      exifCompleter.complete((
        lat: 10.0,
        lon: 20.0,
        date: DateTime(2026, 1, 1),
        hasAudio: false,
      ));
      await tester.pump();

      if (!apiCompleter.isCompleted) {
        apiCompleter.complete({
          'title': 'Late Title',
          'keywords': ['k'],
          'description': '',
        });
        await tester.pump();
      }

      // No new API calls were triggered after EXIF, and no writes occurred
      expect(apiCalls, 0);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final failureCount in [1, 3]) {
    testWidgets(
      'batch reports $failureCount failures and retries only those files',
      (tester) async {
        final files = List.generate(
          failureCount + 2,
          (i) => createTestFile('file$i.jpg'),
        );
        final appFiles = List<AppFile>.generate(
          failureCount + 2,
          (i) => AppFile(
            id: 'id-$i',
            path: files[i].path,
            filename: 'file$i.jpg',
            createdAt: 1700000000,
            isEditorial: false,
            tags: const [],
          ),
        );

        ProviderContainer? testContainer;
        final calls = <String>[];
        var shouldFail = true;

        await pumpScreen(
          tester,
          initialFiles: appFiles,
          onContainer: (c) => testContainer = c,
          generateMetadata: ({
            required apiKey,
            required filePath,
            required options,
          }) async {
            calls.add(filePath);
            if (shouldFail &&
                files.take(failureCount).any((f) => f.path == filePath)) {
              throw Exception('API network timeout: $filePath');
            }
            return {
              'title': 'Success for $filePath',
              'keywords': ['ok'],
              'description': '',
            };
          },
        );

        // Focus a successful file first to catch stale inspector targets on retry.
        await tester.tap(find.text(appFiles.last.filename));
        await tester.pump();

        // Select all files
        await tester.tap(find.byIcon(Icons.select_all));
        await tester.pump();

        // Start batch
        await tester.tap(
          find.byTooltip('AI метаданные'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // No unhandled exceptions in the test framework
        expect(tester.takeException(), isNull);

        final savedFiles = testContainer!.read(filesProvider).value!;
        for (final file in files.skip(failureCount)) {
          expect(
            savedFiles.singleWhere((f) => f.path == file.path).metadataTitle,
            'Success for ${file.path}',
          );
        }
        expect(find.textContaining('подготовлено: 2'), findsOneWidget);
        expect(find.textContaining('ошибок: $failureCount'), findsOneWidget);
        final failedPaths = files.take(failureCount).map((f) => f.path).toSet();
        expect(
          {
            for (final card in tester.widgetList<GenerationGridCard>(
              find.byType(GenerationGridCard),
            ))
              if (card.isSelected) card.imagePath,
          },
          failedPaths,
        );
        expect(
          testContainer!.read(activeGridSelectionProvider).toSet(),
          appFiles.take(failureCount).map((f) => f.id).toSet(),
        );

        await tester.pumpAndSettle();
        await tester.tap(find.text('Подробности'));
        await tester.pumpAndSettle();
        expect(find.text('Ошибки атрибутации'), findsOneWidget);
        for (final path in failedPaths) {
          expect(
            find.textContaining('API network timeout: $path'),
            findsOneWidget,
          );
        }
        await tester.tap(find.text('Закрыть'));
        await tester.pumpAndSettle();

        shouldFail = false;
        calls.clear();
        await tester.tap(
          find.byTooltip('AI метаданные'),
        );
        await tester.pumpAndSettle();
        expect(calls.toSet(), failedPaths);
        expect(calls, hasLength(failureCount));
        for (final file in testContainer!.read(filesProvider).value!) {
          expect(file.metadataTitle, 'Success for ${file.path}');
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('apply to all is decided before the next batch dialog enters', (
    tester,
  ) async {
    final initial = List.generate(4, (i) {
      final file = createTestFile('repeat$i.jpg');
      return AppFile(
        id: '$i',
        path: file.path,
        filename: 'repeat$i.jpg',
        createdAt: 1,
        metadataTitle: 'Old',
        metadataKeywords: 'old',
      );
    });
    final decision = Completer<({bool replace, bool applyToAll})?>();
    var dialogs = 0;
    var generated = 0;
    await pumpScreen(
      tester,
      initialFiles: initial,
      showRegenerateDialog: (_) {
        dialogs++;
        return decision.future;
      },
      generateMetadata: ({
        required apiKey,
        required filePath,
        required options,
      }) async {
        generated++;
        return {
          'title': 'New',
          'keywords': ['new'],
        };
      },
    );
    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pump();
    await tester.tap(find.byTooltip('AI метаданные'));
    await tester.pump();
    expect(dialogs, 1);
    decision.complete((replace: true, applyToAll: true));
    await tester.pumpAndSettle();
    expect(dialogs, 1);
    expect(generated, 4);
  });

  for (final duringDialog in [false, true]) {
    testWidgets(
      'dispose while waiting on ${duringDialog ? 'regeneration dialog' : 'API'} discards continuation',
      (tester) async {
        final file = createTestFile('waiting.jpg');
        final initial = AppFile(
          id: 'waiting',
          path: file.path,
          filename: 'waiting.jpg',
          createdAt: 1,
          metadataTitle: duringDialog ? 'Old' : null,
          metadataKeywords: duringDialog ? 'old' : null,
        );
        final api = Completer<Map<String, dynamic>>();
        final dialog = Completer<({bool replace, bool applyToAll})?>();
        var apiCalls = 0;
        ProviderContainer? container;
        await pumpScreen(
          tester,
          initialFiles: [
            initial,
            if (duringDialog)
              AppFile(
                id: 'second',
                path: createTestFile('second.jpg').path,
                filename: 'second.jpg',
                createdAt: 1,
                metadataTitle: 'Old',
                metadataKeywords: 'old',
              ),
          ],
          onContainer: (c) => container = c,
          showRegenerateDialog: (_) => dialog.future,
          generateMetadata: ({
            required apiKey,
            required filePath,
            required options,
          }) {
            apiCalls++;
            return api.future;
          },
        );
        if (duringDialog) {
          await tester.tap(find.byIcon(Icons.select_all));
          await tester.pump();
          await tester.tap(
            find.byTooltip('AI метаданные'),
          );
        } else {
          await tester.tap(find.text('waiting.jpg'));
          await tester.pump();
          await tester.tap(find.text('AI метаданные'));
        }
        await tester.pump();
        expect(apiCalls, duringDialog ? 0 : 1);
        await tester.pumpWidget(const SizedBox());
        if (duringDialog) {
          dialog.complete((replace: true, applyToAll: true));
        } else {
          api.complete({
            'title': 'Late',
            'keywords': ['late'],
          });
        }
        await tester.pumpAndSettle();
        expect(apiCalls, duringDialog ? 0 : 1);
        expect(writtenFiles, isEmpty);
        expect(
          container!.read(filesProvider).value!.first.metadataTitle,
          initial.metadataTitle,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final batch in [false, true]) {
    testWidgets(
      '${batch ? 'batch' : 'single'} does not recreate a missing catalog target with a new id',
      (tester) async {
        final initial = List.generate(batch ? 2 : 1, (i) {
          final file = createTestFile('original$i.jpg');
          return AppFile(
            id: 'original-$i',
            path: file.path,
            filename: 'original$i.jpg',
            createdAt: 1,
            tags: [AppTags.aiGenerated],
          );
        });
        final response = Completer<Map<String, dynamic>>();
        ProviderContainer? container;
        await pumpScreen(
          tester,
          initialFiles: initial,
          onContainer: (c) => container = c,
          generateMetadata:
              ({required apiKey, required filePath, required options}) =>
                  response.future,
        );
        if (batch) {
          await tester.tap(find.byIcon(Icons.select_all));
          await tester.pump();
          await tester.tap(
            find.byTooltip('AI метаданные'),
          );
        } else {
          await tester.tap(find.text('original0.jpg'));
          await tester.pump();
          await tester.tap(find.text('AI метаданные'));
        }
        await tester.pump();
        final notifier =
            container!.read(filesProvider.notifier) as FakeFilesNotifier;
        notifier.hideFromCatalog();
        response.complete({
          'title': 'Late',
          'keywords': ['late'],
        });
        await tester.pumpAndSettle();
        expect(notifier.addedFiles, isEmpty);
        expect(writtenFiles, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
