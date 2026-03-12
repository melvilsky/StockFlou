import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/single_click_area.dart';
import '../../../../models/app_file.dart';

/// Small text label used above form fields.
class GenerationFormLabel extends StatelessWidget {
  final String text;
  const GenerationFormLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      ),
    );
  }
}

// ─── Tag UI helpers ──────────────────────────────────────────────────────────

/// Returns (label, color, icon) for a known tag key.
(String, Color, IconData) _tagMeta(String tag) {
  switch (tag) {
    case AppTags.aiGenerated:
      return ('AI', const Color(0xFF7C3AED), Icons.auto_awesome);
    case AppTags.editorial:
      return ('Editorial', const Color(0xFFD97706), Icons.newspaper);
    default:
      return (tag, const Color(0xFF0891B2), Icons.label_outline);
  }
}

/// Tiny sticker chip overlaid on the grid card image.
/// Dark semi-transparent background + white text makes it readable on any photo.
class _TagChip extends StatelessWidget {
  final String tag;
  const _TagChip(this.tag);

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _tagMeta(tag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        // Dark backdrop so it reads on any photo background
        color: const Color(0xCC000000), // 80% black
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact removable chip for the inspector / multi-select panel.
class TagBadge extends StatelessWidget {
  final String tag;
  final VoidCallback? onRemove;

  const TagBadge(this.tag, {super.key, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _tagMeta(tag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: Icon(
                Icons.close,
                size: 12,
                color: color.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── GenerationGridCard ──────────────────────────────────────────────────────

/// File grid card with thumbnail, selection state, and tag chips.
class GenerationGridCard extends StatelessWidget {
  final String imagePath;
  final String filename;
  final bool isTagged;
  final bool isSelected;
  final List<String> tags;
  final VoidCallback onTap;

  const GenerationGridCard({
    super.key,
    required this.imagePath,
    required this.filename,
    required this.isTagged,
    required this.isSelected,
    required this.onTap,
    this.tags = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isVideo = AppConstants.isVideo(imagePath);

    return RepaintBoundary(
      child: SingleClickArea(
        onTap: onTap,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primary.withValues(alpha: 0.05)
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: 0.3)
                      : Colors.transparent,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        // Rounded image / video inside ClipRRect
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Image / video thumbnail
                                if (isVideo)
                                  Container(
                                    color: colorScheme.surfaceContainerHighest,
                                    child: Center(
                                      child: Icon(
                                        Icons.videocam,
                                        size: 48,
                                        color: colorScheme.primary.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  Image.file(
                                    File(imagePath),
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                    errorBuilder: (_, __, ___) => Container(
                                      color:
                                          colorScheme.surfaceContainerHighest,
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                  ),
                                // Selection border overlay
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? colorScheme.primary
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Checkmark when selected — outside clip, top-right
                        if (isSelected)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Icon(
                              Icons.check_circle,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                          ),
                        // Tag stickers — outside clip, top-left
                        if (tags.isNotEmpty)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: tags
                                  .take(3)
                                  .map(
                                    (t) => Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: _TagChip(t),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    filename,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Builder(
                        builder: (context) {
                          final isDark =
                              Theme.of(context).brightness == Brightness.dark;
                          final dotColor = isTagged
                              ? (isDark
                                    ? AppTheme.successColorDark
                                    : AppTheme.successColor)
                              : (isDark
                                    ? AppTheme.warningColorDark
                                    : AppTheme.warningColor);
                          return Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: dotColor,
                              shape: BoxShape.circle,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isTagged ? 'Tagged' : 'Untagged',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── GenerationStockStatusCard ───────────────────────────────────────────────

/// Stock platform status card (Adobe, Shutterstock, etc.).
class GenerationStockStatusCard extends StatelessWidget {
  final String code;
  final String label;
  final Color color;
  final bool isUploaded;

  const GenerationStockStatusCard({
    super.key,
    required this.code,
    required this.label,
    required this.color,
    required this.isUploaded,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.outlineVariant.withValues(alpha: 0.1)
            : Colors.grey.shade50,
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  code,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Icon(
            isUploaded ? Icons.check_circle : Icons.check_circle_outline,
            color: isUploaded
                ? (isDark ? AppTheme.successColorDark : AppTheme.successColor)
                : colorScheme.onSurface.withValues(alpha: 0.3),
            size: 18,
          ),
        ],
      ),
    );
  }
}
