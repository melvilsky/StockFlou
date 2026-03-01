import 'package:flutter/material.dart';

/// Search + filter chip bar above the file grid.
///
/// [searchController] is owned by the parent.
/// [searchQuery] is the current text in the search field.
/// [filterType] is one of 'all', 'images', 'videos'.
/// [onSearchChanged] is called when the search text changes.
/// [onFilterChanged] is called when a filter chip is tapped.
class GenerationFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final String searchQuery;
  final String filterType;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onFilterChanged;

  const GenerationFilterBar({
    super.key,
    required this.searchController,
    required this.searchQuery,
    required this.filterType,
    required this.onSearchChanged,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // Search field
          SizedBox(
            width: 220,
            height: 32,
            child: TextField(
              controller: searchController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Поиск по имени...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                suffixIcon: searchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          searchController.clear();
                          onSearchChanged('');
                        },
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.primary, width: 1),
                ),
              ),
              onChanged: onSearchChanged,
            ),
          ),
          const SizedBox(width: 12),
          // Filter chips
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _filterChip(
                label: 'Все',
                icon: Icons.grid_view_rounded,
                isActive: filterType == 'all',
                onTap: () => onFilterChanged('all'),
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 6),
              _filterChip(
                label: 'Фото',
                icon: Icons.image_outlined,
                isActive: filterType == 'images',
                onTap: () => onFilterChanged('images'),
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 6),
              _filterChip(
                label: 'Видео',
                icon: Icons.videocam_outlined,
                isActive: filterType == 'videos',
                onTap: () => onFilterChanged('videos'),
                colorScheme: colorScheme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isActive
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: isActive
              ? null
              : Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  width: 1,
                ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive
                  ? colorScheme.onPrimary
                  : colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
