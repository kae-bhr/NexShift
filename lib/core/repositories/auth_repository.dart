import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/auth_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';

/// Repository pour gérer les licences et authentifications
class AuthRepository {
  static const String _collectionName = 'auth';
  final FirestoreService _firestore = FirestoreService();

  /// Récupère une licence par son numéro
  Future<Auth?> getLicence(String licenceNumber) async {
    try {
      debugPrint('🔍 [AuthRepository] Searching for licence: $licenceNumber');
      debugPrint('🔍 [AuthRepository] Collection: $_collectionName');

      // Use Firestore directly to avoid FirestoreService overwriting 'id' field
      final doc = await FirebaseFirestore.instance
          .collection(_collectionName)
          .doc(licenceNumber)
          .get();

      if (!doc.exists) {
        debugPrint('❌ [AuthRepository] No data found for licence: $licenceNumber');
        return null;
      }

      final data = doc.data();
      if (data == null) {
        debugPrint('❌ [AuthRepository] Document exists but has no data: $licenceNumber');
        return null;
      }

      debugPrint('🔍 [AuthRepository] Data received: $data');

      final auth = Auth.fromJson(data);
      debugPrint('✅ [AuthRepository] Licence found: ${auth.licence}, id: ${auth.id}, station: ${auth.station}, consumed: ${auth.consumed}');
      return auth;
    } catch (e, stackTrace) {
      debugPrint('❌ [AuthRepository] Error getting licence: $e');
      debugPrint('❌ [AuthRepository] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Crée une nouvelle licence
  Future<void> createLicence(Auth auth) async {
    await _firestore.upsert(_collectionName, auth.licence, auth.toJson());
  }

  /// Met à jour une licence existante
  Future<void> updateLicence(Auth auth) async {
    await _firestore.upsert(_collectionName, auth.licence, auth.toJson());
  }

  /// Supprime une licence
  Future<void> deleteLicence(String licenceNumber) async {
    await _firestore.delete(_collectionName, licenceNumber);
  }

  /// Vérifie si une licence existe et est valide
  Future<bool> validateLicence(String licenceNumber) async {
    final auth = await getLicence(licenceNumber);
    return auth != null;
  }
}
