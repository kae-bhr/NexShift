import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/presentation/pages/about_page.dart';
import 'package:nexshift_app/features/auth/presentation/pages/sdis_selection_page.dart';
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';
import 'package:nexshift_app/features/auth/presentation/pages/sdis_selection_for_create_account_page.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('🏠 [WELCOME_PAGE] build() called');
    return ValueListenableBuilder<bool>(
      valueListenable: isRestoringSessionNotifier,
      builder: (context, isRestoring, _) {
        return Scaffold(
          body: Stack(
            children: [
              // Contenu principal
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    HeroWidget(),
                    FilledButton(
                      onPressed: isRestoring
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const SDISSelectionForCreateAccountPage(),
                                ),
                              );
                            },
                      child: const Text(
                        'Créer un compte',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    TextButton(
                      onPressed: isRestoring
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const SDISSelectionPage(),
                                ),
                              );
                            },
                      child: const Text(
                        'Se connecter',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),

              // Overlay de chargement pendant la réauthentification automatique
              if (isRestoring) const _RestoringSessionOverlay(),
            ],
          ),
          bottomNavigationBar: Container(
            padding: const EdgeInsets.symmetric(
              vertical: 10.0,
              horizontal: 40.0,
            ),
            child: TextButton(
              onPressed: isRestoring
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AboutPage(),
                        ),
                      );
                    },
              child: const Text(
                'À propos © NexShift 2025',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RestoringSessionOverlay extends StatelessWidget {
  const _RestoringSessionOverlay();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned.fill(
      child: IgnorePointer(
        // Bloque les taps mais laisse la page visible en dessous
        ignoring: false,
        child: Container(
          // Fond semi-transparent léger pour ne pas masquer le logo/animation
          color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Zone de chargement en bas, au-dessus des boutons
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Connexion en cours…',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
