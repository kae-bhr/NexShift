import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/models/sdis_model.dart';

/// Repository pour gérer la collection racine sdis_list
/// Cette collection contient la liste des SDIS disponibles dans l'application
class SDISRepository {
  static const String _collectionName = 'sdis_list';
  final FirebaseFirestore _firestore;

  SDISRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Récupère la liste de tous les SDIS disponibles
  Future<List<SDIS>> getAllSDIS() async {
    try {
      final snapshot = await _firestore.collection(_collectionName).get();

      return snapshot.docs
          .map((doc) => SDIS.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    } catch (e) {
      debugPrint('Error getting all SDIS: $e');
      return [];
    }
  }

  /// Récupère un SDIS par son ID
  Future<SDIS?> getById(String sdisId) async {
    try {
      final doc = await _firestore.collection(_collectionName).doc(sdisId).get();

      if (!doc.exists) {
        return null;
      }

      return SDIS.fromJson({...doc.data()!, 'id': doc.id});
    } catch (e) {
      debugPrint('Error getting SDIS by ID: $e');
      return null;
    }
  }

  /// Crée ou met à jour un SDIS
  Future<void> createOrUpdate(SDIS sdis) async {
    try {
      await _firestore.collection(_collectionName).doc(sdis.id).set(sdis.toJson());
    } catch (e) {
      debugPrint('Error creating/updating SDIS: $e');
      rethrow;
    }
  }

  /// Supprime un SDIS
  Future<void> delete(String sdisId) async {
    try {
      await _firestore.collection(_collectionName).doc(sdisId).delete();
    } catch (e) {
      debugPrint('Error deleting SDIS: $e');
      rethrow;
    }
  }
}
