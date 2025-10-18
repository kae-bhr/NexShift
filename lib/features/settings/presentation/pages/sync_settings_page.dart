import 'package:flutter/material.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Page de configuration de la synchronisation
class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  bool _autoSync = true;
  bool _syncOnWifiOnly = false;
  bool _syncCalendar = true;
  bool _syncReplacements = true;
  bool _syncNotifications = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoSync = prefs.getBool('sync_auto') ?? true;
      _syncOnWifiOnly = prefs.getBool('sync_wifi_only') ?? false;
      _syncCalendar = prefs.getBool('sync_calendar') ?? true;
      _syncReplacements = prefs.getBool('sync_replacements') ?? true;
      _syncNotifications = prefs.getBool('sync_notifications') ?? true;
      _isLoading = false;
    });
  }

  Future<void> _savePreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _performManualSync() async {
    // Afficher un indicateur de chargement
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 16),
            Text('Synchronisation en cours...'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );

    // Simuler une synchronisation (à remplacer par la vraie logique)
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ Synchronisation terminée'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Synchronisation',
        bottomColor: KColors.appNameColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Paramètres généraux
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Paramètres généraux',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Synchronisation automatique'),
                        subtitle: const Text(
                          'Synchroniser automatiquement les données',
                        ),
                        value: _autoSync,
                        onChanged: (value) {
                          setState(() => _autoSync = value);
                          _savePreference('sync_auto', value);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Wi-Fi uniquement'),
                        subtitle: const Text(
                          'Synchroniser seulement en Wi-Fi pour économiser les données',
                        ),
                        value: _syncOnWifiOnly,
                        onChanged: (value) {
                          setState(() => _syncOnWifiOnly = value);
                          _savePreference('sync_wifi_only', value);
                        },
                      ),
                    ],
                  ),
                ),

                // Types de données à synchroniser
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Données à synchroniser',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Calendrier'),
                        subtitle: const Text('Synchroniser les horaires de garde'),
                        value: _syncCalendar,
                        onChanged: (value) {
                          setState(() => _syncCalendar = value);
                          _savePreference('sync_calendar', value);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Remplacements'),
                        subtitle: const Text('Synchroniser les demandes de remplacement'),
                        value: _syncReplacements,
                        onChanged: (value) {
                          setState(() => _syncReplacements = value);
                          _savePreference('sync_replacements', value);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Notifications'),
                        subtitle: const Text('Synchroniser l\'historique des notifications'),
                        value: _syncNotifications,
                        onChanged: (value) {
                          setState(() => _syncNotifications = value);
                          _savePreference('sync_notifications', value);
                        },
                      ),
                    ],
                  ),
                ),

                // Synchronisation manuelle
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ListTile(
                    leading: const Icon(Icons.sync, color: Colors.blue),
                    title: const Text('Synchroniser maintenant'),
                    subtitle: const Text('Forcer une synchronisation immédiate'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _performManualSync,
                  ),
                ),

                // Informations
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                              size: 20,
                              color: Colors.blue[700],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'À propos de la synchronisation',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[700],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'La synchronisation permet de garder vos données à jour entre l\'application et le serveur. '
                          'Les données sont automatiquement synchronisées en temps réel grâce à Firebase Firestore.\n\n'
                          'En mode hors ligne, vos modifications sont conservées localement et seront automatiquement '
                          'synchronisées dès que vous serez de nouveau connecté.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
