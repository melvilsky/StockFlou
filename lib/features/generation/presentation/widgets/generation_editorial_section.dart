import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/geocoding_service.dart';
import '../../../../core/services/metadata_service.dart';
import '../../../../core/state/files_provider.dart';
import '../../../../core/state/settings_provider.dart';
import '../../../../core/widgets/single_click_area.dart';
import '../../../../models/app_file.dart';
import 'generation_widgets.dart';

/// Editorial metadata section: checkbox + city / country / date fields.
/// Owns its own form controllers so the parent doesn't need to manage them.
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
  bool _isEditorial = false;
  final _cityController = TextEditingController();
  final _countryController = TextEditingController();
  final _cityFocusNode = FocusNode();
  final _countryFocusNode = FocusNode();
  DateTime? _editorialDate;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void didUpdateWidget(GenerationEditorialSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync state when selected file changes
    final newFile = widget.selectedExistingFile;
    final oldFile = oldWidget.selectedExistingFile;
    if (newFile?.id != oldFile?.id) {
      _isEditorial = newFile?.isEditorial ?? false;
      _cityController.text = newFile?.editorialCity ?? '';
      _countryController.text = newFile?.editorialCountry ?? '';
      final ms = newFile?.editorialDate;
      _editorialDate = ms != null
          ? DateTime.fromMillisecondsSinceEpoch(ms)
          : null;
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

  String _formatDate(DateTime date) =>
      '${_months[date.month - 1]} ${date.day} ${date.year}';

  Future<void> _batchUpdate({
    bool? isEditorial,
    String? city,
    String? country,
    DateTime? date,
  }) async {
    final allFiles = ref.read(filesProvider).value ?? [];
    for (final path in widget.selectedPaths) {
      final idx = allFiles.indexWhere((f) => f.path == path);
      if (idx == -1) continue;
      final f = allFiles[idx];
      final updated = AppFile(
        id: f.id,
        path: f.path,
        filename: f.filename,
        metadataTitle: f.metadataTitle,
        metadataDescription: f.metadataDescription,
        metadataKeywords: f.metadataKeywords,
        isEditorial: isEditorial ?? f.isEditorial,
        editorialCity: city ?? f.editorialCity,
        editorialCountry: country ?? f.editorialCountry,
        editorialDate: date != null
            ? date.millisecondsSinceEpoch
            : f.editorialDate,
        createdAt: f.createdAt,
      );
      await ref.read(filesProvider.notifier).updateFile(updated);
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
    final savedLocations =
        ref.watch(settingsProvider).value?.savedLocations ?? [];
    final cities = savedLocations
        .map((e) => e.split('|').first)
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    final countries = savedLocations
        .map((e) => e.split('|').length > 1 ? e.split('|').last : '')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Editorial checkbox
        Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _isEditorial,
                onChanged: (value) async {
                  setState(() => _isEditorial = value ?? false);
                  await _batchUpdate(isEditorial: _isEditorial);
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Эдиториал',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),

        if (_isEditorial) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const GenerationFormLabel('LOCATION'),
              const Spacer(),
              SizedBox(
                height: 28,
                child: SingleClickArea(
                  onTap: () async {
                    final filePath =
                        widget.selectedExistingFile?.path ??
                        widget.selectedLocalInspectorPath;
                    if (filePath == null) return;
                    final exif = await MetadataService.readExifLocationAndDate(
                      filePath,
                    );
                    if (exif.date != null) {
                      setState(() => _editorialDate = exif.date);
                    }
                    if (exif.lat != null && exif.lon != null) {
                      final geo = await GeocodingService.resolve(
                        exif.lat,
                        exif.lon,
                      );
                      setState(() {
                        if (geo.city != null) {
                          _cityController.text = geo.city!;
                        }
                        if (geo.country != null || geo.state != null) {
                          _countryController.text =
                              geo.state ?? geo.country ?? '';
                        }
                      });
                      await _batchUpdate(
                        city: _cityController.text,
                        country: _countryController.text,
                        date: _editorialDate,
                      );
                    }
                  },
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.gps_fixed, size: 14),
                    label: const Text('Авто', style: TextStyle(fontSize: 11)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // City autocomplete
          RawAutocomplete<String>(
            textEditingController: _cityController,
            focusNode: _cityFocusNode,
            optionsBuilder: (v) {
              if (v.text.isEmpty) return cities;
              return cities.where(
                (c) => c.toLowerCase().contains(v.text.toLowerCase()),
              );
            },
            onSelected: (selection) {
              if (_countryController.text.isEmpty) {
                final match = savedLocations.firstWhere(
                  (loc) => loc.startsWith('$selection|'),
                  orElse: () => '',
                );
                if (match.isNotEmpty) {
                  _countryController.text = match.split('|').last;
                }
              }
              _batchUpdate(city: selection, country: _countryController.text);
            },
            fieldViewBuilder: (context, controller, focusNode, _) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: (val) => _batchUpdate(city: val),
                decoration: _inputDecor(context).copyWith(hintText: 'Город'),
                style: const TextStyle(fontSize: 13),
              );
            },
            optionsViewBuilder: (context, onSelected, options) =>
                _autocompleteOptionsView(
                  context,
                  onSelected,
                  options,
                  colorScheme,
                ),
          ),
          const SizedBox(height: 6),
          // Country autocomplete
          RawAutocomplete<String>(
            textEditingController: _countryController,
            focusNode: _countryFocusNode,
            optionsBuilder: (v) {
              if (v.text.isEmpty) return countries;
              return countries.where(
                (c) => c.toLowerCase().contains(v.text.toLowerCase()),
              );
            },
            onSelected: (selection) => _batchUpdate(country: selection),
            fieldViewBuilder: (context, controller, focusNode, _) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: (val) => _batchUpdate(country: val),
                decoration: _inputDecor(
                  context,
                ).copyWith(hintText: 'Страна / Штат'),
                style: const TextStyle(fontSize: 13),
              );
            },
            optionsViewBuilder: (context, onSelected, options) =>
                _autocompleteOptionsView(
                  context,
                  onSelected,
                  options,
                  colorScheme,
                ),
          ),
          if (_editorialDate != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDate(_editorialDate!),
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],

        const SizedBox(height: 16),
      ],
    );
  }
}
