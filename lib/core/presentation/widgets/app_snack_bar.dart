import 'package:flutter/material.dart';

/// Helper standardisé pour afficher des SnackBars cohérents dans toute l'app.
///
/// Utilisation :
///   AppSnackBar.success(context, 'Modification enregistrée');
///   AppSnackBar.error(context, 'Une erreur est survenue');
///   AppSnackBar.info(context, 'Chargement en cours...');
abstract class AppSnackBar {
  static const Duration _defaultDuration = Duration(seconds: 3);
  static const Duration _longDuration = Duration(seconds: 5);

  /// Notification de succès (fond vert)
  static void success(
    BuildContext context,
    String message, {
    Duration duration = _defaultDuration,
    SnackBarAction? action,
  }) {
    _show(
      context,
      message,
      backgroundColor: Colors.green.shade700,
      icon: Icons.check_circle_outline,
      duration: duration,
      action: action,
    );
  }

  /// Notification d'erreur (fond rouge)
  static void error(
    BuildContext context,
    String message, {
    Duration duration = _longDuration,
    SnackBarAction? action,
  }) {
    _show(
      context,
      message,
      backgroundColor: Colors.red.shade700,
      icon: Icons.error_outline,
      duration: duration,
      action: action,
    );
  }

  /// Notification informative (fond gris foncé — style Material par défaut)
  static void info(
    BuildContext context,
    String message, {
    Duration duration = _defaultDuration,
    SnackBarAction? action,
  }) {
    _show(
      context,
      message,
      backgroundColor: Colors.grey.shade800,
      icon: Icons.info_outline,
      duration: duration,
      action: action,
    );
  }

  static void _show(
    BuildContext context,
    String message, {
    required Color backgroundColor,
    required IconData icon,
    required Duration duration,
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: backgroundColor,
          duration: duration,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          action: action,
        ),
      );
  }
}
