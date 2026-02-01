import 'package:flutter/material.dart';

/// Page affichée quand l'abonnement de la caserne est expiré
class SubscriptionExpiredPage extends StatelessWidget {
  const SubscriptionExpiredPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 120,
                color: Colors.red[400],
              ),
              const SizedBox(height: 32),
              Text(
                'Abonnement expiré',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                "L'abonnement de votre caserne a expiré.\n\n"
                "Veuillez contacter votre responsable pour renouveler "
                "la licence NexShift.",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              Icon(
                Icons.email_outlined,
                size: 32,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 8),
              Text(
                'contact@nexshift.app',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
