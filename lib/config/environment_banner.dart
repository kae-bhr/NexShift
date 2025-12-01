import 'package:flutter/material.dart';
import 'package:nexshift_app/config/environment.dart';

/// Bannière affichée en haut de l'app pour les environnements dev/staging
class EnvironmentBanner extends StatelessWidget {
  final Widget child;

  const EnvironmentBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!Environment.showBanner) {
      return child;
    }

    return Stack(
      children: [
        // Contenu de l'app
        child,
        // Bandeau positionné en haut (au-dessus de tout)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            width: double.infinity,
            color: Color(Environment.bannerColor),
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              Environment.bannerMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 10,
                height: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
