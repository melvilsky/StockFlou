import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import '../../core/theme/app_theme.dart';
import '../../core/state/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _apiKeyController;
  late TextEditingController _workspaceController;
  late TextEditingController _newCityController;
  late TextEditingController _newCountryController;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _workspaceController = TextEditingController();
    _newCityController = TextEditingController();
    _newCountryController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = ref.watch(settingsProvider);
    state.whenData((s) {
      if (_apiKeyController.text.isEmpty && s.apiKey != null) {
        _apiKeyController.text = s.apiKey!;
      }
      if (_workspaceController.text.isEmpty && s.workspacePath != null) {
        _workspaceController.text = s.workspacePath!;
      }
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _workspaceController.dispose();
    _newCityController.dispose();
    _newCountryController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    ref.read(settingsProvider.notifier).setApiKey(_apiKeyController.text);
    ref
        .read(settingsProvider.notifier)
        .setWorkspacePath(_workspaceController.text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Settings saved successfully.'),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickWorkspace() async {
    final String? directoryPath = await getDirectoryPath();
    if (directoryPath != null) {
      setState(() {
        _workspaceController.text = directoryPath;
      });
    }
  }

  void _addLocation() {
    final city = _newCityController.text.trim();
    final country = _newCountryController.text.trim();
    if (city.isNotEmpty || country.isNotEmpty) {
      ref.read(settingsProvider.notifier).addLocation(city, country);
      _newCityController.clear();
      _newCountryController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final settingsState = ref.watch(settingsProvider);
    final savedLocations = settingsState.value?.savedLocations ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: colorScheme.outline, height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'API Configuration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Setup your stock keywords generation token from aistockkeywords.com',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI Stock Keywords API Key',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: colorScheme.outlineVariant,
                      hintText: 'Enter your API key here',
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: colorScheme.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: colorScheme.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Workspace Folder',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _workspaceController,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: colorScheme.outlineVariant,
                            hintText: 'Select your workflow folder',
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: colorScheme.outline,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        onPressed: _pickWorkspace,
                        icon: const Icon(Icons.folder_open),
                        style: IconButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _saveSettings,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Save Settings'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            const Text(
              'Editorial Locations',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Manage your saved editorial locations (City and Country/State)',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: savedLocations.map((loc) {
                      final parts = loc.split('|');
                      final display = parts.join(', ');
                      return InputChip(
                        label: Text(display),
                        onDeleted: () {
                          ref
                              .read(settingsProvider.notifier)
                              .removeLocation(loc);
                        },
                      );
                    }).toList(),
                  ),
                  if (savedLocations.isNotEmpty) const SizedBox(height: 24),
                  const Text(
                    'Add New Location',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newCityController,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: colorScheme.outlineVariant,
                            hintText: 'City',
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: colorScheme.outline,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _newCountryController,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: colorScheme.outlineVariant,
                            hintText: 'Country / State',
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: colorScheme.outline,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _addLocation,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
