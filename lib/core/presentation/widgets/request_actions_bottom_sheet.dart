import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/presentation/widgets/unified_request_tile/unified_tile_enums.dart';

/// BottomSheet d'actions pour les demandes dans "Mes demandes"
/// Permet de relancer les notifications ou supprimer la demande
class RequestActionsBottomSheet extends StatelessWidget {
  /// Type de demande (pour l'icône)
  final UnifiedRequestType requestType;

  /// Nom de l'initiateur de la demande
  final String initiatorName;

  /// Équipe de l'initiateur
  final String? team;

  /// Station/caserne
  final String? station;

  /// Date/heure de début
  final DateTime startTime;

  /// Date/heure de fin
  final DateTime endTime;

  /// Callback pour relancer les notifications (reçoit le context pour afficher le dialog)
  final Future<void> Function(BuildContext context)? onResendNotifications;

  /// Callback pour supprimer la demande
  final VoidCallback? onDelete;

  /// Nombre d'utilisateurs à notifier (pour le dialog de confirmation)
  final int usersToNotifyCount;

  const RequestActionsBottomSheet({
    super.key,
    required this.requestType,
    required this.initiatorName,
    this.team,
    this.station,
    required this.startTime,
    required this.endTime,
    this.onResendNotifications,
    this.onDelete,
    this.usersToNotifyCount = 0,
  });

  /// Affiche le BottomSheet
  static void show({
    required BuildContext context,
    required UnifiedRequestType requestType,
    required String initiatorName,
    String? team,
    String? station,
    required DateTime startTime,
    required DateTime endTime,
    VoidCallback? onResendNotifications,
    VoidCallback? onDelete,
    int usersToNotifyCount = 0,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => RequestActionsBottomSheet(
        requestType: requestType,
        initiatorName: initiatorName,
        team: team,
        station: station,
        startTime: startTime,
        endTime: endTime,
        onResendNotifications: onResendNotifications != null
            ? (ctx) async {
                Navigator.pop(ctx);
                // Afficher le dialog de confirmation
                final confirmed = await _showResendConfirmationDialog(
                  ctx,
                  usersToNotifyCount,
                );
                if (confirmed == true) {
                  onResendNotifications();
                }
              }
            : null,
        onDelete: onDelete,
        usersToNotifyCount: usersToNotifyCount,
      ),
    );
  }

  /// Affiche le dialog de confirmation pour la relance des notifications
  static Future<bool?> _showResendConfirmationDialog(
    BuildContext context,
    int usersToNotifyCount,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Expanded(child: Text('Relancer les notifications')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Voulez-vous relancer une notification à tous les agents qui n\'ont pas encore répondu ?',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.people, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    usersToNotifyCount > 0
                        ? '$usersToNotifyCount agent${usersToNotifyCount > 1 ? 's' : ''} ser${usersToNotifyCount > 1 ? 'ont' : 'a'} notifié${usersToNotifyCount > 1 ? 's' : ''}'
                        : 'Les agents concernés seront notifiés',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Relancer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade600,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Retourne l'icône correspondant au type de demande
  IconData _getRequestTypeIcon() {
    switch (requestType) {
      case UnifiedRequestType.automaticReplacement:
        return Icons.autorenew;
      case UnifiedRequestType.sosReplacement:
        return Icons.emergency;
      case UnifiedRequestType.manualReplacement:
        return Icons.person_search;
      case UnifiedRequestType.exchange:
        return Icons.swap_horiz;
    }
  }

  /// Retourne la couleur correspondant au type de demande
  Color _getRequestTypeColor() {
    switch (requestType) {
      case UnifiedRequestType.automaticReplacement:
        return Colors.blue;
      case UnifiedRequestType.sosReplacement:
        return Colors.red;
      case UnifiedRequestType.manualReplacement:
        return Colors.purple;
      case UnifiedRequestType.exchange:
        return Colors.teal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getRequestTypeColor();
    final startFormatted = DateFormat('dd/MM HH:mm').format(startTime);
    final endFormatted = DateFormat('dd/MM HH:mm').format(endTime);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête avec icône et nom
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getRequestTypeIcon(),
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  initiatorName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Informations détaillées
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Équipe
                if (team != null && team!.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(Icons.groups, color: Colors.grey[700], size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Équipe $team',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                // Caserne
                if (station != null && station!.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.grey[700], size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          station!,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                // Horaires
                Row(
                  children: [
                    Icon(Icons.access_time, color: Colors.grey[700], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$startFormatted → $endFormatted',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Bouton Relancer les notifications
          if (onResendNotifications != null) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => onResendNotifications!(context),
                icon: Icon(Icons.notifications_active, color: Colors.orange.shade600),
                label: Text(
                  'Relancer les notifications',
                  style: TextStyle(color: Colors.orange.shade600),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.orange.shade600),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Bouton Supprimer la demande
          if (onDelete != null) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onDelete!();
                },
                icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                label: Text(
                  'Supprimer la demande',
                  style: TextStyle(color: Colors.red.shade400),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade400),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Bouton Fermer
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ),
        ],
      ),
    );
  }
}
