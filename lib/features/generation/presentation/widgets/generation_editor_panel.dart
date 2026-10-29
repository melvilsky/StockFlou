import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/state/settings_provider.dart';
import '../../../../core/state/upload_queue_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/single_click_area.dart';
import '../../../../models/app_file.dart';
import '../../../../models/upload_job.dart';
import '../../domain/metadata_generation_operation.dart';
import 'generation_editorial_section.dart';
import 'generation_widgets.dart';

/// Режим применения ключевых слов к нескольким файлам.
enum KeywordsApplyMode { add, replace }

extension KeywordsApplyModeX on KeywordsApplyMode {
  String get label => this == KeywordsApplyMode.add ? 'Добавить' : 'Заменить';
}

/// Запрошенные изменения одного «применения» к выделению.
///
/// Незатронутые поля остаются `null`, чтобы не перезаписывать
/// индивидуальные значения файлов.
class BatchEditRequest {
  final bool titleTouched;
  final String title;
  final bool descriptionTouched;
  final String description;
  final KeywordsApplyMode keywordsMode;
  final List<String> keywordsToAdd;
  final List<String> keywordsToRemove;

  /// `null` — не трогать Editorial, `true` — включить, `false` — выключить.
  final bool? editorial;
  final String city;
  final String country;
  final DateTime? date;

  /// `null` — не трогать тег AI.
  final bool? aiTag;

  const BatchEditRequest({
    this.titleTouched = false,
    this.title = '',
    this.descriptionTouched = false,
    this.description = '',
    this.keywordsMode = KeywordsApplyMode.add,
    this.keywordsToAdd = const [],
    this.keywordsToRemove = const [],
    this.editorial,
    this.city = '',
    this.country = '',
    this.date,
    this.aiTag,
  });

  bool get hasChanges =>
      titleTouched ||
      descriptionTouched ||
      keywordsMode == KeywordsApplyMode.replace ||
      keywordsToAdd.isNotEmpty ||
      keywordsToRemove.isNotEmpty ||
      editorial != null ||
      aiTag != null;
}

/// Общие и различные значения выделения для полей редактора.
class BatchFieldInfo {
  final int count;
  final bool titleMixed;
  final String? titleCommon;
  final bool descriptionMixed;
  final String? descriptionCommon;
  final bool keywordsMixed;
  final List<String> keywordsCommon;
  final bool editorialMixed;
  final bool editorialCommon;
  final String cityCommon;
  final String countryCommon;
  final DateTime? dateCommon;
  final bool aiMixed;
  final bool aiCommon;

  const BatchFieldInfo({
    required this.count,
    required this.titleMixed,
    required this.titleCommon,
    required this.descriptionMixed,
    required this.descriptionCommon,
    required this.keywordsMixed,
    required this.keywordsCommon,
    required this.editorialMixed,
    required this.editorialCommon,
    required this.cityCommon,
    required this.countryCommon,
    required this.dateCommon,
    required this.aiMixed,
    required this.aiCommon,
  });

  static const empty = BatchFieldInfo(
    count: 0,
    titleMixed: false,
    titleCommon: null,
    descriptionMixed: false,
    descriptionCommon: null,
    keywordsMixed: false,
    keywordsCommon: [],
    editorialMixed: false,
    editorialCommon: false,
    cityCommon: '',
    countryCommon: '',
    dateCommon: null,
    aiMixed: false,
    aiCommon: false,
  );
}

/// Нижний общий редактор метаданных на всю ширину.
///
/// Для одного файла работает с контроллерами экрана и существующим
/// черновиком; для нескольких — держит собственный staged-черновик и
/// отдаёт его только по «Применить к N файлам».
class GenerationEditorPanel extends ConsumerStatefulWidget {
  final List<String> selectedPaths;
  final AppFile? selectedFile;
  final String? selectedLocalPath;
  final int hiddenSelectedCount;

  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final TextEditingController keywordsController;
  final bool metadataDirty;
  final bool isBusy;
  final bool isSaving;
  final int draftRevision;

  final BatchFieldInfo batchInfo;

  final VoidCallback onClearSelection;
  final VoidCallback onSaveSingle;
  final VoidCallback onSingleChanged;
  final ValueChanged<BatchEditRequest> onApplyBatch;
  final ValueChanged<BatchEditRequest?> onBatchDraftChanged;

  final VoidCallback onGenerateAI;
  final VoidCallback onGenerateBatchAI;
  final VoidCallback onExportCsv;
  final VoidCallback onImportCsv;
  final VoidCallback onRunQc;
  final VoidCallback onQueue;
  final VoidCallback onSaveAllMetadata;

  final bool collapsed;
  final ValueChanged<bool> onCollapsedChanged;
  final double height;
  final ValueChanged<double> onHeightChanged;

  const GenerationEditorPanel({
    super.key,
    required this.selectedPaths,
    required this.selectedFile,
    required this.selectedLocalPath,
    required this.hiddenSelectedCount,
    required this.titleController,
    required this.descriptionController,
    required this.keywordsController,
    required this.metadataDirty,
    required this.isBusy,
    required this.isSaving,
    required this.draftRevision,
    required this.batchInfo,
    required this.onClearSelection,
    required this.onSaveSingle,
    required this.onSingleChanged,
    required this.onApplyBatch,
    required this.onBatchDraftChanged,
    required this.onGenerateAI,
    required this.onGenerateBatchAI,
    required this.onExportCsv,
    required this.onImportCsv,
    required this.onRunQc,
    required this.onQueue,
    required this.onSaveAllMetadata,
    required this.collapsed,
    required this.onCollapsedChanged,
    required this.height,
    required this.onHeightChanged,
  });

  @override
  ConsumerState<GenerationEditorPanel> createState() =>
      _GenerationEditorPanelState();
}

class _GenerationEditorPanelState extends ConsumerState<GenerationEditorPanel> {
  final _multiTitleController = TextEditingController();
  final _multiDescriptionController = TextEditingController();
  final _multiCityController = TextEditingController();
  final _multiCountryController = TextEditingController();
  final _multiKeywordInputController = TextEditingController();

  bool _titleTouched = false;
  bool _descriptionTouched = false;
  bool _titleCleared = false;
  bool _descriptionCleared = false;
  KeywordsApplyMode _keywordsMode = KeywordsApplyMode.add;
  final List<String> _keywordsToAdd = [];
  final List<String> _keywordsToRemove = [];
  final Set<String> _hiddenCommonKeywords = {};
  bool? _editorialMode;
  bool? _aiMode;
  DateTime? _editorialDate;
  int _compactTab = 0;

  bool get _isSingle => widget.selectedPaths.length == 1;

  bool get _isBatch => widget.selectedPaths.length > 1;

  @override
  void didUpdateWidget(GenerationEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draftRevision != widget.draftRevision) {
      _resetBatchDraft();
    } else if (!_sameSelection(oldWidget.selectedPaths, widget.selectedPaths)) {
      // Черновик привязан к конкретному набору: другой набор той же длины
      // не должен получить чужие правки.
      _resetBatchDraft();
    }
  }

  @override
  void dispose() {
    _multiTitleController.dispose();
    _multiDescriptionController.dispose();
    _multiCityController.dispose();
    _multiCountryController.dispose();
    _multiKeywordInputController.dispose();
    super.dispose();
  }

  bool _sameSelection(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _resetBatchDraft() {
    _titleTouched = false;
    _descriptionTouched = false;
    _titleCleared = false;
    _descriptionCleared = false;
    _keywordsMode = KeywordsApplyMode.add;
    _keywordsToAdd.clear();
    _keywordsToRemove.clear();
    _hiddenCommonKeywords.clear();
    _editorialMode = null;
    _aiMode = null;
    _editorialDate = null;
    _multiTitleController.clear();
    _multiDescriptionController.clear();
    _multiCityController.clear();
    _multiCountryController.clear();
    _multiKeywordInputController.clear();
    widget.onBatchDraftChanged(null);
  }

  BatchEditRequest _buildRequest() {
    return BatchEditRequest(
      titleTouched: _titleTouched,
      title: _multiTitleController.text.trim(),
      descriptionTouched: _descriptionTouched,
      description: _multiDescriptionController.text.trim(),
      keywordsMode: _keywordsMode,
      keywordsToAdd: List.unmodifiable(_keywordsToAdd),
      keywordsToRemove: List.unmodifiable(_keywordsToRemove),
      editorial: _editorialMode,
      city: _multiCityController.text.trim(),
      country: _multiCountryController.text.trim(),
      date: _editorialDate,
      aiTag: _aiMode,
    );
  }

  void _emitDraft() {
    if (!_isBatch) return;
    setState(() {});
    final request = _buildRequest();
    widget.onBatchDraftChanged(request.hasChanges ? request : null);
  }

  void _applyBatch() {
    final request = _buildRequest();
    if (!request.hasChanges) return;
    widget.onApplyBatch(request);
  }

  // ─── Layout ────────────────────────────────────────────────────────────────

  /// Общие значения показываются как значения, различающиеся — как placeholder.
  /// Значение из контроллера применяется только при явном редактировании
  /// (`_titleTouched` / `_descriptionTouched`), поэтому показ не означает запись.
  void _syncCommonValues(BatchFieldInfo info) {
    if (!_isBatch) return;
    if (!_titleTouched) {
      final common = info.titleMixed ? '' : (info.titleCommon ?? '');
      if (_multiTitleController.text != common) {
        _multiTitleController.text = common;
      }
    }
    if (!_descriptionTouched) {
      final common = info.descriptionMixed ? '' : (info.descriptionCommon ?? '');
      if (_multiDescriptionController.text != common) {
        _multiDescriptionController.text = common;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final count = widget.selectedPaths.length;
    if (count > 1) _syncCommonValues(widget.batchInfo);

    if (count == 0) {
      return _buildCollapsedRow(palette);
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Column(
        children: [
          _buildGrabber(palette),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textScale = MediaQuery.textScalerOf(context).scale(1);
                final useTabs =
                    constraints.maxWidth <
                    AppSizes.compactMinWidth * textScale;
                if (useTabs) return _buildTabsLayout(palette, constraints);
                return _buildColumnsLayout(palette);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedRow(AppPalette palette) {
    return Container(
      height: AppSizes.editorCollapsedHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.pagePadding),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_note_outlined, size: 18, color: palette.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Выберите файлы для редактирования',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: palette.text,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Массовые действия станут доступны после выделения',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: palette.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrabber(AppPalette palette) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          widget.onHeightChanged(widget.height - details.delta.dy);
        },
        child: Container(
          height: 8,
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            width: 42,
            height: 3,
            decoration: BoxDecoration(
              color: palette.controlBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColumnsLayout(AppPalette palette) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 41, child: _columnScroll(_textColumn(palette))),
        _divider(palette),
        Expanded(flex: 27, child: _columnScroll(_keywordsColumn(palette))),
        _divider(palette),
        Expanded(flex: 32, child: _columnScroll(_actionsColumn(palette))),
      ],
    );
  }

  Widget _divider(AppPalette palette) {
    return Container(width: AppStroke.normal, color: palette.border);
  }

  Widget _columnScroll(Widget child) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.pagePadding,
        AppSpacing.sm,
        AppSizes.pagePadding,
        AppSpacing.md,
      ),
      child: child,
    );
  }

  Widget _buildTabsLayout(AppPalette palette, BoxConstraints constraints) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.pagePadding,
            AppSpacing.xs,
            AppSizes.pagePadding,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              _compactTabButton(palette, 0, 'Текст'),
              const SizedBox(width: AppSpacing.sm),
              _compactTabButton(palette, 1, 'Ключи'),
              const SizedBox(width: AppSpacing.sm),
              _compactTabButton(palette, 2, 'Действия'),
              const Spacer(),
              Text(
                '${widget.selectedPaths.length} выбрано',
                style: TextStyle(fontSize: 12, color: palette.textMuted),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.pagePadding,
              AppSpacing.sm,
              AppSizes.pagePadding,
              AppSpacing.md,
            ),
            child: switch (_compactTab) {
              1 => _keywordsColumn(palette),
              2 => _actionsColumn(palette),
              _ => _textColumn(palette),
            },
          ),
        ),
      ],
    );
  }

  Widget _compactTabButton(AppPalette palette, int index, String label) {
    final isActive = _compactTab == index;
    return SingleClickArea(
      onTap: () => setState(() => _compactTab = index),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? palette.surfaceRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: isActive ? palette.controlBorder : palette.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            color: isActive ? palette.text : palette.textMuted,
          ),
        ),
      ),
    );
  }

  // ─── Левая колонка: текст ──────────────────────────────────────────────────

  Widget _textColumn(AppPalette palette) {
    final count = widget.selectedPaths.length;
    final isSingle = _isSingle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isSingle ? '1 файл выбран' : '$count файлов выбрано',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: palette.text,
                ),
              ),
            ),
            if (widget.hiddenSelectedCount > 0)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Text(
                  'скрыто: ${widget.hiddenSelectedCount}',
                  style: TextStyle(fontSize: 11, color: palette.textMuted),
                ),
              ),
            AppTooltip(
              message: 'Снять выделение, не меняя метаданные',
              child: TextButton.icon(
                onPressed: widget.onClearSelection,
                icon: const Icon(Icons.close, size: 15),
                label: const Text('Снять выделение'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _fieldLabel(palette, 'Заголовок (Title)'),
        const SizedBox(height: AppSpacing.xs),
        if (isSingle)
          _singleTextField(
            palette,
            controller: widget.titleController,
            maxLines: 1,
            hint: 'Заголовок',
            onChanged: (_) => widget.onSingleChanged(),
            onClear: () {
              widget.titleController.clear();
              widget.onSingleChanged();
            },
          )
        else
          _batchTextField(
            palette,
            controller: _multiTitleController,
            mixed: widget.batchInfo.titleMixed,
            mixedValue: widget.batchInfo.titleCommon,
            cleared: _titleCleared,
            maxLines: 1,
            hint: 'Заголовок',
            onTouched: () {
              if (!_titleTouched) {
                _titleTouched = true;
                _titleCleared = false;
              }
            },
            onClear: () {
              _multiTitleController.clear();
              _titleTouched = true;
              _titleCleared = true;
              _emitDraft();
            },
          ),
        if (!isSingle && _titleTouched && _titleCleared)
          _clearNote(palette, 'Значение будет очищено у выбранных файлов'),
        const SizedBox(height: AppSpacing.md),
        _fieldLabel(palette, 'Описание (Description)'),
        const SizedBox(height: AppSpacing.xs),
        if (isSingle)
          _singleTextField(
            palette,
            controller: widget.descriptionController,
            maxLines: 3,
            hint: 'Описание',
            onChanged: (_) => widget.onSingleChanged(),
            onClear: () {
              widget.descriptionController.clear();
              widget.onSingleChanged();
            },
          )
        else
          _batchTextField(
            palette,
            controller: _multiDescriptionController,
            mixed: widget.batchInfo.descriptionMixed,
            mixedValue: widget.batchInfo.descriptionCommon,
            cleared: _descriptionCleared,
            maxLines: 3,
            hint: 'Описание',
            onTouched: () {
              if (!_descriptionTouched) {
                _descriptionTouched = true;
                _descriptionCleared = false;
              }
            },
            onClear: () {
              _multiDescriptionController.clear();
              _descriptionTouched = true;
              _descriptionCleared = true;
              _emitDraft();
            },
          ),
        if (!isSingle && _descriptionTouched && _descriptionCleared)
          _clearNote(palette, 'Описание будет очищено у выбранных файлов'),
      ],
    );
  }

  Widget _fieldLabel(AppPalette palette, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: palette.textMuted,
      ),
    );
  }

  Widget _clearNote(AppPalette palette, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 13, color: palette.warning),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11, color: palette.warning),
            ),
          ),
        ],
      ),
    );
  }

  Widget _singleTextField(
    AppPalette palette, {
    required TextEditingController controller,
    required int maxLines,
    required String hint,
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Очистить поле',
                    onPressed: onClear,
                    icon: const Icon(Icons.backspace_outlined, size: 15),
                  ),
          ),
          onChanged: onChanged,
        );
      },
    );
  }

  Widget _batchTextField(
    AppPalette palette, {
    required TextEditingController controller,
    required bool mixed,
    required String? mixedValue,
    required bool cleared,
    required int maxLines,
    required String hint,
    required VoidCallback onTouched,
    required VoidCallback onClear,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final untouched = !_isFieldTouched(controller) && !cleared;
        return TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: untouched && mixed
                ? 'Разные значения'
                : (untouched && (mixedValue ?? '').isNotEmpty
                    ? mixedValue
                    : hint),
            hintStyle: TextStyle(
              fontSize: 13,
              fontStyle: untouched && mixed ? FontStyle.italic : FontStyle.normal,
              color: mixed ? palette.warning : palette.textMuted,
            ),
            suffixIcon: value.text.isNotEmpty || !untouched
                ? IconButton(
                    tooltip: 'Очистить у выбранных файлов',
                    onPressed: onClear,
                    icon: const Icon(Icons.backspace_outlined, size: 15),
                  )
                : null,
          ),
          onChanged: (_) {
            onTouched();
            _emitDraft();
          },
        );
      },
    );
  }

  bool _isFieldTouched(TextEditingController controller) {
    return controller == _multiTitleController ? _titleTouched : _descriptionTouched;
  }

  // ─── Средняя колонка: ключи и Editorial ───────────────────────────────────

  Widget _keywordsColumn(AppPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(palette, 'Ключевые слова'),
        if (_isBatch) ...[
          const SizedBox(height: AppSpacing.sm),
          _modeToggle(palette),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (_isSingle)
          _KeywordsChipsField(
            controller: widget.keywordsController,
            onChanged: (_) => widget.onSingleChanged(),
          )
        else
          _batchKeywordsField(palette),
        const SizedBox(height: AppSpacing.lg),
        _sectionTitle(palette, 'Editorial'),
        const SizedBox(height: AppSpacing.sm),
        if (_isSingle)
          GenerationEditorialSection(
            key: ValueKey(
              'editorial_${widget.selectedFile?.id ?? widget.selectedLocalPath ?? 'none'}',
            ),
            isMulti: false,
            selectedPaths: widget.selectedPaths.toSet(),
            selectedExistingFile: widget.selectedFile,
            selectedLocalInspectorPath: widget.selectedLocalPath,
          )
        else
          _batchEditorialField(palette),
      ],
    );
  }

  Widget _sectionTitle(AppPalette palette, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: palette.textMuted,
      ),
    );
  }

  Widget _modeToggle(AppPalette palette) {
    Widget item(KeywordsApplyMode mode) {
      final isActive = _keywordsMode == mode;
      return Expanded(
        child: AppTooltip(
          message: mode == KeywordsApplyMode.add
              ? 'Безопасный режим: новые ключи добавляются к индивидуальным'
              : 'Полная замена ключей у выбранных файлов',
          child: SingleClickArea(
            onTap: () {
              setState(() {
                _keywordsMode = mode;
              });
              _emitDraft();
            },
            child: Container(
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive ? palette.surfaceRaised : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: Border.all(
                  color: isActive ? palette.controlBorder : Colors.transparent,
                ),
              ),
              child: Text(
                mode.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive ? palette.text : palette.textMuted,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 30,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: palette.field,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: palette.border),
      ),
      child: Row(children: [item(KeywordsApplyMode.add), item(KeywordsApplyMode.replace)]),
    );
  }

  Widget _batchKeywordsField(AppPalette palette) {
    final info = widget.batchInfo;
    final showCommon = !info.keywordsMixed && _keywordsMode == KeywordsApplyMode.add;
    final chips = <Widget>[];
    if (showCommon) {
      for (final keyword in info.keywordsCommon) {
        if (_hiddenCommonKeywords.contains(keyword)) continue;
        chips.add(
          _RemovableChip(
            label: keyword,
            tooltip: 'Удалить у выбранных файлов',
            onRemove: () {
              setState(() {
                _hiddenCommonKeywords.add(keyword);
                if (!_keywordsToRemove.contains(keyword)) {
                  _keywordsToRemove.add(keyword);
                }
              });
              _emitDraft();
            },
          ),
        );
      }
    }
    for (final keyword in _keywordsToAdd) {
      chips.add(
        _RemovableChip(
          label: keyword,
          tooltip: 'Убрать из списка добавления',
          onRemove: () {
            setState(() => _keywordsToAdd.remove(keyword));
            _emitDraft();
          },
        ),
      );
    }
    final replacedChips =
        _keywordsMode == KeywordsApplyMode.replace
            ? _keywordsToAdd
            : const <String>[];
    if (_keywordsMode == KeywordsApplyMode.replace &&
        replacedChips.isEmpty &&
        (info.keywordsCommon.isNotEmpty || info.keywordsMixed)) {
      chips.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Text(
            info.keywordsMixed
                ? 'Разные значения — введите новый список'
                : info.keywordsCommon.join(', '),
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: palette.textMuted,
            ),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minHeight: AppSizes.controlHeight),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: palette.field,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: palette.controlBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showCommon && chips.isNotEmpty)
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final chip in chips) chip,
              ],
            ),
          if (_keywordsMode == KeywordsApplyMode.replace && chips.isEmpty)
            const SizedBox.shrink()
          else if (replacedChips.isNotEmpty)
            SizedBox.shrink(),
          if (showCommon) const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _multiKeywordInputController,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText:
                  _keywordsMode == KeywordsApplyMode.add
                      ? 'Добавить ключи через запятую'
                      : 'Новый список ключей через запятую',
              hintStyle: TextStyle(fontSize: 12, color: palette.textMuted),
            ),
            onSubmitted: _addKeywordInput,
            onChanged: (value) {
              if (value.contains(',')) {
                final parts = value.split(',');
                for (var i = 0; i < parts.length - 1; i++) {
                  _addKeyword(parts[i]);
                }
                _multiKeywordInputController.text = parts.last;
                _multiKeywordInputController.selection =
                    TextSelection.fromPosition(
                      TextPosition(offset: _multiKeywordInputController.text.length),
                    );
              }
            },
          ),
          if (_keywordsMode == KeywordsApplyMode.replace && _keywordsToAdd.isEmpty)
            Text(
              'Пустой список заменит ключи выбранных файлов',
              style: TextStyle(fontSize: 11, color: palette.warning),
            ),
        ],
      ),
    );
  }

  void _addKeywordInput(String value) {
    _addKeyword(value);
    _multiKeywordInputController.clear();
  }

  void _addKeyword(String raw) {
    final keyword = raw.trim();
    if (keyword.isEmpty) return;
    setState(() {
      if (!_keywordsToAdd.contains(keyword)) {
        _keywordsToAdd.add(keyword);
      }
      _hiddenCommonKeywords.remove(keyword);
      _keywordsToRemove.remove(keyword);
    });
    _emitDraft();
  }

  Widget _batchEditorialField(AppPalette palette) {
    final info = widget.batchInfo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _triStateRow(
          palette,
          value: _editorialMode,
          mixed: info.editorialMixed,
          common: info.editorialCommon,
          onChange: (value) {
            setState(() => _editorialMode = value);
            _emitDraft();
          },
        ),
        if (info.editorialMixed)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Редакционные флаги выбранных файлов различаются',
              style: TextStyle(fontSize: 11, color: palette.textMuted),
            ),
          ),
        if (_editorialMode == true) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _multiCityController,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(hintText: 'Город'),
                  onChanged: (_) => _emitDraft(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _multiCountryController,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(hintText: 'Страна'),
                  onChanged: (_) => _emitDraft(),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () async {
              final today = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _editorialDate ?? today,
                firstDate: DateTime(1970),
                lastDate: today,
                helpText: 'Дата съёмки',
              );
              if (picked == null) return;
              setState(() => _editorialDate = picked);
              _emitDraft();
            },
            icon: const Icon(Icons.calendar_today, size: 14),
            label: Text(
              _editorialDate == null
                  ? 'Дата съёмки'
                  : formatEditorialDate(_editorialDate!),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        _sectionTitle(palette, 'AI-тег'),
        const SizedBox(height: AppSpacing.sm),
        _triStateRow(
          palette,
          value: _aiMode,
          mixed: info.aiMixed,
          common: info.aiCommon,
          onChange: (value) {
            setState(() => _aiMode = value);
            _emitDraft();
          },
        ),
      ],
    );
  }

  /// Три состояния для полей, которые не должны затрагиваться по умолчанию.
  Widget _triStateRow(
    AppPalette palette, {
    required bool? value,
    required bool mixed,
    required bool common,
    required ValueChanged<bool?> onChange,
  }) {
    Widget item(String label, bool? itemValue) {
      final isActive = value == itemValue;
      return Expanded(
        child: SingleClickArea(
          onTap: () => onChange(itemValue),
          child: Container(
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isActive ? palette.selectionSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(
                color: isActive ? palette.selection : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? palette.text : palette.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 30,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: palette.field,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          item(mixed ? 'Не менять (разные)' : 'Не менять', null),
          item('Вкл', true),
          item('Выкл', false),
        ],
      ),
    );
  }

  // ─── Правая колонка: действия ──────────────────────────────────────────────

  Widget _actionsColumn(AppPalette palette) {
    final count = widget.selectedPaths.length;
    final busy = widget.isBusy || widget.isSaving;
    final request = _isBatch ? _buildRequest() : null;
    final canApply = _isSingle
        ? widget.metadataDirty && !busy
        : (request?.hasChanges ?? false) && !busy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _sectionTitle(
                palette,
                _isSingle ? 'Действия для файла' : 'Действия для $count файлов',
              ),
            ),
            IconButton(
              tooltip: 'Свернуть редактор',
              onPressed: () => widget.onCollapsedChanged(true),
              icon: const Icon(Icons.expand_more, size: 18),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _actionButton(
                palette,
                icon: Icons.auto_awesome,
                label: 'AI метаданные',
                onTap: busy
                    ? null
                    : () {
                        if (count > 1) {
                          widget.onGenerateBatchAI();
                        } else {
                          widget.onGenerateAI();
                        }
                      },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _actionButton(
                palette,
                icon: Icons.fact_check_outlined,
                label: 'QC проверка',
                onTap: busy ? null : widget.onRunQc,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _actionButton(
                palette,
                icon: Icons.description_outlined,
                label: 'CSV экспорт',
                onTap: busy ? null : widget.onExportCsv,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _actionButton(
                palette,
                icon: Icons.cloud_upload_outlined,
                label: 'В очередь',
                onTap: busy ? null : widget.onQueue,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _buildSummary(palette),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          onPressed: canApply
              ? (_isSingle ? widget.onSaveSingle : _applyBatch)
              : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(40),
          ),
          child: Text(
            _isSingle
                ? 'Сохранить изменения'
                : busy
                    ? 'Применение…'
                    : 'Применить к $count файлам',
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppTooltip(
          message:
              'Записать метаданные всех файлов во всех рабочих областях в файлы',
          child: TextButton(
            onPressed: busy ? null : widget.onSaveAllMetadata,
            child: const Text('Записать все метаданные в файлы'),
          ),
        ),
        if (_isSingle && _isVideoSelected())
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Для видео запись метаданных в файл недоступна — сохраняются в базе',
              style: TextStyle(fontSize: 11, color: palette.textMuted),
            ),
          ),
        if (_isSingle) ...[
          const SizedBox(height: AppSpacing.md),
          _buildStockStatus(palette),
        ],
      ],
    );
  }

  bool _isVideoSelected() {
    final path = widget.selectedFile?.path ?? widget.selectedLocalPath;
    return path != null && AppConstants.isVideo(path);
  }

  Widget _buildSummary(AppPalette palette) {
    final String summary;
    if (_isSingle) {
      summary =
          widget.metadataDirty
              ? 'Есть несохранённые изменения'
              : 'Изменений нет';
    } else {
      final request = _buildRequest();
      if (!request.hasChanges) {
        summary = 'Изменённых полей нет — «Применить» недоступно';
      } else {
        final parts = <String>[];
        if (request.titleTouched) {
          parts.add(request.title.isEmpty ? 'заголовок: очистить' : 'заголовок');
        }
        if (request.descriptionTouched) {
          parts.add(
            request.description.isEmpty ? 'описание: очистить' : 'описание',
          );
        }
        if (request.keywordsMode == KeywordsApplyMode.replace) {
          parts.add('ключи: заменить');
        } else if (request.keywordsToAdd.isNotEmpty ||
            request.keywordsToRemove.isNotEmpty) {
          parts.add(
            'ключи: добавить ${request.keywordsToAdd.length}'
            '${request.keywordsToRemove.isNotEmpty ? ', удалить ${request.keywordsToRemove.length}' : ''}',
          );
        }
        if (request.editorial != null) {
          parts.add(
            request.editorial! ? 'Editorial: включить' : 'Editorial: выключить',
          );
        }
        if (request.aiTag != null) {
          parts.add(request.aiTag! ? 'AI-тег: включить' : 'AI-тег: выключить');
        }
        summary = parts.join(' · ');
      }
    }
    return Text(
      summary,
      style: TextStyle(fontSize: 11, color: palette.textMuted),
    );
  }

  Widget _actionButton(
    AppPalette palette, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return AppTooltip(
      message: enabled ? label : 'Недоступно во время выполнения',
      child: SingleClickArea(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: palette.controlBorder),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: enabled ? palette.primary : palette.textMuted,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: enabled ? palette.text : palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStockStatus(AppPalette palette) {
    final settings = ref.watch(settingsProvider).value;
    final adobeCreds = settings?.adobeCredentials;
    final shutterCreds = settings?.shutterstockCredentials;
    final hasAdobe = adobeCreds != null && !adobeCreds.isEmpty;
    final hasShutter = shutterCreds != null && !shutterCreds.isEmpty;
    if (!hasAdobe && !hasShutter) {
      return Text(
        'Добавьте учётные данные стоков в настройках',
        style: TextStyle(fontSize: 11, color: palette.textMuted),
      );
    }
    final queue = ref.watch(uploadQueueProvider).value ?? const <UploadJob>[];
    final fileId = widget.selectedFile?.id;
    bool isUploadedTo(String stockKey) {
      if (fileId == null) return false;
      return queue.any(
        (job) =>
            job.fileId == fileId &&
            job.stockKey == stockKey &&
            job.status == UploadJobStatus.success,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasAdobe) ...[
          GenerationStockStatusCard(
            code: 'AS',
            label: 'Adobe Stock',
            color: palette.error,
            isUploaded: isUploadedTo('adobe'),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (hasShutter)
          GenerationStockStatusCard(
            code: 'SS',
            label: 'Shutterstock',
            color: palette.selection,
            isUploaded: isUploadedTo('shutterstock'),
          ),
      ],
    );
  }
}

// ─── Ключевые слова ──────────────────────────────────────────────────────────

class _KeywordsChipsField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _KeywordsChipsField({
    required this.controller,
    required this.onChanged,
  });

  @override
  State<_KeywordsChipsField> createState() => _KeywordsChipsFieldState();
}

class _KeywordsChipsFieldState extends State<_KeywordsChipsField> {
  final _inputController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onParentChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onParentChanged);
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onParentChanged() {
    if (mounted) setState(() {});
  }

  List<String> get _keywords => _parseKeywords(widget.controller.text);

  void _add(String raw) {
    final keyword = raw.trim();
    if (keyword.isEmpty) return;
    if (_keywords.contains(keyword)) return;
    final next = [..._keywords, keyword];
    widget.controller.text = next.join(', ');
    widget.onChanged(widget.controller.text);
  }

  void _remove(String keyword) {
    final next = _keywords.where((k) => k != keyword).toList();
    widget.controller.text = next.join(', ');
    widget.onChanged(widget.controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: AppSizes.controlHeight),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: palette.field,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: palette.controlBorder),
      ),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final keyword in _keywords)
            _RemovableChip(
              label: keyword,
              tooltip: 'Удалить ключ',
              onRemove: () => _remove(keyword),
            ),
          IntrinsicWidth(
            child: TextField(
              controller: _inputController,
              focusNode: _focusNode,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: _keywords.isEmpty
                    ? 'Введите ключи через запятую'
                    : 'Добавить…',
                hintStyle: TextStyle(fontSize: 12, color: palette.textMuted),
              ),
              onSubmitted: (value) {
                _add(value);
                _inputController.clear();
              },
              onChanged: (value) {
                if (!value.contains(',')) return;
                final parts = value.split(',');
                for (var i = 0; i < parts.length - 1; i++) {
                  _add(parts[i]);
                }
                _inputController.text = parts.last;
                _inputController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _inputController.text.length),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RemovableChip extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback onRemove;

  const _RemovableChip({
    required this.label,
    required this.tooltip,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: AppSizes.chipMinHeight),
      padding: const EdgeInsets.only(left: AppSpacing.sm, right: AppSpacing.xs),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: palette.text),
          ),
          const SizedBox(width: AppSpacing.xs),
          AppTooltip(
            message: tooltip,
            child: SizedBox(
              width: AppSizes.chipRemoveHitArea,
              height: AppSizes.chipRemoveHitArea,
              child: SingleClickArea(
                onTap: onRemove,
                child: Icon(Icons.close, size: 13, color: palette.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<String> _parseKeywords(String value) {
  return value
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
}
