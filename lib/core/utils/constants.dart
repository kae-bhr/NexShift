import 'package:flutter/material.dart';

class KColors {
  static const Color appNameColor = Color.fromARGB(255, 144, 74, 68);
}

class KTextStyle {
  static const TextStyle titleBoldTextStyleLightMode = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.bold,
    color: KColors.appNameColor,
    fontFamily: 'Roboto',
    shadows: [Shadow(blurRadius: 10, color: Colors.white)],
  );
  static const TextStyle regularBoldTextStyleLightMode = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
    color: KColors.appNameColor,
    fontFamily: 'Roboto',
    shadows: [Shadow(blurRadius: 10, color: Colors.white)],
  );
  static const TextStyle descriptionBoldTextStyleLightMode = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: KColors.appNameColor,
    fontFamily: 'Roboto',
    shadows: [Shadow(blurRadius: 10, color: Colors.white)],
  );
  static const TextStyle regularTextStyleLightMode = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.normal,
    color: KColors.appNameColor,
    fontFamily: 'Roboto',
  );
  static const TextStyle descriptionTextStyleLightMode = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w300,
    fontFamily: 'Roboto',
  );
}
