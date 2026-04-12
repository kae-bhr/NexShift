import 'package:flutter/material.dart';

/// Clé globale du Navigator de l'application.
/// Déclarée ici (et non dans main.dart) pour éviter les dépendances circulaires
/// (ex: MaintenanceService a besoin de naviguerKey pour la navigation impérative).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
