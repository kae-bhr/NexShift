import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:releve/core/utils/constants.dart';

/// Bouton affichant une date/heure sélectionnée ou un label placeholder.
/// Déclenche [onTap] pour ouvrir le sélecteur de date/heure.
class DateTimeButton extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  const DateTimeButton({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fmt = DateFormat('dd/MM HH:mm');
    final hasValue = value != null;

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(
        Icons.schedule_rounded,
        size: 16,
        color: hasValue ? KColors.appNameColor : null,
      ),
      label: Text(
        hasValue ? fmt.format(value!) : label,
        style: TextStyle(
          color: hasValue
              ? KColors.appNameColor
              : (isDark ? Colors.white54 : Colors.grey.shade600),
          fontSize: 13,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        side: BorderSide(
          color: hasValue
              ? KColors.appNameColor.withValues(alpha: 0.5)
              : (isDark ? Colors.white24 : Colors.grey.shade400),
        ),
      ),
    );
  }
}
