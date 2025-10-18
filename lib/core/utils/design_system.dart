import 'package:flutter/material.dart';

/// Design System centralisé pour l'application NexShift
/// Définit tous les tokens de design : spacing, typography, colors, animations, etc.

/// Espacements standardisés (en pixels)
class KSpacing {
  static const double xs = 4.0;
  static const double s = 8.0;
  static const double m = 12.0;
  static const double l = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 48.0;

  // Padding symétriques communs
  static const EdgeInsets paddingXS = EdgeInsets.all(xs);
  static const EdgeInsets paddingS = EdgeInsets.all(s);
  static const EdgeInsets paddingM = EdgeInsets.all(m);
  static const EdgeInsets paddingL = EdgeInsets.all(l);
  static const EdgeInsets paddingXL = EdgeInsets.all(xl);

  // Padding horizontaux
  static const EdgeInsets paddingHorizontalS = EdgeInsets.symmetric(
    horizontal: s,
  );
  static const EdgeInsets paddingHorizontalM = EdgeInsets.symmetric(
    horizontal: m,
  );
  static const EdgeInsets paddingHorizontalL = EdgeInsets.symmetric(
    horizontal: l,
  );
  static const EdgeInsets paddingHorizontalXL = EdgeInsets.symmetric(
    horizontal: xl,
  );

  // Padding verticaux
  static const EdgeInsets paddingVerticalS = EdgeInsets.symmetric(vertical: s);
  static const EdgeInsets paddingVerticalM = EdgeInsets.symmetric(vertical: m);
  static const EdgeInsets paddingVerticalL = EdgeInsets.symmetric(vertical: l);
  static const EdgeInsets paddingVerticalXL = EdgeInsets.symmetric(
    vertical: xl,
  );
}

/// Système typographique hiérarchisé
class KTypography {
  // Tailles de police standardisées
  static const double fontSizeCaption = 12.0;
  static const double fontSizeBody = 14.0;
  static const double fontSizeBodyLarge = 16.0;
  static const double fontSizeTitle = 18.0;
  static const double fontSizeHeadline = 20.0;
  static const double fontSizeDisplay = 24.0;

  // Poids de police
  static const FontWeight fontWeightRegular = FontWeight.w400;
  static const FontWeight fontWeightMedium = FontWeight.w500;
  static const FontWeight fontWeightSemiBold = FontWeight.w600;
  static const FontWeight fontWeightBold = FontWeight.w700;

  // Styles de texte prédéfinis
  static TextStyle caption({Color? color}) => TextStyle(
    fontSize: fontSizeCaption,
    fontWeight: fontWeightRegular,
    color: color,
  );

  static TextStyle body({Color? color, FontWeight? fontWeight}) => TextStyle(
    fontSize: fontSizeBody,
    fontWeight: fontWeight ?? fontWeightRegular,
    color: color,
  );

  static TextStyle bodyLarge({Color? color, FontWeight? fontWeight}) =>
      TextStyle(
        fontSize: fontSizeBodyLarge,
        fontWeight: fontWeight ?? fontWeightRegular,
        color: color,
      );

  static TextStyle title({Color? color, FontWeight? fontWeight}) => TextStyle(
    fontSize: fontSizeTitle,
    fontWeight: fontWeight ?? fontWeightSemiBold,
    color: color,
  );

  static TextStyle headline({Color? color, FontWeight? fontWeight}) =>
      TextStyle(
        fontSize: fontSizeHeadline,
        fontWeight: fontWeight ?? fontWeightBold,
        color: color,
      );

  static TextStyle display({Color? color, FontWeight? fontWeight}) => TextStyle(
    fontSize: fontSizeDisplay,
    fontWeight: fontWeight ?? fontWeightBold,
    color: color,
  );
}

/// Paramètres d'animation standardisés
class KAnimations {
  // Durées
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationNormal = Duration(milliseconds: 300);
  static const Duration durationSlow = Duration(milliseconds: 500);

  // Curves
  static const Curve curveDefault = Curves.easeInOut;
  static const Curve curveEaseOut = Curves.easeOut;
  static const Curve curveEaseIn = Curves.easeIn;
  static const Curve curveSpring = Curves.elasticOut;

  // Transitions
  static Widget fadeTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }

  static Widget slideFromBottomTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const begin = Offset(0.0, 1.0);
    const end = Offset.zero;
    final tween = Tween(begin: begin, end: end);
    final offsetAnimation = animation.drive(
      tween.chain(CurveTween(curve: curveDefault)),
    );
    return SlideTransition(position: offsetAnimation, child: child);
  }
}

/// Radius de bordures standardisés
class KBorderRadius {
  static const double s = 8.0;
  static const double m = 12.0;
  static const double l = 16.0;
  static const double xl = 20.0;

  static BorderRadius circularS = BorderRadius.circular(s);
  static BorderRadius circularM = BorderRadius.circular(m);
  static BorderRadius circularL = BorderRadius.circular(l);
  static BorderRadius circularXL = BorderRadius.circular(xl);
}

/// Élévations standardisées pour Material
class KElevation {
  static const double none = 0.0;
  static const double low = 1.0;
  static const double medium = 2.0;
  static const double high = 4.0;
  static const double veryHigh = 8.0;
}

/// Tailles d'icônes standardisées
class KIconSize {
  static const double s = 18.0;
  static const double m = 24.0;
  static const double l = 30.0;
  static const double xl = 40.0;
}

/// Tailles d'avatars standardisées
class KAvatarSize {
  static const double s = 32.0;
  static const double m = 40.0;
  static const double l = 56.0;
  static const double xl = 80.0;
}

/// Messages d'erreur user-friendly
class KErrorMessages {
  static const String networkError = 'Impossible de se connecter au serveur';
  static const String loadingError = 'Erreur lors du chargement des données';
  static const String saveError = 'Impossible de sauvegarder les modifications';
  static const String userNotFound = 'Utilisateur introuvable';
  static const String teamNotFound = 'Équipe introuvable';
  static const String noData = 'Aucune donnée disponible';
  static const String tryAgain = 'Veuillez réessayer';
}

/// Messages de succès
class KSuccessMessages {
  static const String saved = 'Modifications enregistrées';
  static const String updated = 'Mise à jour effectuée';
  static const String deleted = 'Suppression effectuée';
}

/// Durées de simulation réseau (pour mock data)
class KNetworkDelay {
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
}
