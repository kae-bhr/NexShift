import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexshift_app/core/utils/constants.dart';

class KTheme {
  static ThemeData lightTheme = ThemeData(
    platform: TargetPlatform.iOS,
    primaryColor: KColors.appNameColor,
    useMaterial3: false,
    colorScheme: ColorScheme.fromSeed(
      seedColor: KColors.appNameColor,
      primary: KColors.appNameColor, // Logo and highlight 1st color
      inversePrimary: Colors.white, // Logo shadow
      primaryFixed: KColors.appNameColor, // Theme color
      secondary: Colors.white, // Text over theme color
      tertiary: Colors.black, // Text over brighness mode
      brightness: Brightness.light,
    ),
    appBarTheme: const AppBarTheme(
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark, // Android: black icons
        statusBarBrightness: Brightness.light, // iOS: dark text
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
    ),
  );

  static ThemeData darkTheme = ThemeData(
    platform: TargetPlatform.iOS,
    primaryColor: KColors.appNameColor,
    useMaterial3: false,
    colorScheme: ColorScheme.fromSeed(
      seedColor: KColors.appNameColor,
      primary: Colors.white, // Logo and highlight 1st color
      inversePrimary: KColors.appNameColor, // Logo shadow
      primaryFixed: KColors.appNameColor, // Theme color
      secondary: Colors.white, // Text over theme color
      tertiary: Colors.white, // Text over brighness mode
      brightness: Brightness.dark,
    ),
    appBarTheme: const AppBarTheme(
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light, // Android: white icons
        statusBarBrightness: Brightness.dark, // iOS: light text
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
    ),
  );
}
