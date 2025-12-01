import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';

class UserRepository {
  static const _collectionName = 'users';
  final FirestoreService _firestoreService;
  final FirebaseFirestore? _directFirestore;

  /// Constructeur par défaut (production)
  UserRepository({FirestoreService? firestoreService})
      : _firestoreService = firestoreService ?? FirestoreService(),
        _directFirestore = null;

  /// Constructeur pour les tests avec Firestore direct
  UserRepository.forTest(FirebaseFirestore firestore)
      : _directFirestore = firestore,
        _firestoreService = FirestoreService();

  /// Récupère tous les utilisateurs depuis Firestore
  Future<List<User>> getAll() async {
    try {
      // Mode test : utiliser directement FirebaseFirestore
      if (_directFirestore != null) {
        final snapshot = await _directFirestore!.collection(_collectionName).get();
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return User.fromJson(data);
        }).toList();
      }

      // Mode production : utiliser FirestoreService
      final data = await _firestoreService.getAll(_collectionName);
      return data.map((e) => User.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAll: $e');
      rethrow;
    }
  }

  /// Récupère un utilisateur par son ID
  Future<User?> getById(String id) async {
    try {
      // Mode test : utiliser directement FirebaseFirestore
      if (_directFirestore != null) {
        final doc = await _directFirestore!.collection(_collectionName).doc(id).get();
        if (!doc.exists) return null;
        final data = doc.data()!;
        data['id'] = doc.id;
        return User.fromJson(data);
      }

      // Mode production : utiliser FirestoreService
      final data = await _firestoreService.getById(_collectionName, id);
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
      // Mode test : utiliser directement FirebaseFirestore
      if (_directFirestore != null) {
        final batch = _directFirestore.batch();
        for (final user in users) {
          batch.set(
            _directFirestore.collection(_collectionName).doc(user.id),
            user.toJson(),
          );
        }
        await batch.commit();
        return;
      }

      // Mode production : utiliser FirestoreService
      final operations = users.map((user) => {
        'type': 'set',
        'collection': _collectionName,
        'id': user.id,
        'data': user.toJson(),
      }).toList();
      await _firestoreService.batchWrite(operations);
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

      // Mode test : utiliser directement FirebaseFirestore
      if (_directFirestore != null) {
        await _directFirestore.collection(_collectionName).doc(user.id).set(user.toJson());
        debugPrint('✅ [UserRepository] User ${user.id} upserted successfully');
        return;
      }

      // Mode production : utiliser FirestoreService
      await _firestoreService.upsert(_collectionName, user.id, user.toJson());
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
      // Mode test : utiliser directement FirebaseFirestore
      if (_directFirestore != null) {
        await _directFirestore.collection(_collectionName).doc(id).delete();
        return;
      }

      // Mode production : utiliser FirestoreService
      await _firestoreService.delete(_collectionName, id);
    } catch (e) {
      debugPrint('Firestore error during delete: $e');
      rethrow;
    }
  }

  /// Supprime tous les utilisateurs
  Future<void> clear() async {
    try {
      final all = await getAll();

      // Mode test : utiliser directement FirebaseFirestore
      if (_directFirestore != null) {
        final batch = _directFirestore.batch();
        for (final u in all) {
          batch.delete(_directFirestore.collection(_collectionName).doc(u.id));
        }
        await batch.commit();
        return;
      }

      // Mode production : utiliser FirestoreService
      final operations = all.map((u) => {
        'type': 'delete',
        'collection': _collectionName,
        'id': u.id,
      }).toList();
      await _firestoreService.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during clear: $e');
      rethrow;
    }
  }
}
