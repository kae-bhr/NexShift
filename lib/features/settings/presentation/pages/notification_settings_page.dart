import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
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
  bool _notifReplacementEnabled = true;
  bool _notifExchangeEnabled = true;
  bool _notifQueryEnabled = true;
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
      _notifReplacementEnabled = prefs.getBool('notif_replacement') ?? true;
      _notifExchangeEnabled = prefs.getBool('notif_exchange') ?? true;
      _notifQueryEnabled = prefs.getBool('notif_query') ?? true;
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
        bottomColor: const Color.fromARGB(255, 5, 5, 5),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Paramètres de notification
                Card(
                  margin: const EdgeInsets.all(16),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Paramètres',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Son'),
                        subtitle: const Text(
                          'Jouer un son pour les notifications',
                        ),
                        value: _soundEnabled,
                        activeThumbColor: KColors.appNameColor,
                        activeTrackColor: KColors.appNameColor.withValues(
                          alpha: 0.5,
                        ),
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
                        activeThumbColor: KColors.appNameColor,
                        activeTrackColor: KColors.appNameColor.withValues(
                          alpha: 0.5,
                        ),
                        onChanged: (value) {
                          setState(() => _vibrationEnabled = value);
                          _savePreference('notif_vibration', value);
                        },
                      ),
                    ],
                  ),
                ),

                // Types de notifications
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Types de notifications',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Remplacements'),
                        subtitle: const Text(
                          'Demandes, acceptations, validations et assignations de remplacement',
                        ),
                        value: _notifReplacementEnabled,
                        activeThumbColor: KColors.appNameColor,
                        activeTrackColor: KColors.appNameColor.withValues(
                          alpha: 0.5,
                        ),
                        onChanged: (value) {
                          setState(() => _notifReplacementEnabled = value);
                          _savePreference('notif_replacement', value);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Échanges d\'astreintes'),
                        subtitle: const Text(
                          'Propositions, validations et conclusions d\'échanges',
                        ),
                        value: _notifExchangeEnabled,
                        activeThumbColor: KColors.appNameColor,
                        activeTrackColor: KColors.appNameColor.withValues(
                          alpha: 0.5,
                        ),
                        onChanged: (value) {
                          setState(() => _notifExchangeEnabled = value);
                          _savePreference('notif_exchange', value);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Recherches d\'agents'),
                        subtitle: const Text(
                          'Demandes de disponibilité et réponses aux recherches',
                        ),
                        value: _notifQueryEnabled,
                        activeThumbColor: KColors.appNameColor,
                        activeTrackColor: KColors.appNameColor.withValues(
                          alpha: 0.5,
                        ),
                        onChanged: (value) {
                          setState(() => _notifQueryEnabled = value);
                          _savePreference('notif_query', value);
                        },
                      ),
                    ],
                  ),
                ),

                // Alertes proactives (stockées dans le profil utilisateur)
                _buildProactiveAlertsSection(context),

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

  Widget _buildProactiveAlertsSection(BuildContext context) {
    final user = userNotifier.value;
    if (user == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.schedule_send, color: Colors.deepPurple),
                const SizedBox(width: 8),
                Text(
                  'Alertes proactives',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _buildDailyReminderTile(user: user, context: context),
          if (user.admin) ...[
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('Adhésions caserne'),
              subtitle: const Text(
                'Demandes d\'adhésion à votre caserne',
              ),
              value: user.membershipAlertEnabled,
              activeThumbColor: KColors.appNameColor,
              activeTrackColor: KColors.appNameColor.withValues(alpha: 0.5),
              onChanged: (value) => _updateUserAlertSetting(
                user.copyWith(membershipAlertEnabled: value),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDailyReminderTile({
    required User user,
    required BuildContext context,
  }) {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Rappel quotidien d\'astreinte'),
          subtitle: const Text(
            'Notification quotidienne si vous êtes de garde dans les 24h',
          ),
          value: user.personalAlertEnabled,
          activeThumbColor: KColors.appNameColor,
          activeTrackColor: KColors.appNameColor.withValues(alpha: 0.5),
          onChanged: (value) => _updateUserAlertSetting(
            user.copyWith(personalAlertEnabled: value),
          ),
        ),
        if (user.personalAlertEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.access_time, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Text('Heure d\'envoi : '),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                        hour: user.personalAlertHour,
                        minute: 0,
                      ),
                      builder: (context, child) {
                        return MediaQuery(
                          data: MediaQuery.of(
                            context,
                          ).copyWith(alwaysUse24HourFormat: true),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      _updateUserAlertSetting(
                        user.copyWith(personalAlertHour: picked.hour),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      '${user.personalAlertHour.toString().padLeft(2, '0')}:00',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: KColors.appNameColor,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _updateUserAlertSetting(User updatedUser) async {
    try {
      final repo = UserRepository();
      await repo.upsert(updatedUser);
      await UserStorageHelper.saveUser(updatedUser);
      userNotifier.value = updatedUser;
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
