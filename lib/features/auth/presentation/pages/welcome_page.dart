import 'package:flutter/material.dart';
import 'package:nexshift_app/core/presentation/pages/about_page.dart';
import 'package:nexshift_app/features/auth/presentation/pages/sdis_selection_page.dart';
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';
import 'package:nexshift_app/features/auth/presentation/pages/discover_page.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('🏠 [WELCOME_PAGE] build() called');
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HeroWidget(),
            FilledButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) {
                      return DiscoverPage();
                    },
                  ),
                );
              },
              child: Text(
                "Je découvre NexShift",
                style: TextStyle(fontSize: 16),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) {
                      return const SDISSelectionPage();
                    },
                  ),
                );
              },
              child: Text("Je me connecte", style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 40.0),
        child: TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) {
                  return AboutPage();
                },
              ),
            );
          },
          child: Text('À propos © NexShift 2025', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
