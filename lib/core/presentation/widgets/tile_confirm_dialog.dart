import 'package:flutter/material.dart';

/// Dialog de confirmation réutilisable pour les actions des tuiles unifiées.
///
/// Affiche une icône colorée, un titre, un message, et deux boutons
/// (Annuler / action confirmée).
class TileConfirmDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;
  final IconData confirmIcon;

  const TileConfirmDialog({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
    required this.confirmIcon,
  });

  /// Ouvre le dialog et retourne true si confirmé, false/null sinon.
  static Future<bool?> show(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    required IconData confirmIcon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => TileConfirmDialog(
        icon: icon,
        iconColor: iconColor,
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        confirmColor: confirmColor,
        confirmIcon: confirmIcon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.grey[300] : Colors.grey[700],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: Icon(confirmIcon, size: 16),
          label: Text(confirmLabel),
          style: FilledButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
