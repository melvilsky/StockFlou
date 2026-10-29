import 'dart:ui' as ui;
import 'dart:io';
import 'package:stock_flow/models/app_file.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_flow/core/state/files_provider.dart';
import 'package:stock_flow/core/state/workspaces_provider.dart';
import 'package:stock_flow/features/organization/application/organization_providers.dart';
import 'package:stock_flow/features/organization_search/application/organization_search_providers.dart';
import 'package:stock_flow/main.dart';
import 'package:stock_flow/core/widgets/safe_semantics_binding.dart';

import 'folders_projects_integration/integration_scenario_test.dart'
    show TestFilesNotifier, TestWorkspacesNotifier;
import 'organization_presentation/test_helpers.dart';

class _CheckedSemanticsBinding extends AutomatedTestWidgetsFlutterBinding
    with SafeSemanticsUpdates {
  final nodes = <int, Map<Symbol, dynamic>>{};
  final orphans = <String>[];

  @override
  ui.SemanticsUpdateBuilder createPlatformSemanticsUpdateBuilder() =>
      _CheckedUpdate(this);
}

class _CheckedUpdate implements ui.SemanticsUpdateBuilder {
  final _CheckedSemanticsBinding binding;
  final delegate = ui.SemanticsUpdateBuilder();
  final updated = <int>{};

  _CheckedUpdate(this.binding);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      final args = invocation.namedArguments;
      final id = args[#id] as int;
      binding.nodes[id] = Map.of(args);
      updated.add(id);
      return Function.apply(
        delegate.updateNode,
        invocation.positionalArguments,
        args,
      );
    }
    if (invocation.memberName == #updateCustomAction) {
      return Function.apply(
        delegate.updateCustomAction,
        invocation.positionalArguments,
        invocation.namedArguments,
      );
    }
    if (invocation.memberName == #build) {
      final reachable = <int>{};
      void visit(int id) {
        if (!reachable.add(id)) return;
        for (final child
            in binding.nodes[id]?[#childrenInTraversalOrder] ?? <int>[]) {
          visit(child as int);
        }
      }

      visit(0);
      for (final id in updated.difference(reachable)) {
        final node = binding.nodes[id]!;
        binding.orphans.add(
          '$id label=${node[#label]} tooltip=${node[#tooltip]} traversalParent=${node[#traversalParentId]}',
        );
      }
      binding.nodes.removeWhere((id, _) => !reachable.contains(id));
      return delegate.build();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  final binding = _CheckedSemanticsBinding();

  testWidgets(
    'app sends only rooted accessibility nodes to the native bridge',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = Directory.systemTemp.createTempSync('sf_ax_snapshot_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final files = [
        for (var i = 0; i < 3; i++)
          AppFile(
            id: '$i',
            path:
                File(
                  'assets/app_icon.png',
                ).copySync('${temp.path}/TEST-$i.png').path,
            filename: 'TEST-$i.png',
            createdAt: i,
          ),
      ];
      final notifier = TestFilesNotifier(files);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              filesProvider.overrideWith(() => notifier),
              catalogFilesLoaderProvider.overrideWithValue(
                () async => List.of(notifier.files),
              ),
              workspacesProvider.overrideWith(() => TestWorkspacesNotifier([])),
              organizationRepositoryProvider.overrideWithValue(
                FakeOrganizationRepository(),
              ),
            ],
            child: MaterialApp(
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(0.4)),
                    child: child!,
                  ),
              home: const MainShell(),
            ),
          ),
        );
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        await tester.tap(find.widgetWithText(OutlinedButton, 'Выделить всё'));
        await tester.pump();
        // Editorial в batch-режиме — tri-state, применяется кнопкой «Применить».
        await tester.tap(find.text('Вкл').first);
        await tester.pump();
        await tester.tap(find.textContaining('Применить к'));
        for (var frame = 0; frame < 40; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
        expect(notifier.files.every((file) => file.isEditorial), isTrue);
        expect(binding.nodes, contains(0));
        expect(
          binding.nodes.values.any(
            (node) => '${node[#label]}'.contains('StockFlow'),
          ),
          isTrue,
        );
        expect(binding.orphans, isEmpty);
      } finally {
        semantics.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
