import 'package:flutter/material.dart';
import 'package:nexshift_app/core/utils/design_system.dart';

/// Widget d'erreur réutilisable avec message user-friendly et bouton retry
class ErrorWidget extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;
  final IconData icon;

  const ErrorWidget({
    super.key,
    this.message,
    this.onRetry,
    this.icon = Icons.error_outline,
  });

  @override
  Widget build(BuildContext context) {
    final displayMessage = message ?? KErrorMessages.loadingError;

    return Center(
      child: Padding(
        padding: KSpacing.paddingXL,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(context).colorScheme.error.withOpacity(0.7),
            ),
            SizedBox(height: KSpacing.l),
            Text(
              displayMessage,
              textAlign: TextAlign.center,
              style: KTypography.bodyLarge(
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            SizedBox(height: KSpacing.m),
            Text(
              KErrorMessages.tryAgain,
              textAlign: TextAlign.center,
              style: KTypography.caption(
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(height: KSpacing.xl),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: KSpacing.xl,
                    vertical: KSpacing.m,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: KBorderRadius.circularM,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Widget d'état vide réutilisable
class EmptyStateWidget extends StatelessWidget {
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyStateWidget({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: KSpacing.paddingXL,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(context).colorScheme.tertiary.withOpacity(0.5),
            ),
            SizedBox(height: KSpacing.l),
            Text(
              message,
              textAlign: TextAlign.center,
              style: KTypography.bodyLarge(
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: KSpacing.xl),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
