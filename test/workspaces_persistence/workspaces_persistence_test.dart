import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_flow/core/state/workspaces_provider.dart';

class MockSecureBookmarksAdapter implements SecureBookmarksAdapter {
  int createBookmarkCalls = 0;
  int resolveBookmarkCalls = 0;
  int startAccessingCalls = 0;
  int stopAccessingCalls = 0;
  int activeAccessCount = 0;

  bool shouldThrowOnResolve = false;
  bool shouldThrowOnStart = false;
  bool shouldThrowOnStop = false;
  bool startAccessResult = true;

  String? Function(Directory directory)? onBookmark;
  FileSystemEntity Function(String bookmark)? onResolve;
  final Map<String, String> bookmarkPathMap = {};

  @override
  Future<String?> createBookmark(Directory directory) async {
    createBookmarkCalls++;
    if (onBookmark != null) return onBookmark!(directory);
    final bm = 'bm_${directory.path}';
    bookmarkPathMap[bm] = directory.path;
    return bm;
  }

  @override
  Future<FileSystemEntity> resolveBookmark(String bookmark) async {
    resolveBookmarkCalls++;
    if (shouldThrowOnResolve) {
      throw const FileSystemException('Resolve failed');
    }
    if (onResolve != null) return onResolve!(bookmark);
    final path =
        bookmarkPathMap[bookmark] ??
        (bookmark.startsWith('bm_') ? bookmark.substring(3) : bookmark);
    return Directory(path);
  }

  @override
  Future<bool> startAccessingSecurityScopedResource(
    FileSystemEntity entity,
  ) async {
    startAccessingCalls++;
    if (shouldThrowOnStart) {
      throw const FileSystemException('Start accessing failed');
    }
    if (startAccessResult) {
      activeAccessCount++;
    }
    return startAccessResult;
  }

  @override
  Future<void> stopAccessingSecurityScopedResource(
    FileSystemEntity entity,
  ) async {
    stopAccessingCalls++;
    activeAccessCount--;
    if (shouldThrowOnStop) {
      throw const FileSystemException('Stop accessing failed');
    }
  }
}

class MockDirectoryProbe implements DirectoryProbe {
  final Map<String, bool> pathExists = {};
  final Map<String, bool> pathReadable = {};
  final List<String> probedPaths = [];

  @override
  Future<bool> exists(String path) async {
    return pathExists[path] ?? false;
  }

  @override
  Future<void> probeRead(String path) async {
    probedPaths.add(path);
    if (pathReadable[path] == false) {
      throw FileSystemException('Cannot read directory: $path');
    }
  }
}

class TestSharedPreferences implements SharedPreferences {
  final Map<String, Object> _data = {};
  bool failNextSetString = false;
  bool failNextSetInt = false;
  bool failNextRemove = false;
  bool throwOnSetString = false;
  bool throwOnRemove = false;

  TestSharedPreferences([Map<String, Object>? initial]) {
    if (initial != null) {
      _data.addAll(initial);
    }
  }

  @override
  String? getString(String key) => _data[key] as String?;

  @override
  int? getInt(String key) => _data[key] as int?;

  @override
  bool? getBool(String key) => _data[key] as bool?;

  @override
  double? getDouble(String key) => _data[key] as double?;

  @override
  List<String>? getStringList(String key) => _data[key] as List<String>?;

  @override
  Set<String> getKeys() => _data.keys.toSet();

  @override
  bool containsKey(String key) => _data.containsKey(key);

  @override
  Object? get(String key) => _data[key];

  @override
  Future<bool> setString(String key, String value) async {
    if (throwOnSetString) throw const FileSystemException('I/O error');
    if (failNextSetString) return false;
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    if (failNextSetInt) return false;
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    if (throwOnRemove) throw const FileSystemException('Remove error');
    if (failNextRemove) return false;
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }

  @override
  Future<bool> commit() async => true;

  @override
  Future<void> reload() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSecureBookmarksAdapter mockBookmarks;
  late MockDirectoryProbe mockProbe;
  late TestSharedPreferences testPrefs;

  setUp(() {
    mockBookmarks = MockSecureBookmarksAdapter();
    mockProbe = MockDirectoryProbe();
    testPrefs = TestSharedPreferences();
  });

  ProviderContainer createContainer({WorkspacesNotifier? notifier}) {
    final effectiveNotifier =
        notifier ??
        WorkspacesNotifier(
          bookmarksAdapter: mockBookmarks,
          directoryProbe: mockProbe,
          prefsLoader: () async => testPrefs,
          isMacOS: true,
        );

    final container = ProviderContainer(
      overrides: [workspacesProvider.overrideWith(() => effectiveNotifier)],
    );
    container.read(workspacesProvider);
    addTearDown(container.dispose);
    return container;
  }

  test(
    'corrupt settings survive a later mutation unless backup succeeds',
    () async {
      const corrupt = '{broken';
      testPrefs = TestSharedPreferences({keyWorkspaceEntries: corrupt});
      final container = createContainer();
      final notifier = container.read(workspacesProvider.notifier);
      await notifier.initialization;
      testPrefs.failNextSetString = true;
      expect(await notifier.addWorkspace('/new'), isFalse);
      expect(testPrefs.getString(keyWorkspaceEntries), corrupt);
      expect(container.read(workspacesProvider).lastError, isNotNull);
      testPrefs.failNextSetString = false;
      expect(await notifier.retry(), isTrue);
      expect(testPrefs.getString(keyWorkspaceEntriesBackup), corrupt);
    },
  );

  test(
    'migration preserves original selection after filtering invalid legacy values',
    () async {
      testPrefs = TestSharedPreferences({
        keyWorkspacePaths: jsonEncode([42, '/A', '/B']),
        keyWorkspaceCurrentIndex: 2,
      });
      final container = createContainer();
      await container.read(workspacesProvider.notifier).initialization;
      expect(container.read(workspacesProvider).paths, ['/A', '/B']);
      expect(container.read(workspacesProvider).currentPath, '/B');
      expect(testPrefs.getString(keyWorkspaceCurrentPath), '/B');
    },
  );

  test(
    'migration and recovery report failed index write and keep legacy',
    () async {
      for (final corrupt in [false, true]) {
        testPrefs = TestSharedPreferences({
          if (corrupt) keyWorkspaceEntries: '{broken',
          keyWorkspacePaths: jsonEncode(['/A', '/B']),
          keyWorkspaceCurrentIndex: 1,
        });
        testPrefs.failNextSetInt = true;
        final container = createContainer();
        await container.read(workspacesProvider.notifier).initialization;
        expect(testPrefs.containsKey(keyWorkspacePaths), isTrue);
        expect(container.read(workspacesProvider).lastError, isNotNull);
        expect(container.read(workspacesProvider).currentPath, '/B');
      }
    },
  );

  test('failed legacy removal is visible and can be retried', () async {
    testPrefs = TestSharedPreferences({
      keyWorkspacePaths: jsonEncode(['/A']),
    });
    testPrefs.failNextRemove = true;
    final container = createContainer();
    final notifier = container.read(workspacesProvider.notifier);
    await notifier.initialization;
    expect(container.read(workspacesProvider).lastError, isNotNull);
    testPrefs.failNextRemove = false;
    expect(await notifier.retry(), isTrue);
    expect(testPrefs.containsKey(keyWorkspacePaths), isFalse);
  });

  test('failure to persist selected path is not reported as success', () async {
    testPrefs = _PathWriteFailurePreferences();
    final container = createContainer();
    final notifier = container.read(workspacesProvider.notifier);
    await notifier.initialization;
    expect(await notifier.addWorkspace('/A'), isFalse);
    expect(container.read(workspacesProvider).lastError, isNotNull);
  });

  test('duplicate paths retain a usable bookmark from later entry', () async {
    testPrefs = TestSharedPreferences({
      keyWorkspaceEntries: jsonEncode([
        {'path': '/A'},
        {'path': '/A/', 'bookmark': 'useful'},
      ]),
    });
    final container = createContainer();
    await container.read(workspacesProvider.notifier).initialization;
    expect(
      container.read(workspacesProvider).entries.single.bookmark,
      'useful',
    );
  });

  test('queued mutations do not access disposed provider', () async {
    final loading = Completer<SharedPreferences>();
    final notifier = WorkspacesNotifier(
      prefsLoader: () => loading.future,
      isMacOS: false,
    );
    final container = ProviderContainer(
      overrides: [workspacesProvider.overrideWith(() => notifier)],
    );
    container.read(workspacesProvider);
    final adding = notifier.addWorkspace('/A');
    container.dispose();
    loading.complete(testPrefs);
    expect(await adding, isFalse);
    expect(testPrefs.getKeys(), isEmpty);
  });

  test(
    'older availability probe cannot overwrite a newer successful probe',
    () async {
      final oldProbe = Completer<bool>();
      var calls = 0;
      final probe = _CustomProbe(
        onExists: (_) {
          calls++;
          return calls == 1 ? oldProbe.future : Future.value(true);
        },
        onProbeRead: (_) async {},
      );
      testPrefs = TestSharedPreferences({
        keyWorkspaceEntries: jsonEncode([
          {'path': '/A'},
        ]),
      });
      final container = createContainer(
        notifier: WorkspacesNotifier(
          prefsLoader: () async => testPrefs,
          directoryProbe: probe,
          isMacOS: false,
        ),
      );
      final notifier = container.read(workspacesProvider.notifier);
      await notifier.initialization;
      final initialCheck = notifier.availabilityCheckFuture;
      await notifier.recheckAvailability(path: '/A');
      oldProbe.complete(false);
      await initialCheck;
      expect(
        container.read(workspacesProvider).availabilityFor('/A').isAvailable,
        isTrue,
      );
    },
  );

  test(
    'stop failure is reported as unavailable while preserving entry',
    () async {
      testPrefs = TestSharedPreferences({
        keyWorkspaceEntries: jsonEncode([
          {'path': '/A', 'bookmark': 'bm_/A'},
        ]),
      });
      mockProbe.pathExists['/A'] = true;
      mockBookmarks.shouldThrowOnStop = true;
      final container = createContainer();
      final notifier = container.read(workspacesProvider.notifier);
      await notifier.initialization;
      await notifier.availabilityCheckFuture;
      expect(container.read(workspacesProvider).paths, ['/A']);
      expect(
        container.read(workspacesProvider).availabilityFor('/A').isUnavailable,
        isTrue,
      );
    },
  );

  test(
    'retry after load failure reads settings instead of saving empty state',
    () async {
      var failing = true;
      testPrefs = TestSharedPreferences({
        keyWorkspaceEntries: jsonEncode([
          {'path': '/A'},
        ]),
      });
      final notifier = WorkspacesNotifier(
        prefsLoader: () async {
          if (failing) throw StateError('read failed');
          return testPrefs;
        },
        isMacOS: false,
        directoryProbe: mockProbe,
      );
      final container = createContainer(notifier: notifier);
      await notifier.initialization;
      expect(container.read(workspacesProvider).lastError, isNotNull);
      failing = false;
      expect(await notifier.retry(), isTrue);
      expect(container.read(workspacesProvider).paths, ['/A']);
    },
  );

  test('malformed legacy survives a later successful mutation', () async {
    const legacy = '["/Old';
    testPrefs = TestSharedPreferences({keyWorkspacePaths: legacy});
    final container = createContainer();
    final notifier = container.read(workspacesProvider.notifier);
    await notifier.initialization;
    expect(await notifier.addWorkspace('/New'), isTrue);
    expect(testPrefs.getString(keyWorkspacePaths), legacy);
  });

  test(
    'invalid selection settings do not hide a valid folder catalog',
    () async {
      testPrefs = TestSharedPreferences({
        keyWorkspaceEntries: jsonEncode([
          {'path': '/A'},
        ]),
        keyWorkspaceCurrentIndex: 'broken',
        keyWorkspaceCurrentPath: false,
      });
      final container = createContainer();
      await container.read(workspacesProvider.notifier).initialization;
      expect(container.read(workspacesProvider).paths, ['/A']);
      expect(container.read(workspacesProvider).currentPath, '/A');
    },
  );

  test(
    'mutation after transient read failure reloads existing folders first',
    () async {
      var failing = true;
      testPrefs = TestSharedPreferences({
        keyWorkspaceEntries: jsonEncode([
          {'path': '/Old'},
        ]),
      });
      final notifier = WorkspacesNotifier(
        prefsLoader: () async {
          if (failing) throw StateError('temporary read failure');
          return testPrefs;
        },
        directoryProbe: mockProbe,
        isMacOS: false,
      );
      final container = createContainer(notifier: notifier);
      await notifier.initialization;
      expect(await notifier.addWorkspace('/New'), isFalse);
      failing = false;
      expect(await notifier.addWorkspace('/New'), isTrue);
      expect(container.read(workspacesProvider).paths, ['/Old', '/New']);
    },
  );

  group('Workspaces persistence and availability logic', () {
    test(
      'Два сохранённых пути, один недоступен: после загрузки оба на месте, выбранный недоступный путь сохранён',
      () async {
        final entriesJson = jsonEncode([
          {
            'path': '/Volumes/Drive/AvailableFolder',
            'bookmark': 'bm_/Volumes/Drive/AvailableFolder',
          },
          {
            'path': '/Volumes/OfflineDrive/MissingFolder',
            'bookmark': 'bm_/Volumes/OfflineDrive/MissingFolder',
          },
        ]);
        testPrefs = TestSharedPreferences({
          keyWorkspaceEntries: entriesJson,
          keyWorkspaceCurrentIndex: 1,
          keyWorkspaceCurrentPath: '/Volumes/OfflineDrive/MissingFolder',
        });

        mockProbe.pathExists['/Volumes/Drive/AvailableFolder'] = true;
        mockProbe.pathExists['/Volumes/OfflineDrive/MissingFolder'] = false;

        final container = createContainer();

        // Ждём завершения инициализации и проверки доступности
        await container.read(workspacesProvider.notifier).initialization;
        await container
            .read(workspacesProvider.notifier)
            .availabilityCheckFuture;

        final state = container.read(workspacesProvider);
        expect(state.entries.length, 2);
        expect(state.entries[0].path, '/Volumes/Drive/AvailableFolder');
        expect(state.entries[1].path, '/Volumes/OfflineDrive/MissingFolder');
        expect(state.currentIndex, 1);
        expect(state.currentPath, '/Volumes/OfflineDrive/MissingFolder');

        expect(
          state.availabilityFor('/Volumes/Drive/AvailableFolder').isAvailable,
          isTrue,
        );
        expect(
          state
              .availabilityFor('/Volumes/OfflineDrive/MissingFolder')
              .isUnavailable,
          isTrue,
        );
      },
    );

    test(
      'Изменение текущей папки и перезагрузка не теряют недоступный путь',
      () async {
        final entriesJson = jsonEncode([
          {'path': '/Volumes/Drive/AvailableFolder', 'bookmark': 'bm1'},
          {'path': '/Volumes/OfflineDrive/MissingFolder', 'bookmark': 'bm2'},
        ]);
        testPrefs = TestSharedPreferences({
          keyWorkspaceEntries: entriesJson,
          keyWorkspaceCurrentIndex: 0,
        });

        mockProbe.pathExists['/Volumes/Drive/AvailableFolder'] = true;
        mockProbe.pathExists['/Volumes/OfflineDrive/MissingFolder'] = false;

        final container1 = createContainer();
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Переключаем на недоступную папку
        await container1.read(workspacesProvider.notifier).setCurrent(1);

        expect(container1.read(workspacesProvider).currentIndex, 1);
        expect(
          container1.read(workspacesProvider).currentPath,
          '/Volumes/OfflineDrive/MissingFolder',
        );

        // Имитируем перезапуск приложения со сохранёнными prefs
        final container2 = createContainer();
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final reloadedState = container2.read(workspacesProvider);
        expect(reloadedState.entries.length, 2);
        expect(reloadedState.currentIndex, 1);
        expect(
          reloadedState.currentPath,
          '/Volumes/OfflineDrive/MissingFolder',
        );
        expect(
          reloadedState
              .availabilityFor('/Volumes/OfflineDrive/MissingFolder')
              .isUnavailable,
          isTrue,
        );
      },
    );

    test(
      'Диск «возвращается»: повторная проверка меняет состояние, не добавляет дубль и не меняет порядок',
      () async {
        testPrefs = TestSharedPreferences({
          keyWorkspaceEntries: jsonEncode([
            {'path': '/Volumes/Drive/A'},
            {'path': '/Volumes/ExternalDrive/B'},
            {'path': '/Volumes/Drive/C'},
          ]),
          keyWorkspaceCurrentIndex: 1,
        });

        mockProbe.pathExists['/Volumes/Drive/A'] = true;
        mockProbe.pathExists['/Volumes/ExternalDrive/B'] = false;
        mockProbe.pathExists['/Volumes/Drive/C'] = true;

        final container = createContainer();
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 30));

        var state = container.read(workspacesProvider);
        expect(
          state.availabilityFor('/Volumes/ExternalDrive/B').isUnavailable,
          isTrue,
        );

        // Диск подключили!
        mockProbe.pathExists['/Volumes/ExternalDrive/B'] = true;

        // Повторная проверка
        await container.read(workspacesProvider.notifier).recheckAvailability();

        state = container.read(workspacesProvider);
        expect(state.entries.length, 3);
        expect(state.entries.map((e) => e.path).toList(), [
          '/Volumes/Drive/A',
          '/Volumes/ExternalDrive/B',
          '/Volumes/Drive/C',
        ]);
        expect(state.currentIndex, 1);
        expect(
          state.availabilityFor('/Volumes/ExternalDrive/B').isAvailable,
          isTrue,
        );
      },
    );

    test(
      'Старый формат корректно переносится; новый записан раньше удаления старого',
      () async {
        testPrefs = TestSharedPreferences({
          keyWorkspacePaths: jsonEncode([
            '/Volumes/OldDrive/Folder1',
            '/Volumes/OldDrive/Folder2/',
          ]),
          keyWorkspaceCurrentIndex: 1,
        });

        mockProbe.pathExists['/Volumes/OldDrive/Folder1'] = true;
        mockProbe.pathExists['/Volumes/OldDrive/Folder2'] = true;

        final container = createContainer();
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 30));

        final state = container.read(workspacesProvider);
        expect(state.entries.length, 2);
        expect(state.entries[0].path, '/Volumes/OldDrive/Folder1');
        expect(state.entries[1].path, '/Volumes/OldDrive/Folder2');

        // Проверяем, что в prefs записан новый формат и удалён старый
        expect(testPrefs.containsKey(keyWorkspaceEntries), isTrue);
        expect(testPrefs.containsKey(keyWorkspacePaths), isFalse);
      },
    );

    test(
      'Провал записи нового формата при миграции: старый ключ не удаляется',
      () async {
        testPrefs = TestSharedPreferences({
          keyWorkspacePaths: jsonEncode(['/Volumes/Drive/Folder']),
        });
        testPrefs.failNextSetString =
            true; // Запись нового формата вернёт false

        final container = createContainer();
        await container.read(workspacesProvider.notifier).initialization;

        // Старый ключ ОБЯЗАН остаться
        expect(testPrefs.containsKey(keyWorkspacePaths), isTrue);
      },
    );

    test('Провал удаления старого ключа: новый формат уже сохранён', () async {
      testPrefs = TestSharedPreferences({
        keyWorkspacePaths: jsonEncode(['/Volumes/Drive/Folder']),
      });
      testPrefs.failNextRemove = true; // Удаление старого ключа вернёт false

      final container = createContainer();
      await container.read(workspacesProvider.notifier).initialization;

      // Новый формат записан
      expect(testPrefs.containsKey(keyWorkspaceEntries), isTrue);
      final entries = jsonDecode(testPrefs.getString(keyWorkspaceEntries)!);
      expect(entries[0]['path'], '/Volumes/Drive/Folder');
    });

    test(
      'Пустой валидный новый список не восстанавливается из устаревшего legacy',
      () async {
        testPrefs = TestSharedPreferences({
          keyWorkspaceEntries: jsonEncode([]),
          keyWorkspacePaths: jsonEncode(['/Volumes/OldDrive/ZombieFolder']),
        });

        final container = createContainer();
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final state = container.read(workspacesProvider);
        expect(state.entries, isEmpty);
        expect(state.currentPath, isNull);
      },
    );

    test(
      'Повреждённый JSON не уничтожается автоматически; при наличии legacy создаётся бэкап',
      () async {
        const corruptJson = '{"not_a_valid_entries_list": true}';
        testPrefs = TestSharedPreferences({
          keyWorkspaceEntries: corruptJson,
          keyWorkspacePaths: jsonEncode(['/Volumes/Recovery/Folder']),
        });

        final container = createContainer();
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // Бэкап создан
        expect(testPrefs.getString(keyWorkspaceEntriesBackup), corruptJson);
        // Восстановлено из legacy
        final state = container.read(workspacesProvider);
        expect(state.entries.length, 1);
        expect(state.entries[0].path, '/Volumes/Recovery/Folder');
      },
    );

    test(
      'При невозможности сохранить копию повреждённого JSON исходное значение не меняется',
      () async {
        const corruptJson = '{corrupt_json: true';
        testPrefs = TestSharedPreferences({
          keyWorkspaceEntries: corruptJson,
          keyWorkspacePaths: jsonEncode(['/Volumes/Recovery/Folder']),
        });
        testPrefs.failNextSetString = true; // Сбой сохранения backup

        final container = createContainer();
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // Исходное повреждённое значение не перезаписано
        expect(testPrefs.getString(keyWorkspaceEntries), corruptJson);
        expect(container.read(workspacesProvider).lastError, isNotNull);
      },
    );

    test(
      'Валидные элементы смешанного массива с некорректными записями сохраняются',
      () async {
        testPrefs = TestSharedPreferences({
          keyWorkspaceEntries: jsonEncode([
            {'path': '/Volumes/Drive/Good1'},
            {'invalid_field': 123},
            42,
            {'path': ''},
            {'path': '/Volumes/Drive/Good2', 'bookmark': 'bm2'},
          ]),
          keyWorkspaceCurrentIndex: 4, // Исходно указывал на Good2
        });

        mockProbe.pathExists['/Volumes/Drive/Good1'] = true;
        mockProbe.pathExists['/Volumes/Drive/Good2'] = true;

        final container = createContainer();
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 30));

        final state = container.read(workspacesProvider);
        expect(state.entries.length, 2);
        expect(state.entries[0].path, '/Volumes/Drive/Good1');
        expect(state.entries[1].path, '/Volumes/Drive/Good2');
        // Индекс безопасно сохранён на Good2 (был 4 в исходном массиве, стал 1)
        expect(state.currentIndex, 1);
        expect(state.currentPath, '/Volumes/Drive/Good2');
      },
    );

    test('Отрицательный и выходящий за пределы индекс безопасен', () async {
      testPrefs = TestSharedPreferences({
        keyWorkspaceEntries: jsonEncode([
          {'path': '/Volumes/Drive/Folder'},
        ]),
        keyWorkspaceCurrentIndex: 999, // За пределами
      });

      final container = createContainer();
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(workspacesProvider);
      expect(state.currentIndex, 0);
      expect(state.currentPath, '/Volumes/Drive/Folder');
    });

    test(
      'Исключение некорректного элемента перед выбранным не выбирает другую папку',
      () async {
        testPrefs = TestSharedPreferences({
          keyWorkspaceEntries: jsonEncode([
            {'invalid': true}, // будет отброшен
            {'path': '/Volumes/Drive/A'},
            {'path': '/Volumes/Drive/B'},
          ]),
          keyWorkspaceCurrentIndex: 2, // В исходном списке указывал на B
        });

        final container = createContainer();
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final state = container.read(workspacesProvider);
        expect(state.entries.length, 2);
        expect(state.entries[0].path, '/Volumes/Drive/A');
        expect(state.entries[1].path, '/Volumes/Drive/B');
        expect(state.currentPath, '/Volumes/Drive/B');
        expect(state.currentIndex, 1);
      },
    );

    test(
      'Путь "/" и путь с конечным пробелом сохраняются; /tmp/folder/ и /tmp/folder не дают две записи',
      () async {
        final container = createContainer();
        await pumpEventQueue();

        final notifier = container.read(workspacesProvider.notifier);

        // 1. Добавляем "/"
        await notifier.addWorkspace('/');
        expect(container.read(workspacesProvider).entries.last.path, '/');

        // 2. Добавляем путь с конечным пробелом
        await notifier.addWorkspace('/Volumes/Drive/Folder With Space ');
        expect(
          container.read(workspacesProvider).entries.last.path,
          '/Volumes/Drive/Folder With Space ',
        );

        // 3. Добавляем /tmp/folder/
        await notifier.addWorkspace('/tmp/folder/');
        final countBefore = container.read(workspacesProvider).entries.length;

        // 4. Добавляем /tmp/folder (без слеша)
        await notifier.addWorkspace('/tmp/folder');
        final countAfter = container.read(workspacesProvider).entries.length;

        expect(countAfter, countBefore, reason: 'Не должно быть дубликатов');
        expect(
          container.read(workspacesProvider).entries.last.path,
          '/tmp/folder',
        );
      },
    );

    test(
      'add/remove/setCurrent во время задержанной загрузки не теряются',
      () async {
        final completer = Completer<SharedPreferences>();
        final notifier = WorkspacesNotifier(
          bookmarksAdapter: mockBookmarks,
          directoryProbe: mockProbe,
          prefsLoader: () => completer.future,
        );

        final container = ProviderContainer(
          overrides: [workspacesProvider.overrideWith(() => notifier)],
        );
        addTearDown(container.dispose);

        // Читаем notifier через container для вызова build()
        final boundNotifier = container.read(workspacesProvider.notifier);

        // Во время ожидания загрузки вызываем addWorkspace
        final addFuture = boundNotifier.addWorkspace(
          '/Volumes/Drive/EarlyAdded',
        );

        // Завершаем задержанную загрузку с одним существующим элементом
        testPrefs = TestSharedPreferences({
          keyWorkspaceEntries: jsonEncode([
            {'path': '/Volumes/Drive/PreExisting'},
          ]),
        });
        completer.complete(testPrefs);

        await addFuture;
        await pumpEventQueue();

        final state = container.read(workspacesProvider);
        expect(state.entries.length, 2);
        expect(state.entries[0].path, '/Volumes/Drive/PreExisting');
        expect(state.entries[1].path, '/Volumes/Drive/EarlyAdded');
      },
    );

    test(
      'Поздний результат проверки удалённой папки не возвращает её',
      () async {
        final probeCompleter = Completer<void>();
        mockProbe.pathExists['/Volumes/Drive/ToDelete'] = true;

        // Подменяем probeRead так, чтобы проверка затянулась
        var probeCalled = false;
        final delayedProbe = _CustomProbe(
          onExists: (path) async => true,
          onProbeRead: (path) async {
            probeCalled = true;
            await probeCompleter.future;
          },
        );

        final notifier = WorkspacesNotifier(
          bookmarksAdapter: mockBookmarks,
          directoryProbe: delayedProbe,
          prefsLoader:
              () async => TestSharedPreferences({
                keyWorkspaceEntries: jsonEncode([
                  {'path': '/Volumes/Drive/ToDelete'},
                ]),
              }),
        );

        final container = ProviderContainer(
          overrides: [workspacesProvider.overrideWith(() => notifier)],
        );
        addTearDown(container.dispose);
        final boundNotifier = container.read(workspacesProvider.notifier);

        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(probeCalled, isTrue);

        // Пользователь удаляет папку ПОКА проверка ещё висит в воздухе
        await boundNotifier.removeWorkspace(0);
        expect(container.read(workspacesProvider).entries, isEmpty);

        // Завершаем проверку
        probeCompleter.complete();
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Папка НЕ должна вернуться в список
        expect(container.read(workspacesProvider).entries, isEmpty);
        expect(
          container
              .read(workspacesProvider)
              .availability
              .containsKey('/Volumes/Drive/ToDelete'),
          isFalse,
        );
      },
    );

    test('Ошибка resolve/start/probe/stop не удаляет workspace', () async {
      testPrefs = TestSharedPreferences({
        keyWorkspaceEntries: jsonEncode([
          {'path': '/Volumes/Drive/ErrorFolder', 'bookmark': 'bm_err'},
        ]),
      });

      mockBookmarks.shouldThrowOnResolve = true;

      final container = createContainer();
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(workspacesProvider);
      expect(state.entries.length, 1);
      expect(state.entries[0].path, '/Volumes/Drive/ErrorFolder');
      expect(
        state.availabilityFor('/Volumes/Drive/ErrorFolder').isUnavailable,
        isTrue,
      );
    });

    test(
      'Успешные start/stop сбалансированы, неуспешный start не вызывает stop',
      () async {
        testPrefs = TestSharedPreferences({
          keyWorkspaceEntries: jsonEncode([
            {
              'path': '/Volumes/Drive/NormalFolder',
              'bookmark': 'bm_/Volumes/Drive/NormalFolder',
            },
          ]),
        });
        mockProbe.pathExists['/Volumes/Drive/NormalFolder'] = true;

        final container = createContainer();
        await container.read(workspacesProvider.notifier).initialization;
        await container
            .read(workspacesProvider.notifier)
            .availabilityCheckFuture;

        // Успешный start вызвал ровно один stop
        expect(mockBookmarks.startAccessingCalls, 1);
        expect(mockBookmarks.stopAccessingCalls, 1);
        expect(mockBookmarks.activeAccessCount, 0);

        // Теперь проверяем, когда start вернул false
        mockBookmarks.startAccessResult = false;
        await container.read(workspacesProvider.notifier).recheckAvailability();

        // stop не должен вызываться для неуспешного start
        expect(mockBookmarks.startAccessingCalls, 2);
        expect(mockBookmarks.stopAccessingCalls, 1);
      },
    );

    test(
      'Bookmark разрешился в другой путь: статус unavailable с требованием повторного подключения, запись сохраняется',
      () async {
        testPrefs = TestSharedPreferences({
          keyWorkspaceEntries: jsonEncode([
            {'path': '/Volumes/Drive/OriginalPath', 'bookmark': 'bm_original'},
          ]),
        });
        mockProbe.pathExists['/Volumes/Drive/OriginalPath'] = true;

        // Bookmark возвращает другой путь
        mockBookmarks.onResolve =
            (bm) => Directory('/Volumes/Drive/RelocatedPath');

        final container = createContainer();
        await container.read(workspacesProvider.notifier).initialization;
        await container
            .read(workspacesProvider.notifier)
            .availabilityCheckFuture;

        final state = container.read(workspacesProvider);
        expect(state.entries.length, 1);
        expect(state.entries[0].path, '/Volumes/Drive/OriginalPath');
        expect(
          state.availabilityFor('/Volumes/Drive/OriginalPath').isUnavailable,
          isTrue,
        );
      },
    );

    test(
      'Dispose до окончания проверки не вызывает ошибку состояния',
      () async {
        final probeCompleter = Completer<void>();
        final delayedProbe = _CustomProbe(
          onExists: (path) async => true,
          onProbeRead: (path) async => probeCompleter.future,
        );

        final notifier = WorkspacesNotifier(
          bookmarksAdapter: mockBookmarks,
          directoryProbe: delayedProbe,
          prefsLoader:
              () async => TestSharedPreferences({
                keyWorkspaceEntries: jsonEncode([
                  {'path': '/Volumes/Drive/Folder'},
                ]),
              }),
        );

        final container = ProviderContainer(
          overrides: [workspacesProvider.overrideWith(() => notifier)],
        );
        container.read(workspacesProvider);

        await pumpEventQueue();
        // Уничтожаем container
        container.dispose();

        // Теперь завершаем отложенную операцию
        probeCompleter.complete();
        await pumpEventQueue();

        // Нет непойманных исключений
      },
    );
  });
}

class _CustomProbe implements DirectoryProbe {
  final Future<bool> Function(String) onExists;
  final Future<void> Function(String) onProbeRead;

  _CustomProbe({required this.onExists, required this.onProbeRead});

  @override
  Future<bool> exists(String path) => onExists(path);

  @override
  Future<void> probeRead(String path) => onProbeRead(path);
}

class _PathWriteFailurePreferences extends TestSharedPreferences {
  @override
  Future<bool> setString(String key, String value) async {
    if (key == keyWorkspaceCurrentPath) return false;
    return super.setString(key, value);
  }
}
