import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/navigation/navigator_key.dart';
import 'package:nexshift_app/core/presentation/pages/maintenance_page.dart';
import 'package:nexshift_app/features/app_shell/presentation/widgets/widget_tree.dart';

/// Service qui écoute l'état de maintenance de l'application
/// via les documents Firestore `app_config/maintenance` (global)
/// et `sdis/{sdisId}/app_config/maintenance` (SDIS-level).
///
/// ### Champs du document global (`app_config/maintenance`) :
/// - `enabled` (bool) : true si l'app est en maintenance globale
/// - `message` (String) : message affiché aux utilisateurs
/// - `allowedUsers` (`List<Map>`) : couples {sdisId, userId} autorisés malgré la maintenance
/// - `allowedUserIds` (`List<String>`) : ancien format conservé pour rétrocompatibilité (SDIS-agnostic)
///
/// ### Champs du document SDIS (`sdis/{sdisId}/app_config/maintenance`) :
/// - `enabled` (bool) : true si ce SDIS est en maintenance
/// - `message` (String) : message affiché aux utilisateurs du SDIS
/// - `allowedUserIds` (`List<String>`) : matricules autorisés malgré la maintenance du SDIS
class MaintenanceService {
  MaintenanceService._() {
    // Écouter les changements de userNotifier pour réévaluer le blocage
    // quand un utilisateur se connecte/déconnecte sans que le document Firestore change.
    userNotifier.addListener(_updateCombinedState);
  }

  static final MaintenanceService _instance = MaintenanceService._();
  factory MaintenanceService() => _instance;

  // ── Notifiers globaux ──────────────────────────────────────────────────────
  final ValueNotifier<bool> isMaintenanceNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String> maintenanceMessageNotifier =
      ValueNotifier<String>('');

  // ── Notifiers SDIS ─────────────────────────────────────────────────────────
  final ValueNotifier<bool> isSdisMaintenanceNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<String> sdisMaintenanceMessageNotifier =
      ValueNotifier<String>('');

  // ── État interne global ────────────────────────────────────────────────────
  List<({String sdisId, String userId})> _allowedUsers = [];
  List<String> _legacyAllowedUserIds = []; // rétrocompatibilité
  StreamSubscription<DocumentSnapshot>? _subscription;

  // ── État interne SDIS ──────────────────────────────────────────────────────
  List<String> _sdisAllowedUserIds = [];
  StreamSubscription<DocumentSnapshot>? _sdisSubscription;

  // ── Message effectif ───────────────────────────────────────────────────────
  /// Retourne le message de maintenance le plus pertinent (SDIS prioritaire sur global).
  String get effectiveMaintenanceMessage {
    if (isSdisMaintenanceNotifier.value &&
        sdisMaintenanceMessageNotifier.value.isNotEmpty) {
      return sdisMaintenanceMessageNotifier.value;
    }
    return maintenanceMessageNotifier.value;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION : Maintenance globale
  // ══════════════════════════════════════════════════════════════════════════

  /// Démarre l'écoute en temps réel du document global `app_config/maintenance`.
  void startListening() {
    _subscription?.cancel();
    _subscription = FirebaseFirestore.instance
        .doc('app_config/maintenance')
        .snapshots()
        .listen(
      (snapshot) {
        _processGlobalSnapshot(snapshot);
      },
      onError: (error) {
        debugPrint('❌ [MAINTENANCE] Error listening global: $error');
        isMaintenanceNotifier.value = false;
      },
    );
  }

  /// Lecture unique (one-shot) du document global.
  /// Utilisé dans EnterApp.build() pour assurer un état synchrone avant
  /// de positionner isUserAuthentifiedNotifier.
  Future<void> checkGlobalMaintenance() async {
    try {
      final doc = await FirebaseFirestore.instance
          .doc('app_config/maintenance')
          .get();
      _processGlobalSnapshot(doc);
    } catch (e) {
      debugPrint('❌ [MAINTENANCE] Error checking global maintenance: $e');
    }
  }

  void _processGlobalSnapshot(DocumentSnapshot snapshot) {
    if (!snapshot.exists) {
      isMaintenanceNotifier.value = false;
      maintenanceMessageNotifier.value = '';
      _allowedUsers = [];
      _legacyAllowedUserIds = [];
      _updateCombinedState();
      return;
    }

    final data = snapshot.data() as Map<String, dynamic>?;
    if (data == null) {
      isMaintenanceNotifier.value = false;
      _updateCombinedState();
      return;
    }

    isMaintenanceNotifier.value = data['enabled'] == true;
    maintenanceMessageNotifier.value =
        (data['message'] as String?) ?? 'Maintenance en cours';

    // Nouveau format : allowedUsers = [{sdisId, userId}]
    final allowedUsersRaw = data['allowedUsers'] as List<dynamic>? ?? [];
    _allowedUsers = allowedUsersRaw
        .whereType<Map>()
        .map((m) => (
              sdisId: (m['sdisId'] as String?) ?? '',
              userId: (m['userId'] as String?) ?? '',
            ))
        .where((e) => e.sdisId.isNotEmpty && e.userId.isNotEmpty)
        .toList();

    // Ancien format : allowedUserIds = [userId] — rétrocompat SDIS-agnostic
    _legacyAllowedUserIds =
        List<String>.from(data['allowedUserIds'] ?? []);

    _updateCombinedState();
  }

  /// Vérifie si un utilisateur est autorisé à passer malgré la maintenance globale.
  bool isUserAllowed(String? userId, String? sdisId) {
    if (userId == null) return false;
    // Nouveau format : correspondance exacte (sdisId, userId)
    if (sdisId != null &&
        _allowedUsers
            .any((e) => e.sdisId == sdisId && e.userId == userId)) {
      return true;
    }
    // Ancien format : userId seul (SDIS-agnostic, rétrocompatibilité)
    if (_legacyAllowedUserIds.contains(userId)) return true;
    return false;
  }

  /// Arrête l'écoute du document global.
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    userNotifier.removeListener(_updateCombinedState);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION : Maintenance SDIS
  // ══════════════════════════════════════════════════════════════════════════

  /// Démarre l'écoute en temps réel du document SDIS `sdis/{sdisId}/app_config/maintenance`.
  void startListeningForSdis(String sdisId) {
    _sdisSubscription?.cancel();
    _sdisSubscription = FirebaseFirestore.instance
        .doc('sdis/$sdisId/app_config/maintenance')
        .snapshots()
        .listen(
      (snapshot) {
        _processSdisSnapshot(snapshot);
      },
      onError: (error) {
        debugPrint('❌ [MAINTENANCE] Error listening SDIS: $error');
        isSdisMaintenanceNotifier.value = false;
      },
    );
  }

  /// Lecture unique (one-shot) du document SDIS.
  Future<void> checkSdisMaintenance(String sdisId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .doc('sdis/$sdisId/app_config/maintenance')
          .get();
      _processSdisSnapshot(doc);
    } catch (e) {
      debugPrint('❌ [MAINTENANCE] Error checking SDIS maintenance: $e');
    }
  }

  void _processSdisSnapshot(DocumentSnapshot snapshot) {
    if (!snapshot.exists) {
      isSdisMaintenanceNotifier.value = false;
      sdisMaintenanceMessageNotifier.value = '';
      _sdisAllowedUserIds = [];
      _updateCombinedState();
      return;
    }

    final data = snapshot.data() as Map<String, dynamic>?;
    if (data == null) {
      isSdisMaintenanceNotifier.value = false;
      _updateCombinedState();
      return;
    }

    isSdisMaintenanceNotifier.value = data['enabled'] == true;
    sdisMaintenanceMessageNotifier.value =
        (data['message'] as String?) ?? 'Maintenance en cours';
    _sdisAllowedUserIds =
        List<String>.from(data['allowedUserIds'] ?? []);

    _updateCombinedState();
  }

  /// Vérifie si un utilisateur est autorisé malgré la maintenance SDIS.
  bool isSdisUserAllowed(String? userId) {
    if (userId == null) return false;
    return _sdisAllowedUserIds.contains(userId);
  }

  /// Arrête l'écoute du document SDIS.
  void stopListeningForSdis() {
    _sdisSubscription?.cancel();
    _sdisSubscription = null;
  }

  /// Réinitialise l'état SDIS (à appeler au logout).
  void resetSdisState() {
    isSdisMaintenanceNotifier.value = false;
    sdisMaintenanceMessageNotifier.value = '';
    _sdisAllowedUserIds = [];
    isBlockedByMaintenanceNotifier.value = false;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION : État combiné + navigation impérative
  // ══════════════════════════════════════════════════════════════════════════

  /// Recalcule l'état combiné de blocage et navigue impérativement si nécessaire.
  ///
  /// Appelé :
  /// - À chaque snapshot Firestore (global ou SDIS)
  /// - À chaque changement de userNotifier (connexion/déconnexion)
  void _updateCombinedState() {
    final user = userNotifier.value;
    final sdisId = SDISContext().currentSDISId;
    final wasBlocked = isBlockedByMaintenanceNotifier.value;

    final globalBlocked =
        isMaintenanceNotifier.value && !isUserAllowed(user?.id, sdisId);
    final sdisBlocked =
        isSdisMaintenanceNotifier.value && !isSdisUserAllowed(user?.id);
    final nowBlocked = globalBlocked || sdisBlocked;

    isBlockedByMaintenanceNotifier.value = nowBlocked;

    // Navigation impérative : utilisateur déjà authentifié dans l'app
    // → bloquer si la maintenance vient de s'activer
    if (!wasBlocked && nowBlocked &&
        user != null &&
        isUserAuthentifiedNotifier.value) {
      debugPrint(
          '🚧 [MAINTENANCE] Blocking active user — navigating to MaintenancePage');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) =>
                MaintenancePage(message: effectiveMaintenanceMessage),
          ),
          (route) => false,
        );
      });
    }

    // Navigation impérative : maintenance levée → retour vers WidgetTree
    if (wasBlocked &&
        !nowBlocked &&
        user != null &&
        isUserAuthentifiedNotifier.value) {
      debugPrint(
          '✅ [MAINTENANCE] Maintenance lifted — navigating back to WidgetTree');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => WidgetTree(key: ValueKey(user.id)),
          ),
          (route) => false,
        );
      });
    }
  }
}
