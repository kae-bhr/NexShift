import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:releve/core/data/datasources/notifiers.dart';

class HeroWidget extends StatelessWidget {
  const HeroWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

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
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: SizedBox(
              width: size.width * 0.85,
              height: size.height * 0.40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Lottie.asset(
                    "assets/lotties/background.json",
                    fit: BoxFit.contain,
                  ),
                  Image.asset(
                    "assets/images/RELÈVE.png",
                    width: size.width * 0.55,
                    height: size.height * 0.40,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
