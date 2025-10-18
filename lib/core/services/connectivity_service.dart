import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Service pour gérer la connectivité réseau
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final StreamController<bool> _connectivityController = StreamController<bool>.broadcast();
  Stream<bool> get connectivityStream => _connectivityController.stream;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Timer? _checkTimer;

  /// Démarre la vérification périodique de la connectivité
  void startMonitoring() {
    // Vérification immédiate
    _checkConnectivity();

    // Vérification toutes les 10 secondes
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkConnectivity();
    });
  }

  /// Arrête la vérification de la connectivité
  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  /// Vérifie la connectivité en tentant une connexion à Google DNS
  Future<void> _checkConnectivity() async {
    bool wasOnline = _isOnline;

    try {
      // Tenter une connexion à Google DNS (8.8.8.8) sur le port 53
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));

      _isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      _isOnline = false;
      debugPrint('Connectivity check failed: $e');
    }

    // Notifier seulement si le statut a changé
    if (wasOnline != _isOnline) {
      debugPrint('Connectivity changed: ${_isOnline ? "ONLINE" : "OFFLINE"}');
      _connectivityController.add(_isOnline);
    }
  }

  /// Nettoie les ressources
  void dispose() {
    stopMonitoring();
    _connectivityController.close();
  }
}
