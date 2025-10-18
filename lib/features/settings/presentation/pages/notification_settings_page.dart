import 'package:flutter/material.dart';
import 'package:nexshift_app/core/services/push_notification_service.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Page de configuration des notifications
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _replacementRequestsEnabled = true;
  bool _replacementFoundEnabled = true;
  bool _replacementAssignedEnabled = true;
  bool _availabilityRequestsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _replacementRequestsEnabled =
          prefs.getBool('notif_replacement_requests') ?? true;
      _replacementFoundEnabled =
          prefs.getBool('notif_replacement_found') ?? true;
      _replacementAssignedEnabled =
          prefs.getBool('notif_replacement_assigned') ?? true;
      _availabilityRequestsEnabled =
          prefs.getBool('notif_availability_requests') ?? true;
      _soundEnabled = prefs.getBool('notif_sound') ?? true;
      _vibrationEnabled = prefs.getBool('notif_vibration') ?? true;
      _isLoading = false;
    });
  }

  Future<void> _savePreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Notifications',
        bottomColor: KColors.appNameColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Types de notifications
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Types de notifications',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Demandes de remplacement'),
                        subtitle: const Text(
                          'Notifications quand quelqu\'un cherche un remplaçant',
                        ),
                        value: _replacementRequestsEnabled,
                        onChanged: (value) {
                          setState(() => _replacementRequestsEnabled = value);
                          _savePreference('notif_replacement_requests', value);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Demandes de disponibilité'),
                        subtitle: const Text(
                          'Notifications pour les recherches d\'agents disponibles',
                        ),
                        value: _availabilityRequestsEnabled,
                        onChanged: (value) {
                          setState(() => _availabilityRequestsEnabled = value);
                          _savePreference('notif_availability_requests', value);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Remplaçant trouvé'),
                        subtitle: const Text(
                          'Notifications quand votre remplacement est accepté',
                        ),
                        value: _replacementFoundEnabled,
                        onChanged: (value) {
                          setState(() => _replacementFoundEnabled = value);
                          _savePreference('notif_replacement_found', value);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Remplacement assigné'),
                        subtitle: const Text(
                          'Notifications pour les chefs de garde',
                        ),
                        value: _replacementAssignedEnabled,
                        onChanged: (value) {
                          setState(() => _replacementAssignedEnabled = value);
                          _savePreference('notif_replacement_assigned', value);
                        },
                      ),
                    ],
                  ),
                ),

                // Paramètres de notification
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Paramètres',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Son'),
                        subtitle: const Text('Jouer un son pour les notifications'),
                        value: _soundEnabled,
                        onChanged: (value) {
                          setState(() => _soundEnabled = value);
                          _savePreference('notif_sound', value);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Vibration'),
                        subtitle: const Text('Vibrer lors des notifications'),
                        value: _vibrationEnabled,
                        onChanged: (value) {
                          setState(() => _vibrationEnabled = value);
                          _savePreference('notif_vibration', value);
                        },
                      ),
                    ],
                  ),
                ),

                // Test des notifications
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ListTile(
                    leading: const Icon(Icons.send, color: Colors.blue),
                    title: const Text('Envoyer une notification de test'),
                    subtitle: const Text('Tester les paramètres actuels'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      PushNotificationService().showLocalNotification(
                        title: '🔔 Notification de test',
                        body: 'Les notifications fonctionnent correctement !',
                        payload: {'type': 'test'},
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✓ Notification de test envoyée'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
