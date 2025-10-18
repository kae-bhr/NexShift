import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

/// Service de gestion des logs
/// Sauvegarde les logs de la session courante et de la session précédente
/// Supprime les logs des sessions plus anciennes
class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  File? _currentLogFile;
  File? _previousLogFile;
  final List<String> _memoryBuffer = [];
  static const int _maxBufferSize = 100;

  /// Initialise le service de logs
  Future<void> initialize() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final logsDir = Directory('${directory.path}/logs');

      // Créer le dossier logs s'il n'existe pas
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      // Gérer la rotation des logs
      await _rotateLogs(logsDir);

      // Créer le fichier de log pour la session courante
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      _currentLogFile = File('${logsDir.path}/session_current_$timestamp.log');
      await _currentLogFile!.create();

      debugPrint('📝 Log service initialized: ${_currentLogFile!.path}');

      // Logger l'initialisation
      await log('=== SESSION STARTED ===', level: LogLevel.info);
      await log('App version: 1.0.0', level: LogLevel.info);
      await log('Platform: ${Platform.operatingSystem}', level: LogLevel.info);
    } catch (e) {
      debugPrint('❌ Error initializing log service: $e');
    }
  }

  /// Rotation des logs : garde session courante et précédente, supprime les plus anciennes
  Future<void> _rotateLogs(Directory logsDir) async {
    try {
      final files = await logsDir.list().toList();
      final logFiles = files
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();

      // Trier par date de modification (plus récent d'abord)
      logFiles.sort((a, b) =>
          b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      if (logFiles.isNotEmpty) {
        // Le plus récent devient le log précédent
        _previousLogFile = logFiles.first;
        debugPrint('📜 Previous log file: ${_previousLogFile!.path}');

        // Supprimer tous les fichiers sauf le plus récent
        for (var i = 1; i < logFiles.length; i++) {
          await logFiles[i].delete();
          debugPrint('🗑️ Deleted old log file: ${logFiles[i].path}');
        }

        // Renommer le fichier précédent
        final newPath = _previousLogFile!.path.replaceAll(
          RegExp(r'session_current_'),
          'session_previous_',
        );
        _previousLogFile = await _previousLogFile!.rename(newPath);
      }
    } catch (e) {
      debugPrint('❌ Error rotating logs: $e');
    }
  }

  /// Enregistre un message dans les logs
  Future<void> log(
    String message, {
    LogLevel level = LogLevel.debug,
    String? tag,
  }) async {
    try {
      final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
      final levelStr = level.toString().split('.').last.toUpperCase();
      final tagStr = tag != null ? '[$tag]' : '';
      final logLine = '$timestamp [$levelStr]$tagStr $message';

      // Ajouter au buffer en mémoire
      _memoryBuffer.add(logLine);
      if (_memoryBuffer.length > _maxBufferSize) {
        await _flushBuffer();
      }

      // Afficher dans la console en debug
      if (kDebugMode) {
        switch (level) {
          case LogLevel.error:
            debugPrint('❌ $logLine');
            break;
          case LogLevel.warning:
            debugPrint('⚠️ $logLine');
            break;
          case LogLevel.info:
            debugPrint('ℹ️ $logLine');
            break;
          case LogLevel.debug:
            debugPrint('🐛 $logLine');
            break;
        }
      }
    } catch (e) {
      debugPrint('❌ Error logging message: $e');
    }
  }

  /// Vide le buffer en mémoire vers le fichier
  Future<void> _flushBuffer() async {
    if (_currentLogFile == null || _memoryBuffer.isEmpty) return;

    try {
      final content = '${_memoryBuffer.join('\n')}\n';
      await _currentLogFile!.writeAsString(
        content,
        mode: FileMode.append,
      );
      _memoryBuffer.clear();
    } catch (e) {
      debugPrint('❌ Error flushing log buffer: $e');
    }
  }

  /// Ferme proprement le service de logs
  Future<void> close() async {
    try {
      await log('=== SESSION ENDED ===', level: LogLevel.info);
      await _flushBuffer();
    } catch (e) {
      debugPrint('❌ Error closing log service: $e');
    }
  }

  /// Récupère le contenu des logs de la session courante
  Future<String?> getCurrentSessionLogs() async {
    try {
      await _flushBuffer();
      if (_currentLogFile == null || !await _currentLogFile!.exists()) {
        return null;
      }
      return await _currentLogFile!.readAsString();
    } catch (e) {
      debugPrint('❌ Error reading current session logs: $e');
      return null;
    }
  }

  /// Récupère le contenu des logs de la session précédente
  Future<String?> getPreviousSessionLogs() async {
    try {
      if (_previousLogFile == null || !await _previousLogFile!.exists()) {
        return null;
      }
      return await _previousLogFile!.readAsString();
    } catch (e) {
      debugPrint('❌ Error reading previous session logs: $e');
      return null;
    }
  }

  /// Récupère les chemins des fichiers de logs
  Future<Map<String, String?>> getLogFilePaths() async {
    return {
      'current': _currentLogFile?.path,
      'previous': _previousLogFile?.path,
    };
  }
}

/// Niveau de log
enum LogLevel {
  debug,
  info,
  warning,
  error,
}
