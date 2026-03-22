import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/team_event_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';
import 'package:nexshift_app/core/config/environment_config.dart';

/// Repository pour les événements d'équipe/caserne.
/// Chemin Firestore : /sdis/{sdisId}/stations/{stationId}/teamEvents/{eventId}
class TeamEventRepository {
  final FirestoreService _firestoreService;

  TeamEventRepository({FirestoreService? firestoreService})
      : _firestoreService = firestoreService ?? FirestoreService();

  String _getCollectionPath(String stationId) {
    final path = EnvironmentConfig.getCollectionPath('teamEvents', stationId);
    debugPrint('🗂️ [TeamEventRepository] path = $path');
    return path;
  }

  // ============================================================================
  // LECTURE
  // ============================================================================

  /// Récupère tous les événements d'une station.
  Future<List<TeamEvent>> getAll({required String stationId}) async {
    try {
      final path = _getCollectionPath(stationId);
      final data = await _firestoreService.getAll(path);
      final results = <TeamEvent>[];
      for (final e in data) {
        try {
          results.add(TeamEvent.fromJson(e));
        } catch (parseErr) {
          debugPrint('⚠️ TeamEventRepository.getAll parse error on ${e['id']}: $parseErr');
        }
      }
      return results;
    } catch (e) {
      debugPrint('TeamEventRepository.getAll error: $e');
      return [];
    }
  }

  /// Récupère un événement par ID.
  Future<TeamEvent?> getById({
    required String eventId,
    required String stationId,
  }) async {
    try {
      final path = _getCollectionPath(stationId);
      final data = await _firestoreService.getById(path, eventId);
      return data != null ? TeamEvent.fromJson(data) : null;
    } catch (e) {
      debugPrint('TeamEventRepository.getById error: $e');
      rethrow;
    }
  }

  /// Stream temps réel de tous les événements d'une station, triés par startTime décroissant.
  Stream<List<TeamEvent>> watchAll({required String stationId}) {
    final path = _getCollectionPath(stationId);
    return FirebaseFirestore.instance
        .collection(path)
        .orderBy('startTime', descending: true)
        .snapshots()
        .map((snapshot) {
          final results = <TeamEvent>[];
          for (final doc in snapshot.docs) {
            try {
              final data = doc.data();
              data['id'] = doc.id;
              results.add(TeamEvent.fromJson(data));
            } catch (e) {
              debugPrint('⚠️ TeamEvent.fromJson error on ${doc.id}: $e');
            }
          }
          return results;
        });
  }

  /// Stream des événements à venir (pour pastilles de badge).
  Stream<List<TeamEvent>> watchUpcoming({required String stationId}) {
    final path = _getCollectionPath(stationId);
    return FirebaseFirestore.instance
        .collection(path)
        .where('status', isEqualTo: 'upcoming')
        .orderBy('startTime', descending: false)
        .snapshots()
        .map((snapshot) {
          final results = <TeamEvent>[];
          for (final doc in snapshot.docs) {
            try {
              final data = doc.data();
              data['id'] = doc.id;
              results.add(TeamEvent.fromJson(data));
            } catch (e) {
              debugPrint('⚠️ TeamEvent.fromJson error on ${doc.id}: $e');
            }
          }
          return results;
        });
  }

  /// Stream d'un événement unique — se met à jour en temps réel.
  Stream<TeamEvent?> watchById({
    required String eventId,
    required String stationId,
  }) {
    final path = _getCollectionPath(stationId);
    return FirebaseFirestore.instance
        .collection(path)
        .doc(eventId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      final data = doc.data()!;
      data['id'] = doc.id;
      return TeamEvent.fromJson(data);
    });
  }

  // ============================================================================
  // ÉCRITURE
  // ============================================================================

  /// Crée un nouvel événement et retourne son ID.
  Future<String> create({
    required TeamEvent event,
    required String stationId,
  }) async {
    try {
      final path = _getCollectionPath(stationId);
      await _firestoreService.upsert(path, event.id, event.toJson());
      return event.id;
    } catch (e) {
      debugPrint('TeamEventRepository.create error: $e');
      rethrow;
    }
  }

  /// Met à jour un événement existant (remplacement complet).
  Future<void> update({
    required TeamEvent event,
    required String stationId,
  }) async {
    try {
      final path = _getCollectionPath(stationId);
      await _firestoreService.upsert(path, event.id, event.toJson());
    } catch (e) {
      debugPrint('TeamEventRepository.update error: $e');
      rethrow;
    }
  }

  /// Met à jour des champs spécifiques d'un événement (évite les écrasements concurrents).
  Future<void> updateFields({
    required String eventId,
    required String stationId,
    required Map<String, dynamic> fields,
  }) async {
    try {
      final path = _getCollectionPath(stationId);
      await FirebaseFirestore.instance.collection(path).doc(eventId).update(fields);
    } catch (e) {
      debugPrint('TeamEventRepository.updateFields error: $e');
      rethrow;
    }
  }

  /// Annule un événement.
  Future<void> cancel({
    required String eventId,
    required String stationId,
  }) async {
    try {
      await updateFields(
        eventId: eventId,
        stationId: stationId,
        fields: {
          'status': 'cancelled',
          'cancelledAt': Timestamp.fromDate(DateTime.now()),
        },
      );
    } catch (e) {
      debugPrint('TeamEventRepository.cancel error: $e');
      rethrow;
    }
  }

  /// Supprime un événement.
  Future<void> delete({
    required String eventId,
    required String stationId,
  }) async {
    try {
      final path = _getCollectionPath(stationId);
      await _firestoreService.delete(path, eventId);
    } catch (e) {
      debugPrint('TeamEventRepository.delete error: $e');
      rethrow;
    }
  }

  /// Répare les documents dont startTime/endTime sont stockés en String ISO
  /// au lieu de Timestamp Firestore (suite à un bug d'updateFields).
  Future<void> repairCorruptedDocuments({required String stationId}) async {
    final path = _getCollectionPath(stationId);
    final snapshot = await FirebaseFirestore.instance.collection(path).get();
    int repaired = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final start = data['startTime'];
      final end = data['endTime'];
      if (start is String || end is String) {
        try {
          final fields = <String, dynamic>{};
          if (start is String) {
            fields['startTime'] = Timestamp.fromDate(DateTime.parse(start));
          }
          if (end is String) {
            fields['endTime'] = Timestamp.fromDate(DateTime.parse(end));
          }
          await doc.reference.update(fields);
          repaired++;
          debugPrint('✅ [TeamEventRepository] Repaired doc ${doc.id}');
        } catch (e) {
          debugPrint('⚠️ [TeamEventRepository] Could not repair ${doc.id}: $e');
        }
      }
    }
    debugPrint('🔧 [TeamEventRepository] Repair done: $repaired document(s) fixed');
  }
}
