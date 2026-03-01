import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/state/settings_provider.dart';
import '../../models/stock_credentials.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _apiKeyController;
  late TextEditingController _newCityController;
  late TextEditingController _newCountryController;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
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
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _newCityController.dispose();
    _newCountryController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    ref.read(settingsProvider.notifier).setApiKey(_apiKeyController.text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Settings saved successfully.'),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
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

  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
      body: Row(
        children: [
          // Sidebar Tabs
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            backgroundColor: colorScheme.surface,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('General'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.cloud_upload_outlined),
                selectedIcon: Icon(Icons.cloud_upload),
                label: Text('Stocks'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // Content Area
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [_buildGeneralTab(context), _buildStocksTab(context)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final settingsState = ref.watch(settingsProvider);
    final savedLocations = settingsState.value?.savedLocations ?? [];

    return SingleChildScrollView(
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
                        ref.read(settingsProvider.notifier).removeLocation(loc);
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
                          hintText: 'City (e.g. New York)',
                          filled: true,
                          fillColor: colorScheme.outlineVariant,
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
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _newCountryController,
                        decoration: InputDecoration(
                          hintText: 'Country or State (e.g. NY)',
                          filled: true,
                          fillColor: colorScheme.outlineVariant,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: colorScheme.outline),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: colorScheme.primary),
                          ),
                        ),
                        onSubmitted: (_) => _addLocation(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilledButton(
                      onPressed: _addLocation,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 24,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStocksTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final settingsState = ref.watch(settingsProvider);
    final adobe =
        settingsState.value?.adobeCredentials ?? const StockCredentials();
    final shutter =
        settingsState.value?.shutterstockCredentials ??
        const StockCredentials();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Stock Platforms',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Configure your FTP/SFTP upload credentials for automated submissions.',
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 32),

          // Adobe Stock Card
          _buildStockCredentialCard(
            context: context,
            title: 'Adobe Stock (SFTP)',
            description:
                'Hostname is usually sftp.contributor.adobestock.com. Username is your Contributor ID. You must generate a new SFTP password in the Contributor portal.',
            credentials: adobe,
            onSave: (creds) {
              ref.read(settingsProvider.notifier).saveAdobeCredentials(creds);
              _showSaveSuccess();
            },
          ),

          const SizedBox(height: 32),

          // Shutterstock Card
          _buildStockCredentialCard(
            context: context,
            title: 'Shutterstock (FTPS)',
            description:
                'Use FTPS for secure connections. Hostname is ftps.shutterstock.com. Username is your contributor email or username. Password is the same as your login password.',
            credentials: shutter,
            onSave: (creds) {
              ref
                  .read(settingsProvider.notifier)
                  .saveShutterstockCredentials(creds);
              _showSaveSuccess();
            },
          ),
        ],
      ),
    );
  }

  void _showSaveSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Settings saved successfully.'),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildStockCredentialCard({
    required BuildContext context,
    required String title,
    required String description,
    required StockCredentials credentials,
    required ValueChanged<StockCredentials> onSave,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    // Local controllers just for this card
    final hostCtrl = TextEditingController(text: credentials.hostname);
    final userCtrl = TextEditingController(text: credentials.username);
    final passCtrl = TextEditingController(text: credentials.password);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),

          // Hostname
          const Text('Hostname', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextField(
            controller: hostCtrl,
            decoration: _getOutlineInputDecoration(
              context,
              'e.g. sftp.contributor.adobestock.com',
            ),
          ),
          const SizedBox(height: 16),

          // Username
          const Text(
            'Username / ID',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: userCtrl,
            decoration: _getOutlineInputDecoration(context, 'e.g. 12345678'),
          ),
          const SizedBox(height: 16),

          // Password
          const Text('Password', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextField(
            controller: passCtrl,
            obscureText: true,
            decoration: _getOutlineInputDecoration(context, 'Enter password'),
          ),
          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: () {
              final updated = StockCredentials(
                hostname: hostCtrl.text.trim(),
                username: userCtrl.text.trim(),
                password: passCtrl.text.trim(),
              );
              onSave(updated);
            },
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save Credentials'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _getOutlineInputDecoration(
    BuildContext context,
    String hint,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      filled: true,
      fillColor: colorScheme.outlineVariant,
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.primary),
      ),
    );
  }
}
