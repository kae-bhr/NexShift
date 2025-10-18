import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';

class HeroWidget extends StatelessWidget {
  const HeroWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final taille = MediaQuery.of(context).size;

    return ValueListenableBuilder(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDarkMode, child) {
        return Hero(
          tag: 'hero_logo',
          flightShuttleBuilder:
              (
                BuildContext flightContext,
                Animation<double> animation,
                HeroFlightDirection flightDirection,
                BuildContext fromHeroContext,
                BuildContext toHeroContext,
              ) {
                return fromHeroContext.widget;
              },
          child: Stack(
            alignment: Alignment.center,
            children: [
              Lottie.asset(
                "assets/lotties/animated_logo.json", // animated_logo
                fit: BoxFit.contain,
                width: taille.width * 0.9,
                height: taille.height * 0.4,
              ),
              Image.asset(
                "assets/images/NexShift.png",
                width: taille.width * 0.5,
                fit: BoxFit.contain,
              ),
            ],
          ),
        );
      },
    );
  }
}
