import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Lightweight app theme & style helpers. This file re-exports the
/// constants (colors/text styles) and provides a default ThemeData so
/// callers can import one coherent place for UI styling.
export '../utils/constants.dart';

ThemeData getAppTheme() {
  return ThemeData(
    primaryColor: const Color.fromRGBO(144, 74, 68, 1),
    colorScheme: ColorScheme.fromSeed(seedColor: KColors.appNameColor),
    textTheme: const TextTheme(
      titleLarge: KTextStyle.titleTextStyle,
      bodyLarge: KTextStyle.regularTextStyle,
      bodyMedium: KTextStyle.descriptionTextStyle,
    ),
    useMaterial3: true,
  );
}
