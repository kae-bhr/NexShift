import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';

/// Service qui vérifie si le build courant est suffisamment récent.
///
/// ### Document Firestore : `app_config/version`
/// - `minBuildNumber` (int) : numéro de build minimum requis
/// - `androidStoreUrl` (String) : URL Play Store
/// - `iosStoreUrl` (String) : URL App Store
/// - `message` (String) : message affiché à l'utilisateur
class VersionCheckService {
  VersionCheckService._();
  static final VersionCheckService _instance = VersionCheckService._();
  factory VersionCheckService() => _instance;

  String _storeUrl = '';
  String _message = 'Une nouvelle version est disponible. Veuillez mettre à jour l\'application pour continuer.';

  String get storeUrl => _storeUrl;
  String get message => _message;

  /// Lecture one-shot du document `app_config/version`.
  /// Met à jour [isUpdateRequiredNotifier] selon le résultat.
  /// En cas d'erreur réseau, ne bloque pas l'utilisateur (fail open).
  Future<void> checkOnce() async {
    try {
      final doc = await FirebaseFirestore.instance
          .doc('app_config/version')
          .get();

      if (!doc.exists) {
        debugPrint('ℹ️ [VERSION] app_config/version introuvable — pas de blocage');
        isUpdateRequiredNotifier.value = false;
        return;
      }

      final data = doc.data();
      if (data == null) {
        isUpdateRequiredNotifier.value = false;
        return;
      }

      final minBuildNumber = data['minBuildNumber'] as int? ?? 0;
      final androidUrl = (data['androidStoreUrl'] as String?) ?? '';
      final iosUrl = (data['iosStoreUrl'] as String?) ?? '';
      final msg = (data['message'] as String?) ?? _message;

      _message = msg;
      _storeUrl = Platform.isAndroid ? androidUrl : iosUrl;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      debugPrint(
          '🔍 [VERSION] currentBuild=$currentBuild, minBuildNumber=$minBuildNumber');

      isUpdateRequiredNotifier.value = currentBuild < minBuildNumber;

      if (isUpdateRequiredNotifier.value) {
        debugPrint('🚫 [VERSION] Build $currentBuild < $minBuildNumber — mise à jour requise');
      } else {
        debugPrint('✅ [VERSION] Build $currentBuild OK');
      }
    } catch (e) {
      // Fail open : en cas d'erreur, on ne bloque pas l'utilisateur
      debugPrint('⚠️ [VERSION] Erreur lors du check version (non-bloquant): $e');
      isUpdateRequiredNotifier.value = false;
    }
  }
}
