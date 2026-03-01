import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/state/files_provider.dart';
import '../../../../core/state/workspaces_provider.dart';
import '../../../../core/widgets/single_click_area.dart';

/// Action toolbar: select all, AI Tag, Save All, Save One.
class GenerationToolsBar extends ConsumerWidget {
  final Set<String> selectedPaths;
  final List<File> localFiles;
  final bool metadataDirty;
  final String? focusedPath;
  final VoidCallback onSelectAll;
  final VoidCallback onGenerateAI;
  final VoidCallback onGenerateBatchAI;
  final VoidCallback onSaveAll;
  final VoidCallback onSaveChanges;

  const GenerationToolsBar({
    super.key,
    required this.selectedPaths,
    required this.localFiles,
    required this.metadataDirty,
    required this.focusedPath,
    required this.onSelectAll,
    required this.onGenerateAI,
    required this.onGenerateBatchAI,
    required this.onSaveAll,
    required this.onSaveChanges,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final workspaces = ref.watch(workspacesProvider);
    final dbFiles = ref.watch(filesProvider).value ?? [];
    final sep = Platform.pathSeparator;

    // Count files with metadata across all workspaces (excluding video)
    int saveAllCount = 0;
    for (final entry in workspaces.entries) {
      final wp = entry.path;
      final prefix = wp.endsWith(sep) ? wp : wp + sep;
      for (final f in dbFiles) {
        if (f.path != wp && !f.path.startsWith(prefix)) continue;
        if (AppConstants.isVideo(f.path)) continue;
        final hasMeta =
            (f.metadataTitle != null && f.metadataTitle!.trim().isNotEmpty) ||
            (f.metadataKeywords != null &&
                f.metadataKeywords!.trim().isNotEmpty);
        if (hasMeta) saveAllCount++;
      }
    }

    final hasSelection = focusedPath != null;
    final isFocusedVideo =
        focusedPath != null && AppConstants.isVideo(focusedPath!);
    final saveCount = (metadataDirty && hasSelection && !isFocusedVideo)
        ? 1
        : 0;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          // Select / Deselect all
          Tooltip(
            message: selectedPaths.isEmpty ? 'Выделить всё' : 'Снять выделение',
            child: SingleClickArea(
              onTap: onSelectAll,
              child: IconButton(
                onPressed: () {},
                icon: Icon(
                  selectedPaths.isEmpty ? Icons.select_all : Icons.deselect,
                  size: 22,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // AI Tag
          Tooltip(
            message: 'AI Tag — генерация тегов для выбранных',
            child: SingleClickArea(
              onTap: selectedPaths.isEmpty
                  ? null
                  : () {
                      if (selectedPaths.length > 1) {
                        onGenerateBatchAI();
                      } else {
                        onGenerateAI();
                      }
                    },
              child: IconButton(
                onPressed: selectedPaths.isEmpty ? null : () {},
                icon: Icon(
                  Icons.auto_awesome,
                  size: 22,
                  color: selectedPaths.isEmpty
                      ? colorScheme.onSurface.withValues(alpha: 0.4)
                      : colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Save All
          Tooltip(
            message:
                'Сохранить метаданные в файлы (кроме видео) во всех рабочих областях',
            child: SingleClickArea(
              onTap: saveAllCount > 0 ? onSaveAll : null,
              child: FilledButton.icon(
                onPressed: saveAllCount > 0 ? () {} : null,
                icon: const Icon(Icons.save, size: 18),
                label: Text('Сохранить все ($saveAllCount)'),
                style: FilledButton.styleFrom(
                  backgroundColor: saveAllCount > 0
                      ? colorScheme.primary
                      : null,
                  foregroundColor: saveAllCount > 0
                      ? colorScheme.onPrimary
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Save one
          Tooltip(
            message: isFocusedVideo
                ? 'Для видео файлов запись метаданных в файл недоступна'
                : 'Сохранить метаданные выбранного файла в БД и в файл',
            child: FilledButton.icon(
              onPressed: saveCount > 0 ? onSaveChanges : null,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text('Сохранить ($saveCount)'),
              style: FilledButton.styleFrom(
                backgroundColor: saveCount > 0
                    ? colorScheme.primaryContainer
                    : null,
                foregroundColor: saveCount > 0
                    ? colorScheme.onPrimaryContainer
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
