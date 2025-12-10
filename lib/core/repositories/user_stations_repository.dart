import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/models/user_stations_model.dart';

/// Repository pour gérer la collection user_stations
/// Supporte à la fois l'architecture racine (legacy) et l'architecture SDIS
class UserStationsRepository {
  static const String _collectionName = 'user_stations';
  final FirebaseFirestore _firestore;

  UserStationsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Construit la référence vers la collection user_stations
  /// Si sdisId est fourni: /sdis/{sdisId}/user_stations
  /// Sinon (legacy): /user_stations
  CollectionReference _getCollection(String? sdisId) {
    if (sdisId != null && sdisId.isNotEmpty) {
      return _firestore.collection('sdis/$sdisId/$_collectionName');
    }
    return _firestore.collection(_collectionName);
  }

  /// Récupère les stations d'un utilisateur
  /// Retourne null si l'utilisateur n'existe pas dans la collection
  Future<UserStations?> getUserStations(String userId, {String? sdisId}) async {
    try {
      final doc = await _getCollection(sdisId).doc(userId).get();

      if (!doc.exists) {
        return null;
      }

      final data = doc.data() as Map<String, dynamic>;
      data['userId'] = doc.id;
      return UserStations.fromJson(data);
    } catch (e) {
      debugPrint('Error getting user stations: $e');
      return null;
    }
  }

  /// Crée ou met à jour le mapping pour un utilisateur
  Future<void> setUserStations(
    String userId,
    List<String> stations, {
    String? sdisId,
  }) async {
    try {
      // IMPORTANT: Utiliser merge: true pour ne PAS écraser les autres champs
      // (firstName, lastName, fcmToken, etc.)
      await _getCollection(sdisId).doc(userId).set({
        'userId': userId,
        'stations': stations,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error setting user stations: $e');
      rethrow;
    }
  }

  /// Crée ou met à jour un document user_stations complet avec toutes les données
  Future<void> createOrUpdateUserStations(
    UserStations userStations, {
    String? sdisId,
  }) async {
    try {
      await _getCollection(sdisId)
          .doc(userStations.userId)
          .set(userStations.toJson());
    } catch (e) {
      debugPrint('Error creating/updating user stations: $e');
      rethrow;
    }
  }

  /// Ajoute une station à un utilisateur existant
  Future<void> addStationToUser(
    String userId,
    String stationId, {
    String? sdisId,
  }) async {
    try {
      final userStations = await getUserStations(userId, sdisId: sdisId);

      if (userStations == null) {
        // Créer le mapping avec cette station
        await setUserStations(userId, [stationId], sdisId: sdisId);
      } else {
        // Ajouter la station si elle n'existe pas déjà
        if (!userStations.stations.contains(stationId)) {
          final updatedStations = [...userStations.stations, stationId];
          await setUserStations(userId, updatedStations, sdisId: sdisId);
        }
      }
    } catch (e) {
      debugPrint('Error adding station to user: $e');
      rethrow;
    }
  }

  /// Retire une station d'un utilisateur
  Future<void> removeStationFromUser(
    String userId,
    String stationId, {
    String? sdisId,
  }) async {
    try {
      final userStations = await getUserStations(userId, sdisId: sdisId);

      if (userStations != null) {
        final updatedStations = userStations.stations
            .where((station) => station != stationId)
            .toList();

        if (updatedStations.isEmpty) {
          // Supprimer le document si aucune station ne reste
          await _getCollection(sdisId).doc(userId).delete();
        } else {
          await setUserStations(userId, updatedStations, sdisId: sdisId);
        }
      }
    } catch (e) {
      debugPrint('Error removing station from user: $e');
      rethrow;
    }
  }

  /// Récupère tous les utilisateurs d'une station
  /// Utile pour les admins qui veulent voir qui a accès à leur station
  Future<List<String>> getUsersInStation(
    String stationId, {
    String? sdisId,
  }) async {
    try {
      final snapshot = await _getCollection(sdisId)
          .where('stations', arrayContains: stationId)
          .get();

      return snapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      debugPrint('Error getting users in station: $e');
      return [];
    }
  }
}
