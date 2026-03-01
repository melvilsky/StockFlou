import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/single_click_area.dart';

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

/// File grid card with thumbnail and selection state.
class GenerationGridCard extends StatelessWidget {
  final String imagePath;
  final String filename;
  final bool isTagged;
  final bool isSelected;
  final VoidCallback onTap;

  const GenerationGridCard({
    super.key,
    required this.imagePath,
    required this.filename,
    required this.isTagged,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleClickArea(
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
                  child: Builder(
                    builder: (context) {
                      final isVideo = AppConstants.isVideo(imagePath);

                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? Border.all(color: colorScheme.primary, width: 2)
                              : Border.all(color: colorScheme.outline),
                          color: isVideo
                              ? colorScheme.surfaceContainerHighest
                              : null,
                          image: isVideo
                              ? null
                              : DecorationImage(
                                  image: FileImage(File(imagePath)),
                                  fit: BoxFit.cover,
                                ),
                        ),
                        child: Stack(
                          children: [
                            if (isVideo)
                              Center(
                                child: Icon(
                                  Icons.videocam,
                                  size: 48,
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                            if (isSelected)
                              Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Icon(
                                    Icons.check_circle,
                                    color: colorScheme.primary,
                                    size: 20,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
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
    );
  }
}

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
