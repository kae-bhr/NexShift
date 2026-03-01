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
  DebugPrintCallback? _originalDebugPrint;

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

      // Intercepter tous les debugPrint
      _originalDebugPrint = debugPrint;
      debugPrint = _customDebugPrint;

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
        final mostRecent = logFiles.first;

        // Vérifier si le fichier est déjà renommé en "previous"
        if (mostRecent.path.contains('session_previous_')) {
          // Si déjà en "previous", le garder tel quel
          _previousLogFile = mostRecent;
          debugPrint('📜 Found previous log file: ${_previousLogFile!.path}');
        } else if (mostRecent.path.contains('session_current_')) {
          // Si c'est un "current", le renommer en "previous"
          final newPath = mostRecent.path.replaceAll(
            RegExp(r'session_current_'),
            'session_previous_',
          );
          _previousLogFile = await mostRecent.rename(newPath);
          debugPrint('📜 Renamed to previous log: ${_previousLogFile!.path}');
        }

        // Supprimer tous les autres fichiers (index 1 et plus)
        for (var i = 1; i < logFiles.length; i++) {
          await logFiles[i].delete();
          debugPrint('🗑️ Deleted old log file: ${logFiles[i].path}');
        }
      }
    } catch (e) {
      debugPrint('❌ Error rotating logs: $e');
    }
  }

  /// Gestionnaire personnalisé pour capturer tous les debugPrint
  void _customDebugPrint(String? message, {int? wrapWidth}) {
    // Console uniquement en mode DEBUG pour ne pas impacter les perfs en prod
    if (kDebugMode) {
      _originalDebugPrint?.call(message, wrapWidth: wrapWidth);
    }

    // Capturer dans le fichier (toujours, pour diagnostic post-crash en prod)
    if (message != null && message.isNotEmpty) {
      _logToFile(message);
    }
  }

  /// Enregistre un message dans le fichier (version synchrone pour debugPrint)
  void _logToFile(String message) {
    try {
      final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
      final logLine = '$timestamp [DEBUG] $message';

      // Ajouter au buffer en mémoire
      _memoryBuffer.add(logLine);

      // Flush plus agressif : tous les 20 messages au lieu de 100
      if (_memoryBuffer.length >= 20) {
        _flushBuffer();
      }
    } catch (e) {
      _originalDebugPrint?.call('❌ Error logging to file: $e');
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

      // Flush plus agressif
      if (_memoryBuffer.length >= 20) {
        await _flushBuffer();
      }

      // Afficher dans la console en debug (sans emoji pour éviter double capture)
      if (kDebugMode) {
        _originalDebugPrint?.call('[$levelStr]$tagStr $message');
      }
    } catch (e) {
      _originalDebugPrint?.call('❌ Error logging message: $e');
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

      // Restaurer le debugPrint original
      if (_originalDebugPrint != null) {
        debugPrint = _originalDebugPrint!;
      }
    } catch (e) {
      _originalDebugPrint?.call('❌ Error closing log service: $e');
    }
  }

  /// Filtre les lignes [DEBUG] pour n'afficher que les logs significatifs
  String _filterDebugLines(String content) {
    return content
        .split('\n')
        .where((line) => !line.contains('[DEBUG]'))
        .join('\n');
  }

  /// Récupère le contenu des logs de la session courante
  Future<String?> getCurrentSessionLogs() async {
    try {
      await _flushBuffer();
      if (_currentLogFile == null || !await _currentLogFile!.exists()) {
        return null;
      }
      final content = await _currentLogFile!.readAsString();
      return _filterDebugLines(content);
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
      final content = await _previousLogFile!.readAsString();
      return _filterDebugLines(content);
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
