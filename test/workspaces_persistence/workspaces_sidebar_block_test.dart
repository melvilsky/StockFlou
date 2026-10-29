import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_flow/core/state/workspaces_provider.dart';
import 'package:stock_flow/core/widgets/workspaces_sidebar_block.dart';

class MockBookmarks implements SecureBookmarksAdapter {
  @override
  Future<String?> createBookmark(Directory directory) async =>
      'bm_${directory.path}';

  @override
  Future<FileSystemEntity> resolveBookmark(String bookmark) async {
    final path = bookmark.startsWith('bm_') ? bookmark.substring(3) : bookmark;
    return Directory(path);
  }

  @override
  Future<bool> startAccessingSecurityScopedResource(
    FileSystemEntity entity,
  ) async => true;

  @override
  Future<void> stopAccessingSecurityScopedResource(
    FileSystemEntity entity,
  ) async {}
}

class FakeProbe implements DirectoryProbe {
  final Map<String, bool> existsMap = {};
  int probeReadCalls = 0;
  final List<String> probedPaths = [];

  @override
  Future<bool> exists(String path) async => existsMap[path] ?? false;

  @override
  Future<void> probeRead(String path) async {
    probeReadCalls++;
    probedPaths.add(path);
  }
}

class MemoryPrefs implements SharedPreferences {
  final Map<String, Object> data = {};

  MemoryPrefs([Map<String, Object>? initial]) {
    if (initial != null) data.addAll(initial);
  }

  @override
  String? getString(String key) => data[key] as String?;

  @override
  int? getInt(String key) => data[key] as int?;

  @override
  bool? getBool(String key) => data[key] as bool?;

  @override
  double? getDouble(String key) => data[key] as double?;

  @override
  List<String>? getStringList(String key) => data[key] as List<String>?;

  @override
  Set<String> getKeys() => data.keys.toSet();

  @override
  bool containsKey(String key) => data.containsKey(key);

  @override
  Object? get(String key) => data[key];

  @override
  Future<bool> setString(String key, String value) async {
    data[key] = value;
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    data[key] = value;
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    data[key] = value;
    return true;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    data[key] = value;
    return true;
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }

  @override
  Future<bool> commit() async => true;

  @override
  Future<void> reload() async {}
}

Widget createSidebarApp({
  required ProviderContainer container,
  Brightness brightness = Brightness.light,
  double width = 220,
  Future<String?> Function()? directoryPicker,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: brightness,
        ),
      ),
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: WorkspacesSidebarBlock(directoryPicker: directoryPicker),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeProbe probe;
  late MemoryPrefs prefs;
  late MockBookmarks bookmarks;

  setUp(() {
    probe = FakeProbe();
    prefs = MemoryPrefs();
    bookmarks = MockBookmarks();
  });

  ProviderContainer makeContainer({Map<String, Object>? initialPrefs}) {
    if (initialPrefs != null) {
      prefs.data.addAll(initialPrefs);
    }
    final notifier = WorkspacesNotifier(
      bookmarksAdapter: bookmarks,
      directoryProbe: probe,
      prefsLoader: () async => prefs,
      isMacOS: true,
    );
    final container = ProviderContainer(
      overrides: [workspacesProvider.overrideWith(() => notifier)],
    );
    container.read(workspacesProvider);
    return container;
  }

  testWidgets('late folder picker result is ignored after sidebar disposal', (
    tester,
  ) async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(workspacesProvider.notifier).initialization;
    final chosen = Completer<String?>();
    await tester.pumpWidget(
      createSidebarApp(
        container: container,
        directoryPicker: () => chosen.future,
      ),
    );
    await tester.tap(find.text('Добавить папку'));
    await tester.pumpWidget(const SizedBox());
    chosen.complete('/A');
    await tester.pumpAndSettle();
    expect(container.read(workspacesProvider).entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retry button reloads failed settings without erasing stored folders',
    (tester) async {
      var failing = true;
      prefs = MemoryPrefs({
        keyWorkspaceEntries: jsonEncode([
          {'path': '/A'},
        ]),
      });
      final notifier = WorkspacesNotifier(
        prefsLoader: () async {
          if (failing) throw StateError('read failed');
          return prefs;
        },
        directoryProbe: probe,
        isMacOS: false,
      );
      final container = ProviderContainer(
        overrides: [workspacesProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      container.read(workspacesProvider);
      await notifier.initialization;
      await tester.pumpWidget(createSidebarApp(container: container));
      expect(find.text('Повторить'), findsOneWidget);
      failing = false;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
      expect(container.read(workspacesProvider).lastError, isNull);
    },
  );

  group('WorkspacesSidebarBlock widget tests', () {
    testWidgets('Недоступная папка видна со значком и tooltip', (tester) async {
      probe.existsMap['/Volumes/USB/Available'] = true;
      probe.existsMap['/Volumes/OfflineDrive/Missing'] = false;

      final container = makeContainer(
        initialPrefs: {
          keyWorkspaceEntries: jsonEncode([
            {
              'path': '/Volumes/USB/Available',
              'bookmark': 'bm_/Volumes/USB/Available',
            },
            {
              'path': '/Volumes/OfflineDrive/Missing',
              'bookmark': 'bm_/Volumes/OfflineDrive/Missing',
            },
          ]),
          keyWorkspaceCurrentIndex: 0,
        },
      );

      await container.read(workspacesProvider.notifier).initialization;
      await container.read(workspacesProvider.notifier).availabilityCheckFuture;

      await tester.pumpWidget(createSidebarApp(container: container));
      await tester.pumpAndSettle();

      // Обе папки видны по имени
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Missing'), findsOneWidget);

      // Недоступная папка имеет значок предупреждения
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      // Tooltip с понятным текстом присутствует
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byIcon(Icons.warning_amber_rounded),
          matching: find.byType(Tooltip),
        ),
      );
      expect(
        tooltip.message,
        contains(
          'Папка недоступна. Подключите диск или выберите эту папку снова',
        ),
      );
    });

    testWidgets(
      'Повтор проверки доступен: кнопка «Обновить» проверяет выбранную папку',
      (tester) async {
        probe.existsMap['/Volumes/OfflineDrive/Missing'] = false;

        final container = makeContainer(
          initialPrefs: {
            keyWorkspaceEntries: jsonEncode([
              {
                'path': '/Volumes/OfflineDrive/Missing',
                'bookmark': 'bm_/Volumes/OfflineDrive/Missing',
              },
            ]),
            keyWorkspaceCurrentIndex: 0,
          },
        );

        await container.read(workspacesProvider.notifier).initialization;
        await container
            .read(workspacesProvider.notifier)
            .availabilityCheckFuture;

        await tester.pumpWidget(createSidebarApp(container: container));
        await tester.pumpAndSettle();

        // Нажимаем «Обновить»
        await tester.tap(find.widgetWithText(OutlinedButton, 'Обновить'));
        await tester.pumpAndSettle();

        // Папка недоступна -> отображается SnackBar с пояснением
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.textContaining(
            'Папка недоступна. Подключите диск или выберите эту папку снова',
          ),
          findsOneWidget,
        );

        // Диск подключили!
        probe.existsMap['/Volumes/OfflineDrive/Missing'] = true;

        // Снова нажимаем «Обновить»
        await tester.tap(find.widgetWithText(OutlinedButton, 'Обновить'));
        await tester.pumpAndSettle();

        // Теперь папка доступна, значок предупреждения исчез
        expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
        expect(container.read(refreshWorkspaceProvider), 1);
      },
    );

    testWidgets('Повторное подключение не создаёт дубль', (tester) async {
      probe.existsMap['/Volumes/Drive/ExistingFolder'] = true;

      final container = makeContainer(
        initialPrefs: {
          keyWorkspaceEntries: jsonEncode([
            {
              'path': '/Volumes/Drive/ExistingFolder',
              'bookmark': 'bm_/Volumes/Drive/ExistingFolder',
            },
          ]),
          keyWorkspaceCurrentIndex: 0,
        },
      );

      await container.read(workspacesProvider.notifier).initialization;
      await container.read(workspacesProvider.notifier).availabilityCheckFuture;

      await tester.pumpWidget(
        createSidebarApp(
          container: container,
          directoryPicker:
              () async =>
                  '/Volumes/Drive/ExistingFolder/', // с замыкающим слешем
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ExistingFolder'), findsOneWidget);

      // Нажимаем «Добавить папку»
      await tester.tap(find.widgetWithText(FilledButton, 'Добавить папку'));
      await tester.pumpAndSettle();

      // Запись по-прежнему ровно одна
      expect(container.read(workspacesProvider).entries.length, 1);
      expect(find.text('ExistingFolder'), findsOneWidget);
    });

    testWidgets('Удаление из списка не вызывает операций над файлами', (
      tester,
    ) async {
      probe.existsMap['/Volumes/Drive/SafeFolder'] = true;

      final container = makeContainer(
        initialPrefs: {
          keyWorkspaceEntries: jsonEncode([
            {
              'path': '/Volumes/Drive/SafeFolder',
              'bookmark': 'bm_/Volumes/Drive/SafeFolder',
            },
          ]),
          keyWorkspaceCurrentIndex: 0,
        },
      );

      await container.read(workspacesProvider.notifier).initialization;
      await container.read(workspacesProvider.notifier).availabilityCheckFuture;

      await tester.pumpWidget(createSidebarApp(container: container));
      await tester.pumpAndSettle();

      expect(find.text('SafeFolder'), findsOneWidget);

      // Нажимаем крестик удаления
      await tester.tap(find.byTooltip('Удалить из рабочих областей'));
      await tester.pumpAndSettle();

      // Запись удалена из списка
      expect(container.read(workspacesProvider).entries, isEmpty);
      expect(find.text('Нет папок'), findsOneWidget);
      // Никаких файловых операций удаления не было
    });

    testWidgets('Путь "/" показывает понятное имя "Корень (/)"', (
      tester,
    ) async {
      probe.existsMap['/'] = true;

      final container = makeContainer(
        initialPrefs: {
          keyWorkspaceEntries: jsonEncode([
            {'path': '/'},
          ]),
          keyWorkspaceCurrentIndex: 0,
        },
      );

      await container.read(workspacesProvider.notifier).initialization;
      await container.read(workspacesProvider.notifier).availabilityCheckFuture;

      await tester.pumpWidget(createSidebarApp(container: container));
      await tester.pumpAndSettle();

      expect(find.text('Корень (/)'), findsOneWidget);
    });

    testWidgets('Узкая панель и длинное имя не вызывают RenderFlex overflow', (
      tester,
    ) async {
      const longPath =
          '/Volumes/SuperLongDriveName/SuperLongSubfolderName/AnotherVeryLongDirectoryNameToTestNarrowConstraints';
      probe.existsMap[longPath] = true;

      final container = makeContainer(
        initialPrefs: {
          keyWorkspaceEntries: jsonEncode([
            {'path': longPath},
          ]),
        },
      );

      await container.read(workspacesProvider.notifier).initialization;
      await container.read(workspacesProvider.notifier).availabilityCheckFuture;

      // Устанавливаем ширину всего 150px
      await tester.pumpWidget(
        createSidebarApp(container: container, width: 150),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Корректно отображается в светлой и тёмной темах', (
      tester,
    ) async {
      probe.existsMap['/Volumes/Drive/ThemeFolder'] = true;

      final containerLight = makeContainer(
        initialPrefs: {
          keyWorkspaceEntries: jsonEncode([
            {'path': '/Volumes/Drive/ThemeFolder'},
          ]),
        },
      );
      await containerLight.read(workspacesProvider.notifier).initialization;
      await containerLight
          .read(workspacesProvider.notifier)
          .availabilityCheckFuture;

      await tester.pumpWidget(
        createSidebarApp(
          container: containerLight,
          brightness: Brightness.light,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final containerDark = makeContainer(
        initialPrefs: {
          keyWorkspaceEntries: jsonEncode([
            {'path': '/Volumes/Drive/ThemeFolder'},
          ]),
        },
      );
      await containerDark.read(workspacesProvider.notifier).initialization;
      await containerDark
          .read(workspacesProvider.notifier)
          .availabilityCheckFuture;

      await tester.pumpWidget(
        createSidebarApp(container: containerDark, brightness: Brightness.dark),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Клавиатурный фокус и семантика доступны', (tester) async {
      probe.existsMap['/Volumes/Drive/Accessible'] = true;

      final container = makeContainer(
        initialPrefs: {
          keyWorkspaceEntries: jsonEncode([
            {'path': '/Volumes/Drive/Accessible'},
          ]),
        },
      );
      await container.read(workspacesProvider.notifier).initialization;
      await container.read(workspacesProvider.notifier).availabilityCheckFuture;

      await tester.pumpWidget(createSidebarApp(container: container));
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(InkWell).first);
      expect(semantics.label, contains('Accessible'));
    });
  });
}
