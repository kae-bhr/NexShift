import 'package:flutter/foundation.dart';

/// Contexte global pour le SDIS actuellement sélectionné
/// Permet à tous les repositories d'accéder au sdisId sans le passer en paramètre
class SDISContext {
  static final SDISContext _instance = SDISContext._internal();

  factory SDISContext() => _instance;

  SDISContext._internal();

  /// SDIS ID actuellement actif (ex: "50")
  String? _currentSDISId;

  /// Récupère le SDIS ID actuel
  String? get currentSDISId => _currentSDISId;

  /// Définit le SDIS ID actuel
  /// Appelé lors du login avec succès
  void setCurrentSDISId(String? sdisId) {
    _currentSDISId = sdisId;
    debugPrint('📍 SDIS Context set to: $sdisId');
  }

  /// Efface le SDIS ID actuel
  /// Appelé lors du logout
  void clear() {
    _currentSDISId = null;
    debugPrint('📍 SDIS Context cleared');
  }

  /// Vérifie si un SDIS est défini
  bool get hasSDIS => _currentSDISId != null && _currentSDISId!.isNotEmpty;
}
