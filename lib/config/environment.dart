/// Configuration de l'environnement de l'application
/// Gère la sélection entre dev, staging et production
enum AppEnvironment {
  dev,
  staging,
  prod,
}

class Environment {
  /// Environnement actuel (défini via --dart-define=ENV)
  static AppEnvironment get current {
    const envString = String.fromEnvironment('ENV', defaultValue: 'prod');
    switch (envString.toLowerCase()) {
      case 'dev':
      case 'development':
        return AppEnvironment.dev;
      case 'staging':
      case 'stag':
        return AppEnvironment.staging;
      case 'prod':
      case 'production':
      default:
        return AppEnvironment.prod;
    }
  }

  /// Indique si on est en environnement de production
  static bool get isProduction => current == AppEnvironment.prod;

  /// Indique si on est en environnement de développement
  static bool get isDevelopment => current == AppEnvironment.dev;

  /// Indique si on est en environnement de staging
  static bool get isStaging => current == AppEnvironment.staging;

  /// Nom de l'environnement pour affichage
  static String get name {
    switch (current) {
      case AppEnvironment.dev:
        return 'DÉVELOPPEMENT';
      case AppEnvironment.staging:
        return 'STAGING';
      case AppEnvironment.prod:
        return 'PRODUCTION';
    }
  }

  /// Couleur de la bannière selon l'environnement
  static int get bannerColor {
    switch (current) {
      case AppEnvironment.dev:
        return 0xFFFF9800; // Orange
      case AppEnvironment.staging:
        return 0xFF2196F3; // Bleu
      case AppEnvironment.prod:
        return 0xFF4CAF50; // Vert (non affiché)
    }
  }

  /// Indique si on doit afficher la bannière
  static bool get showBanner => !isProduction;

  /// Message de la bannière
  static String get bannerMessage {
    switch (current) {
      case AppEnvironment.dev:
        return '⚠️ ENVIRONNEMENT DE DÉVELOPPEMENT ⚠️';
      case AppEnvironment.staging:
        return 'ℹ️ ENVIRONNEMENT DE STAGING';
      case AppEnvironment.prod:
        return '';
    }
  }
}
