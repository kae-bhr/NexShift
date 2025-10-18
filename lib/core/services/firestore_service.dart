import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Service de base pour interagir avec Firestore
/// Fournit des méthodes génériques pour les opérations CRUD
class FirestoreService {
  /// Récupère une instance de Firestore (lazy loading)
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Récupère une instance de Firestore
  FirebaseFirestore get firestore => _firestore;

  /// Récupère tous les documents d'une collection
  Future<List<Map<String, dynamic>>> getAll(String collection) async {
    try {
      final snapshot = await _firestore.collection(collection).get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Error fetching $collection: $e');
    }
  }

  /// Récupère un document par son ID
  Future<Map<String, dynamic>?> getById(String collection, String id) async {
    try {
      final doc = await _firestore.collection(collection).doc(id).get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data != null) {
        data['id'] = doc.id;
      }
      return data;
    } catch (e) {
      throw Exception('Error fetching $collection/$id: $e');
    }
  }

  /// Récupère des documents avec une condition where
  Future<List<Map<String, dynamic>>> getWhere(
    String collection,
    String field,
    dynamic value,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(collection)
          .where(field, isEqualTo: value)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Error fetching $collection where $field=$value: $e');
    }
  }

  /// Récupère des documents avec plusieurs conditions where
  Future<List<Map<String, dynamic>>> getWhereMultiple(
    String collection,
    Map<String, dynamic> conditions,
  ) async {
    try {
      Query query = _firestore.collection(collection);
      conditions.forEach((field, value) {
        query = query.where(field, isEqualTo: value);
      });
      final snapshot = await query.get();
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Error fetching $collection with conditions: $e');
    }
  }

  /// Récupère des documents dans une plage de dates
  /// Utilise un index composite pour de meilleures performances
  Future<List<Map<String, dynamic>>> getInDateRange(
    String collection,
    String startField,
    String endField,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) async {
    return await _getInDateRangeFallback(
      collection,
      startField,
      endField,
      rangeStart,
      rangeEnd,
    );
  }

  /// Fallback: Récupère tous les documents et filtre en mémoire
  Future<List<Map<String, dynamic>>> _getInDateRangeFallback(
    String collection,
    String startField,
    String endField,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) async {
    try {
      final snapshot = await _firestore.collection(collection).get();

      final filtered = <Map<String, dynamic>>[];

      for (var doc in snapshot.docs) {
        try {
          final data = doc.data();

          if (!data.containsKey(startField) || !data.containsKey(endField)) {
            continue;
          }

          // Gérer les deux formats: Timestamp et String
          DateTime? startTime;
          DateTime? endTime;

          final startValue = data[startField];
          final endValue = data[endField];

          // Conversion du startField
          if (startValue is Timestamp) {
            startTime = startValue.toDate();
          } else if (startValue is String) {
            try {
              startTime = DateTime.parse(startValue);
            } catch (_) {
              continue;
            }
          } else {
            continue;
          }

          // Conversion du endField
          if (endValue is Timestamp) {
            endTime = endValue.toDate();
          } else if (endValue is String) {
            try {
              endTime = DateTime.parse(endValue);
            } catch (_) {
              continue;
            }
          } else {
            continue;
          }

          // Vérifier le chevauchement avec la plage
          final overlaps =
              endTime.isAfter(rangeStart) && startTime.isBefore(rangeEnd);

          if (overlaps) {
            final resultData = Map<String, dynamic>.from(data);
            resultData['id'] = doc.id;
            filtered.add(resultData);
          }
        } catch (e) {
          // Ignorer les documents avec des erreurs de parsing
          continue;
        }
      }

      return filtered;
    } catch (e) {
      throw Exception('Error fetching $collection in date range: $e');
    }
  }

  /// Crée ou met à jour un document
  Future<void> upsert(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) async {
    try {
      debugPrint('🔄 [FirestoreService] Upserting $collection/$id');
      debugPrint('   Using set(merge: true)');

      // Log current user
      final currentUser = FirebaseAuth.instance.currentUser;
      debugPrint('   Current user: ${currentUser?.email} (uid: ${currentUser?.uid})');

      // Check if document exists
      final docSnapshot = await _firestore.collection(collection).doc(id).get();
      debugPrint('   Document exists: ${docSnapshot.exists}');

      // If user document, load and log the current user's permissions
      if (collection == 'users' && currentUser != null) {
        final currentUserDoc = await _firestore.collection('users').doc(currentUser.uid).get();
        if (currentUserDoc.exists) {
          final userData = currentUserDoc.data();
          debugPrint('   Current user admin: ${userData?['admin']}');
          debugPrint('   Current user status: ${userData?['status']}');
        } else {
          debugPrint('   ⚠️ Current user document does not exist in Firestore!');
        }
      }

      await _firestore
          .collection(collection)
          .doc(id)
          .set(data, SetOptions(merge: true));
      debugPrint('✅ [FirestoreService] Successfully upserted $collection/$id');
    } catch (e) {
      debugPrint('❌ [FirestoreService] Error upserting $collection/$id');
      debugPrint('   Error: $e');
      debugPrint('   Error type: ${e.runtimeType}');
      throw Exception('Error upserting $collection/$id: $e');
    }
  }

  /// Crée un nouveau document avec un ID auto-généré
  Future<String> create(String collection, Map<String, dynamic> data) async {
    try {
      final docRef = await _firestore.collection(collection).add(data);
      return docRef.id;
    } catch (e) {
      throw Exception('Error creating document in $collection: $e');
    }
  }

  /// Supprime un document
  Future<void> delete(String collection, String id) async {
    try {
      await _firestore.collection(collection).doc(id).delete();
    } catch (e) {
      throw Exception('Error deleting $collection/$id: $e');
    }
  }

  /// Supprime tous les documents correspondant à une condition
  Future<void> deleteWhere(
    String collection,
    String field,
    dynamic value,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(collection)
          .where(field, isEqualTo: value)
          .get();
      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      throw Exception('Error deleting $collection where $field=$value: $e');
    }
  }

  /// Écoute les changements sur une collection
  Stream<List<Map<String, dynamic>>> streamCollection(String collection) {
    return _firestore
        .collection(collection)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList(),
        );
  }

  /// Écoute les changements sur un document spécifique
  Stream<Map<String, dynamic>?> streamDocument(String collection, String id) {
    return _firestore.collection(collection).doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data();
      if (data != null) {
        data['id'] = doc.id;
      }
      return data;
    });
  }

  /// Effectue une opération batch (transaction multiple)
  Future<void> batchWrite(List<Map<String, dynamic>> operations) async {
    try {
      final batch = _firestore.batch();
      for (var operation in operations) {
        final type = operation['type'] as String;
        final collection = operation['collection'] as String;
        final id = operation['id'] as String?;
        final data = operation['data'] as Map<String, dynamic>?;

        switch (type) {
          case 'set':
            if (id != null && data != null) {
              batch.set(
                _firestore.collection(collection).doc(id),
                data,
                SetOptions(merge: true),
              );
            }
            break;
          case 'delete':
            if (id != null) {
              batch.delete(_firestore.collection(collection).doc(id));
            }
            break;
        }
      }
      await batch.commit();
    } catch (e) {
      throw Exception('Error executing batch write: $e');
    }
  }
}
