import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/single_click_area.dart';
import '../../../../models/app_file.dart';
import '../../../../models/workflow_status.dart';
import 'media_file_meta.dart';

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

IconData _tagIcon(String tag) {
  switch (tag) {
    case AppTags.aiGenerated:
      return Icons.auto_awesome;
    case AppTags.editorial:
      return Icons.newspaper;
    default:
      return Icons.label_outline;
  }
}

String _tagTitle(String tag) {
  switch (tag) {
    case AppTags.aiGenerated:
      return 'AI-изображение';
    case AppTags.editorial:
      return 'Editorial';
    default:
      return tag;
  }
}

/// Small icon markers for AI / Editorial tags next to the filename.
class _TagMarkers extends StatelessWidget {
  final List<String> tags;

  const _TagMarkers(this.tags);

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final visible = tags.take(3).toList(growable: false);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          AppTooltip(
            message: _tagTitle(visible[i]),
            child: Icon(
              _tagIcon(visible[i]),
              size: 13,
              color: palette.textMuted,
            ),
          ),
        ],
      ],
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

// ─── Workflow status presentation ────────────────────────────────────────────

/// Русские подписи статусов из workspace-spec §4.
(String, IconData) _workflowStatusVisual(WorkflowStatus status) {
  switch (status) {
    case WorkflowStatus.newFile:
      return ('Новый', Icons.add_circle_outline);
    case WorkflowStatus.metadataReady:
      return ('Метаданные готовы', Icons.description_outlined);
    case WorkflowStatus.qcFailed:
      return ('Нужна правка QC', Icons.warning_amber_rounded);
    case WorkflowStatus.readyToUpload:
      return ('Готов к загрузке', Icons.check_circle_outline);
    case WorkflowStatus.uploaded:
      return ('Загружен', Icons.cloud_done_outlined);
    case WorkflowStatus.submitted:
      return ('Отправлен на проверку', Icons.verified_outlined);
  }
}

Color _workflowStatusColor(WorkflowStatus status, AppPalette palette) {
  switch (status) {
    case WorkflowStatus.readyToUpload:
    case WorkflowStatus.uploaded:
    case WorkflowStatus.submitted:
      return palette.success;
    case WorkflowStatus.qcFailed:
      return palette.warning;
    case WorkflowStatus.newFile:
    case WorkflowStatus.metadataReady:
      return palette.textMuted;
  }
}

// ─── Shared small widgets ────────────────────────────────────────────────────

/// Enter/Space activates the focused card or list row.
const Map<ShortcutActivator, Intent> _activateShortcuts = {
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
};

/// Async size/resolution text. One frame of "…" while the cached metadata
/// future settles; keeps the footer from jumping when data arrives.
class _MediaMetaText extends StatefulWidget {
  final String path;
  final bool isAccessible;
  final bool showResolution;

  const _MediaMetaText({
    required this.path,
    required this.isAccessible,
    required this.showResolution,
  });

  @override
  State<_MediaMetaText> createState() => _MediaMetaTextState();
}

class _MediaMetaTextState extends State<_MediaMetaText> {
  late Future<MediaFileMeta> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(_MediaMetaText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.isAccessible != widget.isAccessible) {
      _future = _load();
    }
  }

  Future<MediaFileMeta> _load() {
    if (!widget.isAccessible) return Future.value(const MediaFileMeta());
    return MediaMetaCache.load(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final style = TextStyle(
      fontSize: 11,
      height: 1.2,
      color: palette.textMuted,
    );

    return FutureBuilder<MediaFileMeta>(
      future: _future,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final meta = snapshot.data;
        final size = meta == null ? null : formatMediaBytes(meta.bytes);
        final resolution = formatMediaDimensions(meta);

        if (loading) {
          return Text(
            '…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }

        final parts = <String>[
          if (size != null) size,
          if (widget.showResolution && resolution != null) resolution,
        ];
        if (parts.isEmpty) parts.add('—');

        final text = Text(
          parts.join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
        final full = [size, resolution].whereType<String>().join(' · ');
        if (full.isEmpty) return text;
        return AppTooltip(message: full, child: text);
      },
    );
  }
}

/// Photo, video or failure placeholder. Never throws into the grid: a broken
/// thumbnail or an unavailable disk shows an explicit label instead.
class _MediaThumbnail extends StatelessWidget {
  final String path;
  final bool isAccessible;

  const _MediaThumbnail({required this.path, required this.isAccessible});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (!isAccessible) {
      return _ThumbPlaceholder(
        icon: Icons.cloud_off_outlined,
        label: 'Файл недоступен',
        color: palette.field,
      );
    }
    if (AppConstants.isVideo(path)) {
      return Container(
        color: palette.field,
        alignment: Alignment.center,
        child: Icon(
          Icons.play_circle_outline,
          size: 36,
          color: palette.textMuted,
        ),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder:
          (_, __, ___) => _ThumbPlaceholder(
            icon: Icons.broken_image_outlined,
            label: 'Ошибка превью',
            color: palette.field,
          ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ThumbPlaceholder({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final compact = height.isFinite && height < 56;
        return Container(
          color: color,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 18 : 26, color: palette.textMuted),
              if (!compact) ...[
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: palette.textMuted),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Checkbox that stays visible on the photo (unlike hover-only overlays).
/// Icon-based so it always has a 32 px hit area without a vertical layout shift.
class _CardCheckbox extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;

  const _CardCheckbox({required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AppTooltip(
      message: 'Выбрать файл',
      child: Semantics(
        checked: isSelected,
        child: Material(
          color: palette.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Icon(
                isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: isSelected ? palette.selection : palette.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small icon button over the thumbnail (menu in the card / list row).
class _OverlayIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final Color foreground;

  const _OverlayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.foreground,
    this.size = AppSizes.iconHitArea,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AppTooltip(
      message: tooltip,
      child: Material(
        color: palette.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: 18, color: foreground),
          ),
        ),
      ),
    );
  }
}

/// Outline drawn outside the card so keyboard focus is never confused with
/// selection (selection also has a checkbox and a filled surface).
class _FocusRing extends StatelessWidget {
  final Color color;

  const _FocusRing({required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card + AppStroke.focus),
        border: Border.all(color: color, width: AppStroke.focus),
      ),
    );
  }
}

/// Shared tap/selection/keyboard shell used by the grid card and list row.
Widget _buildFocusableShell({
  required ValueChanged<bool> onHoverChanged,
  required ValueChanged<bool> onFocusChanged,
  required VoidCallback onTap,
  required VoidCallback? onOpenPreview,
  required Widget child,
}) {
  return FocusableActionDetector(
    shortcuts: _activateShortcuts,
    actions: <Type, Action<Intent>>{
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          onTap();
          return null;
        },
      ),
    },
    onShowHoverHighlight: onHoverChanged,
    onShowFocusHighlight: onFocusChanged,
    mouseCursor: SystemMouseCursors.click,
    child: child,
  );
}

// ─── GenerationGridCard ──────────────────────────────────────────────────────

/// Grid card: thumbnail, filename, workflow status, size/resolution and tags.
///
/// Selection is a single click on the card (via [SingleClickArea]); the
/// checkbox and menu are Stack siblings, not descendants, so their clicks never
/// bubble into card selection.
class GenerationGridCard extends StatefulWidget {
  final String imagePath;
  final String filename;
  final bool isSelected;
  final bool isAccessible;
  final WorkflowStatus workflowStatus;
  final List<String> tags;
  final VoidCallback onTap;
  final VoidCallback? onOpenPreview;
  final VoidCallback? onMenu;
  final bool showCheckbox;

  const GenerationGridCard({
    super.key,
    required this.imagePath,
    required this.filename,
    required this.isSelected,
    required this.isAccessible,
    required this.workflowStatus,
    required this.onTap,
    this.tags = const [],
    this.onOpenPreview,
    this.onMenu,
    this.showCheckbox = true,
  });

  @override
  State<GenerationGridCard> createState() => _GenerationGridCardState();
}

class _GenerationGridCardState extends State<GenerationGridCard> {
  bool _hovered = false;
  bool _focused = false;
  /// Одиночный клик выбирает файл. Полный просмотр открывается из меню
  /// карточки (см. `onMenu`), чтобы не заводить таймеры двойного клика.
  void _handleCardTap() {
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (statusLabel, statusIcon) = _workflowStatusVisual(
      widget.workflowStatus,
    );
    final statusColor = _workflowStatusColor(widget.workflowStatus, palette);

    final background =
        widget.isSelected
            ? palette.selectionSurface
            : _hovered
            ? palette.surfaceHover
            : palette.surface;
    final borderColor =
        widget.isSelected
            ? palette.selection
            : _hovered
            ? palette.controlBorder
            : palette.border;

    return RepaintBoundary(
      child: _buildFocusableShell(
        onHoverChanged: (value) {
          if (_hovered != value) setState(() => _hovered = value);
        },
        onFocusChanged: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        onTap: widget.onTap,
        onOpenPreview: widget.onOpenPreview,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: AppMotion.hover,
              curve: AppMotion.easing,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: borderColor,
                  width:
                      widget.isSelected
                          ? AppStroke.selection
                          : AppStroke.normal,
                ),
              ),
              child: SingleClickArea(
                onTap: _handleCardTap,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () {},
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    hoverColor: Colors.transparent,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final thumbnail = ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(AppRadius.card),
                          ),
                          child: _MediaThumbnail(
                            path: widget.imagePath,
                            isAccessible: widget.isAccessible,
                          ),
                        );
                        final footer = _GenerationCardFooter(
                          filename: widget.filename,
                          tags: widget.tags,
                          statusLabel: statusLabel,
                          statusIcon: statusIcon,
                          statusColor: statusColor,
                          path: widget.imagePath,
                          isAccessible: widget.isAccessible,
                        );

                        // В сетке высоту миниатюры задаёт ячейка: при
                        // childAspectRatio из токенов (aspect 1.8 + footer)
                        // получается ровно 1.8, а при другой высоте сетка не
                        // ломается. Unbounded — единственный вне-сеточный путь.
                        if (constraints.maxHeight.isFinite) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [Expanded(child: thumbnail), footer],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AspectRatio(
                              aspectRatio: AppSizes.cardImageAspectRatio,
                              child: thumbnail,
                            ),
                            footer,
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showCheckbox)
              Positioned(
                top: 4,
                left: 4,
                child: _CardCheckbox(
                  isSelected: widget.isSelected,
                  onTap: widget.onTap,
                ),
              ),
            if (widget.onMenu != null)
              Positioned(
                top: 4,
                right: 4,
                child: _OverlayIconButton(
                  icon: Icons.more_horiz,
                  tooltip: 'Действия с файлом',
                  onPressed: widget.onMenu!,
                  foreground: palette.text,
                ),
              ),
            if (_focused)
              Positioned(
                left: -AppStroke.focus,
                top: -AppStroke.focus,
                right: -AppStroke.focus,
                bottom: -AppStroke.focus,
                child: IgnorePointer(
                  child: _FocusRing(color: palette.selection),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Two compact lines: filename + tag markers, then status + size/resolution.
class _GenerationCardFooter extends StatelessWidget {
  final String filename;
  final List<String> tags;
  final String statusLabel;
  final IconData statusIcon;
  final Color statusColor;
  final String path;
  final bool isAccessible;

  const _GenerationCardFooter({
    required this.filename,
    required this.tags,
    required this.statusLabel,
    required this.statusIcon,
    required this.statusColor,
    required this.path,
    required this.isAccessible,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      constraints: const BoxConstraints(
        minHeight: AppSizes.cardFooterMinHeight,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      alignment: Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AppTooltip(
                  message: filename,
                  child: Text(
                    filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      color: palette.text,
                    ),
                  ),
                ),
              ),
              if (tags.isNotEmpty) const SizedBox(width: 6),
              _TagMarkers(tags),
            ],
          ),
          const SizedBox(height: 2),
          LayoutBuilder(
            builder: (context, constraints) {
              // Разрешение — первое, что уходит в tooltip на узкой карточке.
              // Порог масштабируется вместе с текстом, чтобы при 150% не
              // оставалось обрезанного статуса.
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final showResolution = constraints.maxWidth >= 232 * textScale;
              return Row(
                children: [
                  Icon(statusIcon, size: 13, color: statusColor),
                  const SizedBox(width: 4),
                  Expanded(
                    child: AppTooltip(
                      message: statusLabel,
                      child: Text(
                        statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.55,
                    ),
                    child: _MediaMetaText(
                      path: path,
                      isAccessible: isAccessible,
                      showResolution: showResolution,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── GenerationFileListTile ──────────────────────────────────────────────────

/// Compact list row for the grid/list switch: same data and interactions as
/// [GenerationGridCard], 52 px tall with a 40 px thumbnail.
class GenerationFileListTile extends StatefulWidget {
  final String imagePath;
  final String filename;
  final bool isSelected;
  final bool isAccessible;
  final WorkflowStatus workflowStatus;
  final List<String> tags;
  final VoidCallback onTap;
  final VoidCallback? onOpenPreview;
  final VoidCallback? onMenu;
  final bool showCheckbox;

  const GenerationFileListTile({
    super.key,
    required this.imagePath,
    required this.filename,
    required this.isSelected,
    required this.isAccessible,
    required this.workflowStatus,
    required this.onTap,
    this.tags = const [],
    this.onOpenPreview,
    this.onMenu,
    this.showCheckbox = true,
  });

  @override
  State<GenerationFileListTile> createState() => _GenerationFileListTileState();
}

class _GenerationFileListTileState extends State<GenerationFileListTile> {
  bool _hovered = false;
  bool _focused = false;
  /// См. _GenerationGridCardState._handleCardTap.
  void _handleTileTap() {
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (statusLabel, statusIcon) = _workflowStatusVisual(
      widget.workflowStatus,
    );
    final statusColor = _workflowStatusColor(widget.workflowStatus, palette);

    final background =
        widget.isSelected
            ? palette.selectionSurface
            : _hovered
            ? palette.surfaceHover
            : Colors.transparent;
    final borderColor =
        widget.isSelected
            ? palette.selection
            : _hovered
            ? palette.border
            : Colors.transparent;

    return RepaintBoundary(
      child: _buildFocusableShell(
        onHoverChanged: (value) {
          if (_hovered != value) setState(() => _hovered = value);
        },
        onFocusChanged: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        onTap: widget.onTap,
        onOpenPreview: widget.onOpenPreview,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 52),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: borderColor,
                  width:
                      widget.isSelected
                          ? AppStroke.selection
                          : AppStroke.normal,
                ),
              ),
              child: SingleClickArea(
                onTap: _handleTileTap,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () {},
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    hoverColor: Colors.transparent,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        widget.showCheckbox ? 44 : 12,
                        6,
                        widget.onMenu != null ? 44 : 12,
                        6,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Не отдаём метаданным место, нужное миниатюре,
                          // имени и статусу: на узкой строке они уходят в
                          // tooltip, а не выталкивают соседей.
                          final metaMaxWidth = math.min(
                            math.min(220.0, constraints.maxWidth * 0.42),
                            math.max(0.0, constraints.maxWidth - 40 - 20 - 96),
                          );
                          return Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: _MediaThumbnail(
                                    path: widget.imagePath,
                                    isAccessible: widget.isAccessible,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: AppTooltip(
                                            message: widget.filename,
                                            child: Text(
                                              widget.filename,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                height: 1.3,
                                                color: palette.text,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (widget.tags.isNotEmpty)
                                          const SizedBox(width: 6),
                                        _TagMarkers(widget.tags),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(
                                          statusIcon,
                                          size: 13,
                                          color: statusColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: AppTooltip(
                                            message: statusLabel,
                                            child: Text(
                                              statusLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                height: 1.2,
                                                color: palette.textMuted,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: metaMaxWidth,
                                ),
                                child: _MediaMetaText(
                                  path: widget.imagePath,
                                  isAccessible: widget.isAccessible,
                                  showResolution: true,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showCheckbox)
              Positioned(
                left: 6,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _CardCheckbox(
                    isSelected: widget.isSelected,
                    onTap: widget.onTap,
                  ),
                ),
              ),
            if (widget.onMenu != null)
              Positioned(
                right: 6,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _OverlayIconButton(
                    icon: Icons.more_horiz,
                    tooltip: 'Действия с файлом',
                    onPressed: widget.onMenu!,
                    foreground: palette.text,
                    size: 32,
                  ),
                ),
              ),
            if (_focused)
              Positioned(
                left: -AppStroke.focus,
                top: -AppStroke.focus,
                right: -AppStroke.focus,
                bottom: -AppStroke.focus,
                child: IgnorePointer(
                  child: _FocusRing(color: palette.selection),
                ),
              ),
          ],
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
        color:
            isDark
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
            color:
                isUploaded
                    ? (isDark
                        ? AppTheme.successColorDark
                        : AppTheme.successColor)
                    : colorScheme.onSurface.withValues(alpha: 0.3),
            size: 18,
          ),
        ],
      ),
    );
  }
}
