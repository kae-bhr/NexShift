import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/models/position_model.dart';
import '../config/environment_config.dart';

class PositionRepository {
  static const _collectionName = 'positions';
  final FirebaseFirestore _firestore;

  PositionRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Retourne le chemin de collection selon l'environnement et la station
  String _getCollectionPath(String stationId) {
    return EnvironmentConfig.getCollectionPath(_collectionName, stationId);
  }

  /// Récupère toutes les positions d'une caserne
  Stream<List<Position>> getPositionsByStation(String stationId) {
    final collectionPath = _getCollectionPath(stationId);
    return _firestore
        .collection(collectionPath)
        .orderBy('order')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Position.fromFirestore(doc)).toList());
  }

  /// Récupère une position par son ID
  Future<Position?> getPositionById(String positionId, {String? stationId}) async {
    // En mode dev, stationId est requis
    if (stationId == null) {
      throw Exception('stationId required for getPositionById');
    }

    final collectionPath = _getCollectionPath(stationId);
    final doc = await _firestore.collection(collectionPath).doc(positionId).get();
    if (!doc.exists) return null;
    return Position.fromFirestore(doc);
  }

  /// Crée une nouvelle position
  Future<String> createPosition(Position position, {String? stationId}) async {
    // En mode dev, utiliser stationId depuis position ou paramètre
    final station = stationId ?? position.stationId;
    final collectionPath = _getCollectionPath(station);
    final docRef = await _firestore
        .collection(collectionPath)
        .add(position.toFirestore());
    return docRef.id;
  }

  /// Met à jour une position existante
  Future<void> updatePosition(Position position, {String? stationId}) async {
    // En mode dev, utiliser stationId depuis position ou paramètre
    final station = stationId ?? position.stationId;
    final collectionPath = _getCollectionPath(station);
    await _firestore
        .collection(collectionPath)
        .doc(position.id)
        .update(position.toFirestore());
  }

  /// Supprime une position
  Future<void> deletePosition(String positionId, {String? stationId}) async {
    if (stationId == null) {
      throw Exception('stationId required for deletePosition');
    }

    final collectionPath = _getCollectionPath(stationId);
    await _firestore.collection(collectionPath).doc(positionId).delete();
  }

  /// Réordonne les positions d'une caserne
  Future<void> reorderPositions(
      String stationId, List<Position> positions) async {
    final collectionPath = _getCollectionPath(stationId);
    final batch = _firestore.batch();

    for (int i = 0; i < positions.length; i++) {
      final position = positions[i].copyWith(order: i);
      batch.update(
        _firestore.collection(collectionPath).doc(position.id),
        {'order': i},
      );
    }

    await batch.commit();
  }
}
