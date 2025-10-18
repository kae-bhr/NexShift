import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// Service de logging pour le débogage
class DebugLogger {
  static final DebugLogger _instance = DebugLogger._internal();
  factory DebugLogger() => _instance;
  DebugLogger._internal() {
    // Intercepter tous les debugPrint de l'application
    _setupDebugPrintInterceptor();
  }

  final List<String> _logs = [];
  final int _maxLogs = 500; // Augmenté pour capturer plus de logs
  DebugPrintCallback? _originalDebugPrint;

  /// Configure l'interception de debugPrint
  void _setupDebugPrintInterceptor() {
    _originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        _addLogEntry(message);
      }
      // Appeler la fonction originale pour garder l'output console
      _originalDebugPrint?.call(message, wrapWidth: wrapWidth);
    };
  }

  /// Ajoute une entrée au log (interne, sans timestamp dupliqué)
  void _addLogEntry(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logEntry = '[$timestamp] $message';

    _logs.insert(0, logEntry);
    if (_logs.length > _maxLogs) {
      _logs.removeLast();
    }
  }

  /// Ajoute un log manuel
  void log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logEntry = '[$timestamp] $message';

    _logs.insert(0, logEntry);
    if (_logs.length > _maxLogs) {
      _logs.removeLast();
    }

    // Utiliser developer.log pour éviter la récursion
    developer.log(message);
  }

  /// Récupère tous les logs
  List<String> getLogs() => List.unmodifiable(_logs);

  /// Efface tous les logs
  void clear() => _logs.clear();

  /// Log spécifique pour FCM
  void logFCM(String message) {
    log('🔔 FCM: $message');
  }

  /// Log spécifique pour Firestore
  void logFirestore(String message) {
    log('🔥 Firestore: $message');
  }

  /// Log spécifique pour les erreurs
  void logError(String message) {
    log('❌ ERROR: $message');
  }

  /// Log spécifique pour les succès
  void logSuccess(String message) {
    log('✅ SUCCESS: $message');
  }
}
