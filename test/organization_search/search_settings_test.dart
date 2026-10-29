import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_flow/features/organization_search/application/organization_search_providers.dart';
import 'package:stock_flow/models/workflow_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OrganizationSearchSettings - Сериализация и десериализация', () {
    test('сохраняет и восстанавливает все поля без потерь', () {
      final original = OrganizationSearchSettings(
        scope: const SearchScope.folder(
          folderPath: '/Volumes/Data/Photos',
          includeSubfolders: true,
        ),
        filters: const SearchFilterCriteria(
          query: 'sunset mountain',
          workflowStatuses: {
            WorkflowStatus.newFile,
            WorkflowStatus.metadataReady,
          },
          hasKeywords: false,
          hasTitle: true,
          isEditorial: true,
          isAiGenerated: false,
          mediaCategory: MediaCategoryFilter.image,
          isAccessible: true,
        ),
        scrollOffset: 342.5,
      );

      final jsonStr = original.toJson();
      expect(jsonStr.length, lessThan(OrganizationSearchSettings.maxSerializedBytes));

      final restored = OrganizationSearchSettings.fromJson(jsonStr);
      expect(restored.scope, equals(original.scope));
      expect(restored.filters, equals(original.filters));
      expect(restored.scrollOffset, equals(342.5));
    });

    test('десериализация пустой строки или битых данных возвращает настройки по умолчанию',
        () {
      expect(
        OrganizationSearchSettings.fromJson(''),
        equals(const OrganizationSearchSettings()),
      );
      expect(
        OrganizationSearchSettings.fromJson('{invalid json'),
        equals(const OrganizationSearchSettings()),
      );
    });

    test('превышение максимального размера вызывает StateError при сериализации', () {
      // Имитируем гигантский запрос
      final oversizedQuery = 'A' * (OrganizationSearchSettings.maxSerializedBytes + 100);
      final oversized = OrganizationSearchSettings(
        filters: SearchFilterCriteria(query: oversizedQuery),
      );

      expect(
        () => oversized.toJson(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('SearchSettingsStorage - Персистентность', () {
    test('SharedPreferencesSearchSettingsStorage сохраняет и восстанавливает настройки',
        () async {
      SharedPreferences.setMockInitialValues({});

      final storage = SharedPreferencesSearchSettingsStorage();

      expect(await storage.loadSettings(), isNull);

      final settings = OrganizationSearchSettings(
        scope: const SearchScope.project(
          projectId: 'proj-777',
          includeSubfolders: true,
        ),
        filters: const SearchFilterCriteria(query: 'nature'),
        scrollOffset: 120.0,
      );

      await storage.saveSettings(settings);

      final loaded = await storage.loadSettings();
      expect(loaded, isNotNull);
      expect(loaded!.scope.projectId, equals('proj-777'));
      expect(loaded.scope.includeSubfolders, isTrue);
      expect(loaded.filters.query, equals('nature'));
      expect(loaded.scrollOffset, equals(120.0));

      await storage.clearSettings();
      expect(await storage.loadSettings(), isNull);
    });

    test('InMemorySearchSettingsStorage работает в памяти', () async {
      final storage = InMemorySearchSettingsStorage();
      expect(await storage.loadSettings(), isNull);

      const settings = OrganizationSearchSettings(
        scope: SearchScope.selection(),
        scrollOffset: 50.0,
      );

      await storage.saveSettings(settings);
      expect(await storage.loadSettings(), equals(settings));

      await storage.clearSettings();
      expect(await storage.loadSettings(), isNull);
    });
  });
}
