import 'package:flutter/material.dart';

import '../domain/organization_models.dart';
import 'widgets/collections_section_view.dart';
import 'widgets/projects_section_view.dart';
import 'widgets/selection_section_view.dart';

/// Единый составной виджет организации (проекты, коллекции, «Отбор»)
/// для размещения в сайдбаре приложения рядом с блоком рабочих областей.
///
/// Полностью готов к подключению задачей 06.
class OrganizationSidebarView extends StatelessWidget {
  final String? selectedProjectId;
  final ValueChanged<Project?>? onProjectSelected;
  final ValueChanged<String>? onFolderSelected;

  final String? selectedCollectionId;
  final ValueChanged<Collection?>? onCollectionSelected;

  final bool isSelectionSource;
  final VoidCallback? onOpenSelection;

  final List<String> selectedFileIds;
  final Future<String?> Function()? directoryPicker;

  const OrganizationSidebarView({
    super.key,
    this.selectedProjectId,
    this.onProjectSelected,
    this.onFolderSelected,
    this.selectedCollectionId,
    this.onCollectionSelected,
    this.isSelectionSource = false,
    this.onOpenSelection,
    this.selectedFileIds = const [],
    this.directoryPicker,
  });

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProjectsSectionView(
            selectedProjectId: selectedProjectId,
            onProjectSelected: onProjectSelected,
            onFolderSelected: onFolderSelected,
            directoryPicker: directoryPicker,
          ),
          CollectionsSectionView(
            selectedCollectionId: selectedCollectionId,
            onCollectionSelected: onCollectionSelected,
            selectedFileIds: selectedFileIds,
          ),
          SelectionSectionView(
            selectedFileIds: selectedFileIds,
            isSelectedSource: isSelectionSource,
            onOpenSelection: onOpenSelection,
          ),
        ],
      ),
    );
  }
}
