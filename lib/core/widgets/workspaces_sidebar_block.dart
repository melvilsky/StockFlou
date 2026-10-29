import 'app_tooltip.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../state/navigation_provider.dart';
import '../state/workspaces_provider.dart';
import 'single_click_area.dart';

/// Отображаемое имя папки рабочей области.
String workspaceDisplayName(String path) {
  if (path == '/' || RegExp(r'^/+$').hasMatch(path)) {
    return 'Корень (/)';
  }
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) {
    return path;
  }
  return segments.last;
}

class WorkspacesSidebarBlock extends ConsumerWidget {
  final Future<String?> Function()? directoryPicker;

  const WorkspacesSidebarBlock({super.key, this.directoryPicker});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaces = ref.watch(workspacesProvider);
    final entries = workspaces.entries;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final blockBg =
        isDark
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : colorScheme.surfaceContainerLow;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: blockBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Рабочие области',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
              if (workspaces.isCheckingAvailability)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (workspaces.lastError != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                workspaces.lastError!,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: () => ref.read(workspacesProvider.notifier).retry(),
              child: const Text('Повторить'),
            ),
          ],
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child:
                entries.isEmpty
                    ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Нет папок',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    )
                    : ListView.builder(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      itemBuilder: (context, idx) {
                        final entry = entries[idx];
                        final path = entry.path;
                        final name = workspaceDisplayName(path);
                        final isSelected = idx == workspaces.currentIndex;
                        final availability = workspaces.availabilityFor(path);
                        final isUnavailable = availability.isUnavailable;
                        final isChecking = availability.isChecking;

                        final statusDescription =
                            isUnavailable
                                ? 'Папка недоступна. Подключите диск или выберите эту папку снова'
                                : (isChecking
                                    ? 'Проверяется доступность'
                                    : 'Доступна');

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Material(
                            color: Colors.transparent,
                            child: SingleClickArea(
                              onTap: () {
                                ref
                                    .read(workspacesProvider.notifier)
                                    .setCurrent(idx);
                                ref
                                    .read(navigationProvider.notifier)
                                    .setTab(NavigationTab.workspace);
                              },
                              child: Semantics(
                                label: '$name, $statusDescription',
                                selected: isSelected,
                                button: true,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    ref
                                        .read(workspacesProvider.notifier)
                                        .setCurrent(idx);
                                    ref
                                        .read(navigationProvider.notifier)
                                        .setTab(NavigationTab.workspace);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          isSelected
                                              ? colorScheme.primary.withValues(
                                                alpha: 0.15,
                                              )
                                              : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      border:
                                          isUnavailable
                                              ? Border.all(
                                                color: colorScheme.error
                                                    .withValues(alpha: 0.4),
                                                width: 1,
                                              )
                                              : null,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isUnavailable
                                              ? Icons.folder_off_outlined
                                              : Icons.folder_outlined,
                                          size: 18,
                                          color:
                                              isUnavailable
                                                  ? colorScheme.error
                                                  : (isSelected
                                                      ? colorScheme.primary
                                                      : colorScheme.onSurface
                                                          .withValues(
                                                            alpha: 0.6,
                                                          )),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: AppTooltip(
                                            message:
                                                isUnavailable
                                                    ? '$path\n${availability.message ?? "Папка недоступна. Подключите диск или выберите эту папку снова"}'
                                                    : path,
                                            child: Text(
                                              name,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight:
                                                    isSelected
                                                        ? FontWeight.w600
                                                        : FontWeight.normal,
                                                color:
                                                    isUnavailable
                                                        ? colorScheme.error
                                                        : (isSelected
                                                            ? colorScheme
                                                                .primary
                                                            : colorScheme
                                                                .onSurface),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        if (isChecking)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 6,
                                            ),
                                            child: SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(colorScheme.primary),
                                              ),
                                            ),
                                          )
                                        else if (isUnavailable)
                                          AppTooltip(
                                            message:
                                                availability.message ??
                                                'Папка недоступна. Подключите диск или выберите эту папку снова',
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                right: 4,
                                              ),
                                              child: Icon(
                                                Icons.warning_amber_rounded,
                                                size: 16,
                                                color: colorScheme.error,
                                              ),
                                            ),
                                          ),
                                        Semantics(
                                          container: true,
                                          child: IconButton(
                                            icon: Icon(
                                              Icons.close,
                                              size: 16,
                                              color: colorScheme.onSurface
                                                  .withValues(alpha: 0.5),
                                            ),
                                            onPressed: () {
                                              ref
                                                  .read(
                                                    workspacesProvider.notifier,
                                                  )
                                                  .removeWorkspace(idx);
                                            },
                                            tooltip:
                                                'Удалить из рабочих областей',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 28,
                                              minHeight: 28,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: FilledButton.icon(
              onPressed: () async {
                final picker = directoryPicker ?? getDirectoryPath;
                final path = await picker();
                if (!context.mounted) return;
                if (path != null && path.isNotEmpty) {
                  final ok = await ref
                      .read(workspacesProvider.notifier)
                      .addWorkspace(path);
                  if (context.mounted) {
                    if (!ok && ref.read(workspacesProvider).lastError != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ref.read(workspacesProvider).lastError!,
                          ),
                        ),
                      );
                    }
                    ref
                        .read(navigationProvider.notifier)
                        .setTab(NavigationTab.workspace);
                  }
                }
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Добавить папку'),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: OutlinedButton.icon(
              onPressed:
                  workspaces.currentPath == null
                      ? null
                      : () async {
                        final current = workspaces.currentPath!;
                        await ref
                            .read(workspacesProvider.notifier)
                            .recheckAvailability(path: current);
                        if (!context.mounted) return;
                        final updated = ref
                            .read(workspacesProvider)
                            .availabilityFor(current);
                        if (context.mounted) {
                          if (updated.isAvailable) {
                            ref
                                .read(refreshWorkspaceProvider.notifier)
                                .trigger();
                            ref
                                .read(navigationProvider.notifier)
                                .setTab(NavigationTab.workspace);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  updated.message ??
                                      'Папка недоступна. Подключите диск или выберите эту папку снова',
                                ),
                              ),
                            );
                          }
                        }
                      },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Обновить'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colorScheme.outline),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
