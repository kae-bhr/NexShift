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
                        activeTrackColor: KColors.appNameColor.withValues(alpha: 0.5),
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
                        activeTrackColor: KColors.appNameColor.withValues(alpha: 0.5),
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
                        title: const Text('Demandes de remplacement'),
                        subtitle: const Text(
                          'Notifications quand quelqu\'un cherche un remplaçant',
                        ),
                        value: _replacementRequestsEnabled,
                        activeThumbColor: KColors.appNameColor,
                        activeTrackColor: KColors.appNameColor.withValues(alpha: 0.5),
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
                        activeThumbColor: KColors.appNameColor,
                        activeTrackColor: KColors.appNameColor.withValues(alpha: 0.5),
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
                        activeThumbColor: KColors.appNameColor,
                        activeTrackColor: KColors.appNameColor.withValues(alpha: 0.5),
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
                        activeThumbColor: KColors.appNameColor,
                        activeTrackColor: KColors.appNameColor.withValues(alpha: 0.5),
                        onChanged: (value) {
                          setState(() => _replacementAssignedEnabled = value);
                          _savePreference('notif_replacement_assigned', value);
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

    final isChiefOrLeader =
        user.status == KConstants.statusChief ||
        user.status == KConstants.statusLeader ||
        user.admin;

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

          // Alerte personnelle avant astreinte
          _buildAlertTile(
            title: 'Rappel avant astreinte',
            subtitle: 'Recevoir une notification avant le début de votre garde',
            enabled: user.personalAlertEnabled,
            hours: user.personalAlertBeforeShiftHours,
            onEnabledChanged: (value) => _updateUserAlertSetting(
              user.copyWith(personalAlertEnabled: value),
            ),
            onHoursChanged: (hours) => _updateUserAlertSetting(
              user.copyWith(personalAlertBeforeShiftHours: hours),
            ),
          ),

          // Alertes chef (uniquement si chief/leader/admin)
          if (isChiefOrLeader) ...[
            const Divider(height: 1),
            _buildAlertTile(
              title: 'Alerte changements équipe',
              subtitle:
                  'Notification si un remplacement est prévu dans votre équipe',
              enabled: user.chiefAlertEnabled,
              hours: user.chiefAlertBeforeShiftHours,
              onEnabledChanged: (value) => _updateUserAlertSetting(
                user.copyWith(chiefAlertEnabled: value),
              ),
              onHoursChanged: (hours) => _updateUserAlertSetting(
                user.copyWith(chiefAlertBeforeShiftHours: hours),
              ),
            ),
            const Divider(height: 1),
            _buildAnomalyAlertTile(
              title: 'Alerte anomalies planning',
              subtitle:
                  'Notification si une astreinte future n\'a pas assez d\'agents',
              enabled: user.anomalyAlertEnabled,
              days: user.anomalyAlertDaysBefore,
              onEnabledChanged: (value) => _updateUserAlertSetting(
                user.copyWith(anomalyAlertEnabled: value),
              ),
              onDaysChanged: (days) => _updateUserAlertSetting(
                user.copyWith(anomalyAlertDaysBefore: days),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAlertTile({
    required String title,
    required String subtitle,
    required bool enabled,
    required int hours,
    required ValueChanged<bool> onEnabledChanged,
    required ValueChanged<int> onHoursChanged,
  }) {
    return Column(
      children: [
        SwitchListTile(
          title: Text(title),
          subtitle: Text(subtitle),
          value: enabled,
          activeThumbColor: KColors.appNameColor,
          activeTrackColor: KColors.appNameColor.withValues(alpha: 0.5),
          onChanged: onEnabledChanged,
        ),
        if (enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Text('Délai : '),
                DropdownButton<int>(
                  value: hours,
                  underline: const SizedBox.shrink(),
                  items: [1, 2, 3, 6, 12, 24].map((h) {
                    return DropdownMenuItem(
                      value: h,
                      child: Text('$h heure${h > 1 ? 's' : ''} avant'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) onHoursChanged(value);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAnomalyAlertTile({
    required String title,
    required String subtitle,
    required bool enabled,
    required int days,
    required ValueChanged<bool> onEnabledChanged,
    required ValueChanged<int> onDaysChanged,
  }) {
    return Column(
      children: [
        SwitchListTile(
          title: Text(title),
          subtitle: Text(subtitle),
          value: enabled,
          activeThumbColor: KColors.appNameColor,
          activeTrackColor: KColors.appNameColor.withValues(alpha: 0.5),
          onChanged: onEnabledChanged,
        ),
        if (enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Text('Période : '),
                DropdownButton<int>(
                  value: days,
                  underline: const SizedBox.shrink(),
                  items: [7, 14, 21, 30].map((d) {
                    return DropdownMenuItem(
                      value: d,
                      child: Text('$d jours à l\'avance'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) onDaysChanged(value);
                  },
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
