import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';

class UserRepository {
  static const _collectionName = 'users';
  final FirestoreService _firestore = FirestoreService();

  /// Récupère tous les utilisateurs depuis Firestore
  Future<List<User>> getAll() async {
    try {
      final data = await _firestore.getAll(_collectionName);
      return data.map((e) => User.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAll: $e');
      rethrow;
    }
  }

  /// Récupère un utilisateur par son ID
  Future<User?> getById(String id) async {
    try {
      final data = await _firestore.getById(_collectionName, id);
      if (data != null) {
        return User.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Firestore error in getById: $e');
      rethrow;
    }
  }

  /// Sauvegarde tous les utilisateurs
  Future<void> saveAll(List<User> users) async {
    try {
      final operations = users.map((user) => {
        'type': 'set',
        'collection': _collectionName,
        'id': user.id,
        'data': user.toJson(),
      }).toList();
      await _firestore.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during saveAll: $e');
      rethrow;
    }
  }

  /// Met à jour ou insère un utilisateur
  Future<void> upsert(User user) async {
    try {
      debugPrint('🔄 [UserRepository] Upserting user ${user.id}');
      debugPrint('   Data: firstName=${user.firstName}, lastName=${user.lastName}, team=${user.team}, status=${user.status}, station=${user.station}');
      await _firestore.upsert(_collectionName, user.id, user.toJson());
      debugPrint('✅ [UserRepository] User ${user.id} upserted successfully');
    } catch (e) {
      debugPrint('❌ [UserRepository] Firestore error during upsert: $e');
      debugPrint('   User ID: ${user.id}');
      debugPrint('   Error type: ${e.runtimeType}');
      rethrow;
    }
  }

  /// Supprime un utilisateur
  Future<void> delete(String id) async {
    try {
      await _firestore.delete(_collectionName, id);
    } catch (e) {
      debugPrint('Firestore error during delete: $e');
      rethrow;
    }
  }

  /// Supprime tous les utilisateurs
  Future<void> clear() async {
    try {
      final all = await getAll();
      final operations = all.map((u) => {
        'type': 'delete',
        'collection': _collectionName,
        'id': u.id,
      }).toList();
      await _firestore.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during clear: $e');
      rethrow;
    }
  }
}
