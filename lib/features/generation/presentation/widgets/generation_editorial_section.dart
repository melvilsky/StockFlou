import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/geocoding_service.dart';
import '../../../../core/services/metadata_service.dart';
import '../../../../core/state/editorial_state_provider.dart';
import '../../../../core/state/files_provider.dart';
import '../../../../core/state/settings_provider.dart';
import '../../../../core/widgets/single_click_area.dart';
import '../../../../models/app_file.dart';
import '../../domain/metadata_generation_operation.dart';
import 'generation_widgets.dart';

/// Editorial metadata section: toggle pills + city / country / date fields.
/// Reads and writes editorial state via [editorialStateProvider].
class GenerationEditorialSection extends ConsumerStatefulWidget {
  final bool isMulti;
  final Set<String> selectedPaths;
  final AppFile? selectedExistingFile;
  final String? selectedLocalInspectorPath;

  const GenerationEditorialSection({
    super.key,
    required this.isMulti,
    required this.selectedPaths,
    this.selectedExistingFile,
    this.selectedLocalInspectorPath,
  });

  @override
  ConsumerState<GenerationEditorialSection> createState() =>
      _GenerationEditorialSectionState();
}

class _GenerationEditorialSectionState
    extends ConsumerState<GenerationEditorialSection> {
  // Text controllers kept local because RawAutocomplete needs them,
  // but they sync with the provider on every change.
  final _cityController = TextEditingController();
  final _countryController = TextEditingController();
  final _cityFocusNode = FocusNode();
  final _countryFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Sync text controllers from provider on first build
    final state = ref.read(editorialStateProvider);
    _cityController.text = state.city;
    _countryController.text = state.country;
  }

  @override
  void didUpdateWidget(GenerationEditorialSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When selected file changes, sync text controllers from provider
    final newFile = widget.selectedExistingFile;
    final oldFile = oldWidget.selectedExistingFile;
    if (newFile?.id != oldFile?.id) {
      final state = ref.read(editorialStateProvider);
      _cityController.text = state.city;
      _countryController.text = state.country;
    }
  }

  @override
  void dispose() {
    _cityController.dispose();
    _countryController.dispose();
    _cityFocusNode.dispose();
    _countryFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickShootDate(EditorialStateNotifier notifier) async {
    final current = ref.read(editorialStateProvider).date;
    final today = DateTime.now();
    final last = DateTime(today.year, today.month, today.day);
    final first = DateTime(1970);
    var initial = current ?? last;
    if (initial.isAfter(last)) initial = last;
    if (initial.isBefore(first)) initial = first;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Дата съёмки',
      cancelText: 'Отмена',
      confirmText: 'Выбрать',
    );
    if (picked == null || !mounted) return;
    final date = DateTime(picked.year, picked.month, picked.day);
    notifier.setDate(date);
    await _batchUpdate(date: date);
  }

  /// Update editorial fields on DB files or insert local files as new DB entries.
  Future<void> _batchUpdate({
    bool? isEditorial,
    String? city,
    String? country,
    DateTime? date,
  }) async {
    final allFiles = ref.read(filesProvider).value ?? [];
    for (final path in widget.selectedPaths) {
      final idx = allFiles.indexWhere((f) => f.path == path);

      if (idx == -1) {
        // File does not exist in DB yet, create it
        final shouldBeEditorial = isEditorial ?? false;
        final newTags = shouldBeEditorial ? [AppTags.editorial] : <String>[];

        final newFile = AppFile(
          id: const Uuid().v4(),
          path: path,
          filename: path.split(Platform.pathSeparator).last,
          isEditorial: shouldBeEditorial,
          editorialCity: city,
          editorialCountry: country,
          editorialDate: date?.millisecondsSinceEpoch,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          tags: newTags,
        );
        await ref.read(filesProvider.notifier).addFile(newFile);
      } else {
        // File already in DB, update it
        final f = allFiles[idx];
        final newTags = List<String>.from(f.tags);
        final shouldBeEditorial = isEditorial ?? f.isEditorial;
        if (shouldBeEditorial && !newTags.contains(AppTags.editorial)) {
          newTags.add(AppTags.editorial);
        } else if (!shouldBeEditorial) {
          newTags.remove(AppTags.editorial);
        }
        final updated = f.copyWith(
          isEditorial: isEditorial ?? f.isEditorial,
          editorialCity: city ?? f.editorialCity,
          editorialCountry: country ?? f.editorialCountry,
          editorialDate:
              date != null ? date.millisecondsSinceEpoch : f.editorialDate,
          tags: newTags,
        );
        await ref.read(filesProvider.notifier).updateFile(updated);
      }
    }
  }

  Future<void> _updateAITag(bool isAI) async {
    final allFiles = ref.read(filesProvider).value ?? [];
    for (final path in widget.selectedPaths) {
      final idx = allFiles.indexWhere((f) => f.path == path);
      if (idx == -1) {
        // File does not exist in DB yet, create it
        final newTags = isAI ? [AppTags.aiGenerated] : <String>[];
        final newFile = AppFile(
          id: const Uuid().v4(),
          path: path,
          filename: path.split(Platform.pathSeparator).last,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          tags: newTags,
        );
        await ref.read(filesProvider.notifier).addFile(newFile);
      } else {
        // File exists, update it
        final f = allFiles[idx];
        final updated =
            isAI
                ? f.withTag(AppTags.aiGenerated)
                : f.withoutTag(AppTags.aiGenerated);
        await ref.read(filesProvider.notifier).updateFile(updated);
      }
    }
  }

  InputDecoration _inputDecor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
    );
  }

  Widget _autocompleteOptionsView(
    BuildContext context,
    AutocompleteOnSelected<String> onSelected,
    Iterable<String> options,
    ColorScheme colorScheme,
  ) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 296),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options.elementAt(index);
              return ListTile(
                dense: true,
                title: Text(option, style: const TextStyle(fontSize: 13)),
                onTap: () => onSelected(option),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final editorial = ref.watch(editorialStateProvider);
    final notifier = ref.read(editorialStateProvider.notifier);

    // Keep text controllers in sync with provider (provider is source of truth
    // when changed externally, e.g. by _toggleSelection in parent).
    if (_cityController.text != editorial.city) {
      _cityController.text = editorial.city;
    }
    if (_countryController.text != editorial.country) {
      _countryController.text = editorial.country;
    }

    final savedLocations =
        ref.watch(settingsProvider).value?.savedLocations ?? [];
    final cities =
        savedLocations
            .map((e) => e.split('|').first)
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
    final countries =
        savedLocations
            .map((e) => e.split('|').length > 1 ? e.split('|').last : '')
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tag toggle pills — AI and Editorial side by side
        const SizedBox(height: 4),
        Row(
          children: [
            _TagToggle(
              label: 'AI',
              icon: Icons.auto_awesome,
              color: const Color(0xFF7C3AED),
              isActive: editorial.isAI,
              onTap: () async {
                final newVal = !editorial.isAI;
                notifier.setAI(newVal);
                await _updateAITag(newVal);
              },
            ),
            const SizedBox(width: 8),
            _TagToggle(
              label: 'Эдиториал',
              icon: Icons.newspaper,
              color: const Color(0xFFD97706),
              isActive: editorial.isEditorial,
              onTap: () async {
                final newVal = !editorial.isEditorial;
                notifier.setEditorial(newVal);

                if (newVal) {
                  // turned on: auto-fetch location and date
                  String? filePath =
                      widget.selectedExistingFile?.path ??
                      widget.selectedLocalInspectorPath;
                  if (filePath == null && widget.selectedPaths.isNotEmpty) {
                    filePath = widget.selectedPaths.first;
                  }

                  String newCity = '';
                  String newCountry = '';
                  DateTime? newDate;

                  if (filePath != null) {
                    final exif = await MetadataService.readExifLocationAndDate(
                      filePath,
                    );
                    newDate = exif.date;
                    if (exif.lat != null && exif.lon != null) {
                      final geo = await GeocodingService.resolve(
                        exif.lat,
                        exif.lon,
                      );
                      if (geo.city != null) newCity = geo.city!;
                      newCountry = geo.country ?? geo.state ?? '';
                    }
                  }

                  if (newDate != null) notifier.setDate(newDate);
                  if (newCity.isNotEmpty) {
                    _cityController.text = newCity;
                    notifier.setCity(newCity);
                  }
                  if (newCountry.isNotEmpty) {
                    _countryController.text = newCountry;
                    notifier.setCountry(newCountry);
                  }

                  await _batchUpdate(
                    isEditorial: true,
                    city: _cityController.text,
                    country: _countryController.text,
                    date: ref.read(editorialStateProvider).date,
                  );
                } else {
                  // turned off: clear fields
                  _cityController.clear();
                  _countryController.clear();
                  notifier.setCity('');
                  notifier.setCountry('');
                  notifier.setDate(null);
                  // this explicitly sets fields to null/empty in DB and removes the tag
                  await _batchUpdate(
                    isEditorial: false,
                    city: '',
                    country: '',
                    date: null,
                  );
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (editorial.isEditorial) ...[
          const SizedBox(height: 12),
          const GenerationFormLabel('LOCATION'),
          const SizedBox(height: 6),
          // City autocomplete
          Semantics(
            container: true,
            child: RawAutocomplete<String>(
              textEditingController: _cityController,
              focusNode: _cityFocusNode,
              optionsBuilder: (v) {
                if (v.text.isEmpty) return cities;
                return cities.where(
                  (c) => c.toLowerCase().contains(v.text.toLowerCase()),
                );
              },
              onSelected: (selection) {
                notifier.setCity(selection);
                if (_countryController.text.isEmpty) {
                  final match = savedLocations.firstWhere(
                    (loc) => loc.startsWith('$selection|'),
                    orElse: () => '',
                  );
                  if (match.isNotEmpty) {
                    final countryVal = match.split('|').last;
                    _countryController.text = countryVal;
                    notifier.setCountry(countryVal);
                  }
                }
                _batchUpdate(city: selection, country: _countryController.text);
              },
              fieldViewBuilder: (context, controller, focusNode, _) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: (val) {
                    notifier.setCity(val);
                    _batchUpdate(city: val);
                  },
                  decoration: _inputDecor(context).copyWith(hintText: 'Город'),
                  style: const TextStyle(fontSize: 13),
                );
              },
              optionsViewBuilder:
                  (context, onSelected, options) => _autocompleteOptionsView(
                    context,
                    onSelected,
                    options,
                    colorScheme,
                  ),
            ),
          ),
          const SizedBox(height: 6),
          // Country autocomplete
          Semantics(
            container: true,
            child: RawAutocomplete<String>(
              textEditingController: _countryController,
              focusNode: _countryFocusNode,
              optionsBuilder: (v) {
                if (v.text.isEmpty) return countries;
                return countries.where(
                  (c) => c.toLowerCase().contains(v.text.toLowerCase()),
                );
              },
              onSelected: (selection) {
                notifier.setCountry(selection);
                _batchUpdate(country: selection);
              },
              fieldViewBuilder: (context, controller, focusNode, _) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: (val) {
                    notifier.setCountry(val);
                    _batchUpdate(country: val);
                  },
                  decoration: _inputDecor(
                    context,
                  ).copyWith(hintText: 'Страна / Штат'),
                  style: const TextStyle(fontSize: 13),
                );
              },
              optionsViewBuilder:
                  (context, onSelected, options) => _autocompleteOptionsView(
                    context,
                    onSelected,
                    options,
                    colorScheme,
                  ),
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            button: true,
            label:
                editorial.date == null
                    ? 'Указать дату съёмки'
                    : 'Дата съёмки ${formatEditorialDate(editorial.date!)}',
            child: SingleClickArea(
              onTap: () => _pickShootDate(notifier),
              child: InputDecorator(
                decoration: _inputDecor(context),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        editorial.date == null
                            ? 'Дата съёмки'
                            : formatEditorialDate(editorial.date!),
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              editorial.date == null
                                  ? colorScheme.onSurface.withValues(
                                    alpha: 0.45,
                                  )
                                  : colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],

        const SizedBox(height: 16),
      ],
    );
  }
}

/// Pill-shaped toggle button used for AI / Editorial tag selection.
class _TagToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  const _TagToggle({
    required this.label,
    required this.icon,
    required this.color,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? color : color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? color : color.withValues(alpha: 0.35),
            width: 1,
          ),
          boxShadow:
              isActive
                  ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                  : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: isActive ? Colors.white : color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
