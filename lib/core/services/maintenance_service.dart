import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Service qui écoute l'état de maintenance de l'application
/// via le document Firestore `app_config/maintenance`.
///
/// Champs attendus :
/// - `enabled` (bool) : true si l'app est en maintenance
/// - `message` (String) : message affiché aux utilisateurs
/// - `allowedUserIds` (List<String>) : UIDs autorisés malgré la maintenance
class MaintenanceService {
  MaintenanceService._();
  static final MaintenanceService _instance = MaintenanceService._();
  factory MaintenanceService() => _instance;

  final ValueNotifier<bool> isMaintenanceNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String> maintenanceMessageNotifier =
      ValueNotifier<String>('');

  List<String> _allowedUserIds = [];
  StreamSubscription<DocumentSnapshot>? _subscription;

  /// Démarre l'écoute en temps réel du document maintenance
  void startListening() {
    _subscription?.cancel();
    _subscription = FirebaseFirestore.instance
        .doc('app_config/maintenance')
        .snapshots()
        .listen(
      (snapshot) {
        if (!snapshot.exists) {
          isMaintenanceNotifier.value = false;
          maintenanceMessageNotifier.value = '';
          _allowedUserIds = [];
          return;
        }

        final data = snapshot.data();
        if (data == null) {
          isMaintenanceNotifier.value = false;
          return;
        }

        isMaintenanceNotifier.value = data['enabled'] == true;
        maintenanceMessageNotifier.value =
            (data['message'] as String?) ?? 'Maintenance en cours';
        _allowedUserIds = List<String>.from(data['allowedUserIds'] ?? []);
      },
      onError: (error) {
        debugPrint('❌ [MAINTENANCE] Error listening: $error');
        // En cas d'erreur, ne pas bloquer l'app
        isMaintenanceNotifier.value = false;
      },
    );
  }

  /// Vérifie si un utilisateur est autorisé malgré la maintenance
  bool isUserAllowed(String? userId) {
    if (userId == null) return false;
    return _allowedUserIds.contains(userId);
  }

  /// Arrête l'écoute
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }
}
