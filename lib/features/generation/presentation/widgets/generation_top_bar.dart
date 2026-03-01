import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/state/files_provider.dart';
import '../../../../core/state/workspaces_provider.dart';

/// Top bar showing current workspace folder name and file counts.
class GenerationTopBar extends ConsumerWidget {
  final int localCount;
  final bool isLoading;
  final int batchDone;
  final int batchTotal;

  const GenerationTopBar({
    super.key,
    required this.localCount,
    required this.isLoading,
    required this.batchDone,
    required this.batchTotal,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final workspacePath = ref.watch(workspacesProvider).currentPath;
    final folderName = workspacePath == null || workspacePath.isEmpty
        ? ''
        : workspacePath.split(Platform.pathSeparator).last;

    return ref
        .watch(filesProvider)
        .when(
          data: (dbFiles) {
            final sep = Platform.pathSeparator;
            final dbCount = workspacePath == null || workspacePath.isEmpty
                ? 0
                : dbFiles
                      .where(
                        (f) =>
                            f.path == workspacePath ||
                            f.path.startsWith(workspacePath + sep),
                      )
                      .length;
            final total = dbCount + localCount;

            return Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
                border: Border(
                  bottom: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    folderName.isEmpty ? '—' : folderName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Text(
                    'Файлов: $total',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const Spacer(),
                  if (isLoading && batchTotal > 0)
                    Text(
                      'Обработка: $batchDone / $batchTotal',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                ],
              ),
            );
          },
          loading: () => Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 20,
                  color: colorScheme.outline,
                ),
                const SizedBox(width: 10),
                Text(
                  folderName.isEmpty ? '—' : folderName,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
        );
  }
}
