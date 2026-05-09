import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:releve/core/data/datasources/user_storage_helper.dart';

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

  /// Filet de sécurité : s'assure que le SDIS ID est initialisé.
  /// Tente de récupérer depuis :
  /// 1. SharedPreferences (rapide, local)
  /// 2. Firebase Auth email ({sdisId}_{matricule}@nexshift.app)
  /// 3. Firebase Auth custom claims (sdisId)
  /// Sauvegarde dans SharedPreferences si récupéré depuis Firebase.
  Future<void> ensureInitialized() async {
    if (hasSDIS) return;

    debugPrint('🔄 [SDIS_CONTEXT] ensureInitialized() - no SDIS in memory, attempting recovery...');

    // 1. Essayer SharedPreferences
    final storedSdisId = await UserStorageHelper.loadSdisId();
    if (storedSdisId != null && storedSdisId.isNotEmpty) {
      _currentSDISId = storedSdisId;
      debugPrint('✅ [SDIS_CONTEXT] Recovered from SharedPreferences: $storedSdisId');
      return;
    }

    // 2. Essayer Firebase Auth email
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      final email = firebaseUser.email;
      if (email != null && email.endsWith('@nexshift.app')) {
        final parts = email.split('@')[0].split('_');
        if (parts.isNotEmpty && parts[0].isNotEmpty) {
          _currentSDISId = parts[0];
          debugPrint('✅ [SDIS_CONTEXT] Recovered from Firebase email: ${parts[0]}');
          await UserStorageHelper.saveSdisId(parts[0]);
          return;
        }
      }

      // 3. Essayer Firebase Auth custom claims
      try {
        final tokenResult = await firebaseUser.getIdTokenResult();
        final claims = tokenResult.claims;
        if (claims != null && claims['sdisId'] is String) {
          final claimsSdisId = claims['sdisId'] as String;
          if (claimsSdisId.isNotEmpty) {
            _currentSDISId = claimsSdisId;
            debugPrint('✅ [SDIS_CONTEXT] Recovered from Firebase claims: $claimsSdisId');
            await UserStorageHelper.saveSdisId(claimsSdisId);
            return;
          }
        }
      } catch (e) {
        debugPrint('⚠️ [SDIS_CONTEXT] Failed to read Firebase claims: $e');
      }
    }

    debugPrint('❌ [SDIS_CONTEXT] Could not recover SDIS ID from any source');
  }
}
