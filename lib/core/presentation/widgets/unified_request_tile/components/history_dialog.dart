import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Validation d'une équipe dans l'historique d'un échange
class TeamValidationEntry {
  /// Identifiant de l'équipe (ex. "N", "J")
  final String teamId;

  /// Nom du chef validateur (null → "un chef")
  final String? validatorName;

  /// Horodatage de la validation
  final DateTime validatedAt;

  const TeamValidationEntry({
    required this.teamId,
    this.validatorName,
    required this.validatedAt,
  });
}

/// Données à afficher dans le dialog d'historique d'une demande
class HistoryDialogData {
  /// Horodatage de la demande (créée par le futur remplacé)
  final DateTime createdAt;

  /// Horodatage de l'acceptation (null → "Inconnu")
  final DateTime? acceptedAt;

  /// Horodatage de la validation chef (null → ligne non affichée)
  /// Utilisé pour les remplacements. Ignoré si [teamValidations] est non-null.
  final DateTime? validatedAt;

  /// Nom du validateur chef (null → "un chef")
  /// Utilisé pour les remplacements. Ignoré si [teamValidations] est non-null.
  final String? validatorName;

  /// Validations par équipe (échanges uniquement).
  /// Si non-null, remplace [validatedAt]/[validatorName] dans la timeline.
  final List<TeamValidationEntry>? teamValidations;

  /// Label du type de demande (ex. "Remplacement automatique", "Échange de garde")
  final String requestTypeLabel;

  const HistoryDialogData({
    required this.createdAt,
    this.acceptedAt,
    this.validatedAt,
    this.validatorName,
    this.teamValidations,
    required this.requestTypeLabel,
  });
}

/// Affiche le dialog d'historique d'une demande
void showHistoryDialog(BuildContext context, HistoryDialogData data) {
  showDialog<void>(
    context: context,
    builder: (context) => _HistoryDialog(data: data),
  );
}

class _HistoryDialog extends StatelessWidget {
  final HistoryDialogData data;

  const _HistoryDialog({required this.data});

  static final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  String _format(DateTime? dt) {
    if (dt == null) return 'Inconnu';
    return _dateFormat.format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.history_rounded,
              size: 20,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Historique',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  data.requestTypeLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          Divider(color: Colors.grey.shade200, height: 1),
          const SizedBox(height: 16),
          _TimelineEntry(
            icon: Icons.radio_button_checked_rounded,
            iconColor: Colors.blue.shade600,
            label: 'Demande créée',
            value: _format(data.createdAt),
            isFirst: true,
            hasNext: true,
          ),
          _TimelineEntry(
            icon: Icons.check_circle_outline_rounded,
            iconColor: Colors.green.shade600,
            label: 'Acceptée',
            value: _format(data.acceptedAt),
            isFirst: false,
            hasNext: (data.teamValidations?.isNotEmpty ?? false) || data.validatedAt != null,
          ),
          // Validations par équipe (échanges)
          if (data.teamValidations != null)
            ...data.teamValidations!.map((tv) => _TimelineEntry(
              icon: Icons.verified_outlined,
              iconColor: Colors.purple.shade600,
              label: tv.validatorName != null
                  ? 'Validé éq. ${tv.teamId} par ${tv.validatorName}'
                  : 'Validé éq. ${tv.teamId}',
              value: _format(tv.validatedAt),
              isFirst: false,
              hasNext: tv != data.teamValidations!.last,
            ))
          // Validation unique (remplacements)
          else if (data.validatedAt != null)
            _TimelineEntry(
              icon: Icons.verified_outlined,
              iconColor: Colors.purple.shade600,
              label: data.validatorName != null
                  ? 'Validée par ${data.validatorName}'
                  : 'Validée par un chef',
              value: _format(data.validatedAt),
              isFirst: false,
              hasNext: false,
            ),
          const SizedBox(height: 4),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'Fermer',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Ligne de la timeline avec connecteur vertical
class _TimelineEntry extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool isFirst;
  final bool hasNext;

  const _TimelineEntry({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.isFirst,
    required this.hasNext,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Colonne timeline : icône + ligne verticale
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Icon(icon, size: 20, color: iconColor),
                if (hasNext)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Colonne texte
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: hasNext ? 16 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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
