import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:releve/core/data/datasources/notifiers.dart';
import 'package:releve/core/data/models/station_model.dart';

/// État de l'abonnement d'une caserne
enum SubscriptionStatus {
  active, // Abonnement valide
  expiringSoon, // Expire dans moins de 30 jours
  expired, // Expiré
  unknown, // Pas encore chargé ou pas de date
}

/// Service qui surveille l'état de l'abonnement de la caserne courante.
/// Écoute en temps réel le document station dans Firestore pour détecter
/// les changements de subscriptionEndDate.
class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService _instance = SubscriptionService._();
  factory SubscriptionService() => _instance;

  final ValueNotifier<int> daysRemainingNotifier = ValueNotifier<int>(-1);

  final ValueNotifier<DateTime?> endDateNotifier =
      ValueNotifier<DateTime?>(null);

  StreamSubscription<DocumentSnapshot>? _subscription;
  Timer? _dailyCheckTimer;

  /// Démarre l'écoute de l'abonnement pour une station donnée
  void startListening(String sdisId, String stationId) {
    stopListening();

    final stationPath = 'sdis/$sdisId/stations/$stationId';
    debugPrint('📋 [SUBSCRIPTION] Listening to $stationPath');

    _subscription = FirebaseFirestore.instance
        .doc(stationPath)
        .snapshots()
        .listen(
      (snapshot) {
        if (!snapshot.exists) {
          _updateStatus(null);
          return;
        }

        final data = snapshot.data();
        if (data == null) {
          _updateStatus(null);
          return;
        }

        final station = Station.fromJson({...data, 'id': snapshot.id});
        _updateStatus(station.subscriptionEndDate);
      },
      onError: (error) {
        debugPrint('❌ [SUBSCRIPTION] Error listening: $error');
        subscriptionStatusNotifier.value = SubscriptionStatus.unknown;
      },
    );

    // Timer quotidien pour recalculer le statut (au cas où le jour change)
    _dailyCheckTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _recalculate(),
    );
  }

  void _updateStatus(DateTime? endDate) {
    endDateNotifier.value = endDate;
    _recalculate();
  }

  void _recalculate() {
    final endDate = endDateNotifier.value;
    if (endDate == null) {
      subscriptionStatusNotifier.value = SubscriptionStatus.unknown;
      daysRemainingNotifier.value = -1;
      return;
    }

    final now = DateTime.now();
    final daysRemaining = endDate.difference(now).inDays;
    daysRemainingNotifier.value = daysRemaining;

    if (now.isAfter(endDate)) {
      subscriptionStatusNotifier.value = SubscriptionStatus.expired;
    } else if (daysRemaining <= 30) {
      subscriptionStatusNotifier.value = SubscriptionStatus.expiringSoon;
    } else {
      subscriptionStatusNotifier.value = SubscriptionStatus.active;
    }

    debugPrint(
      '📋 [SUBSCRIPTION] Status: ${subscriptionStatusNotifier.value}, '
      'days remaining: $daysRemaining',
    );
  }

  /// Vérifie l'abonnement une seule fois (pour le check au login)
  Future<SubscriptionStatus> checkOnce(
    String sdisId,
    String stationId,
  ) async {
    try {
      final stationPath = 'sdis/$sdisId/stations/$stationId';
      debugPrint('📋 [SUBSCRIPTION] checkOnce: fetching $stationPath');
      final doc =
          await FirebaseFirestore.instance.doc(stationPath).get();

      if (!doc.exists || doc.data() == null) {
        debugPrint('📋 [SUBSCRIPTION] checkOnce: doc does not exist or data is null');
        return SubscriptionStatus.unknown;
      }

      final data = doc.data()!;
      debugPrint('📋 [SUBSCRIPTION] checkOnce: raw subscriptionEndDate = ${data['subscriptionEndDate']} (type: ${data['subscriptionEndDate']?.runtimeType})');

      final station = Station.fromJson({...data, 'id': doc.id});
      final endDate = station.subscriptionEndDate;
      debugPrint('📋 [SUBSCRIPTION] checkOnce: parsed endDate = $endDate');

      if (endDate == null) return SubscriptionStatus.unknown;

      final now = DateTime.now();
      if (now.isAfter(endDate)) return SubscriptionStatus.expired;
      if (endDate.difference(now).inDays <= 30) {
        return SubscriptionStatus.expiringSoon;
      }
      return SubscriptionStatus.active;
    } catch (e) {
      debugPrint('❌ [SUBSCRIPTION] Error checking: $e');
      return SubscriptionStatus.unknown;
    }
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _dailyCheckTimer?.cancel();
    _dailyCheckTimer = null;
  }
}
