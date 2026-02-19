import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';
import 'package:nexshift_app/core/services/cloud_functions_service.dart';
import 'package:nexshift_app/core/config/environment_config.dart';

/// Repository pour gérer les données utilisateur dans Firestore
///
/// IMPORTANT - Système hybride:
/// - Les données PII (nom, prénom, email, matricule) sont chiffrées côté serveur
///   et doivent être lues via les callable functions (cloud_functions_service.dart)
/// - Ce repository gère principalement les données NON-PII spécifiques aux stations
///   (équipe, statut, compétences, etc.)
///
/// Pour lire des profils utilisateur avec PII déchiffrées, utilisez:
/// - CloudFunctionsService.getUserProfile() pour un utilisateur
/// - CloudFunctionsService.getStationUsers() pour tous les utilisateurs d'une station
class UserRepository {
  static const _collectionName = 'users';
  final FirestoreService _firestoreService;
  final FirebaseFirestore? _directFirestore;

  /// Cache statique des utilisateurs déchiffrés, alimenté par getByStation.
  /// Clé = userId, Valeur = User avec PII en clair.
  static final Map<String, User> _decryptedUserCache = {};

  /// Retourne le chemin de collection selon l'environnement
  String _getCollectionPath(String? stationId) {
    return EnvironmentConfig.getCollectionPath(_collectionName, stationId);
  }

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

  /// Récupère les utilisateurs d'une station spécifique
  Future<List<User>> getByStation(String stationId) async {
    try {
      // IMPORTANT : Utiliser CloudFunctionsService pour obtenir les données déchiffrées
      // Les PII (firstName, lastName, email) sont chiffrées dans Firestore
      // et ne peuvent être déchiffrées que par les Cloud Functions
      final cloudFunctionsService = CloudFunctionsService();
      final users = await cloudFunctionsService.getUsersByStation(stationId: stationId);

      // Alimenter le cache avec les données déchiffrées
      for (final user in users) {
        _decryptedUserCache[user.id] = user;
      }

      debugPrint('📥 UserRepository.getByStation: loaded ${users.length} users (decrypted) from station $stationId');
      return users;
    } catch (e) {
      debugPrint('❌ Error in getByStation (trying Cloud Functions): $e');

      // Fallback : lecture Firestore directe (données chiffrées)
      // Cela ne devrait être utilisé qu'en mode test/dev
      debugPrint('⚠️ Falling back to direct Firestore read (encrypted data)');

      final collectionPath = _getCollectionPath(stationId);

      // Mode test : utiliser directement FirebaseFirestore
      if (_directFirestore != null) {
        // En mode dev avec sous-collections
        if (EnvironmentConfig.useStationSubcollections) {
          final snapshot = await _directFirestore!.collection(collectionPath).get();
          return snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return User.fromJson(data);
          }).toList();
        } else {
          // Mode prod avec collections plates
          final snapshot = await _directFirestore!
              .collection(_collectionName)
              .where('station', isEqualTo: stationId)
              .get();
          return snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return User.fromJson(data);
          }).toList();
        }
      }

      // Mode production : utiliser FirestoreService (fallback)
      // En mode dev (sous-collections), on récupère tous les users de la sous-collection
      // En mode prod (collections plates), on filtre par station
      if (EnvironmentConfig.useStationSubcollections) {
        final data = await _firestoreService.getAll(collectionPath);
        return data.map((e) => User.fromJson(e)).toList();
      } else {
        final data = await _firestoreService.getWhere(
          collectionPath,
          'station',
          stationId,
        );
        return data.map((e) => User.fromJson(e)).toList();
      }
    }
  }

  /// Récupère un utilisateur par son ID
  /// Cherche d'abord dans le cache des utilisateurs déchiffrés (alimenté par getByStation).
  /// En mode DEV sans stationId: cherche dans toutes les stations.
  Future<User?> getById(String id, {String? stationId}) async {
    try {
      // Vérifier le cache déchiffré en priorité
      if (_decryptedUserCache.containsKey(id)) {
        return _decryptedUserCache[id];
      }

      // En mode dev SANS stationId: chercher dans toutes les stations
      if (EnvironmentConfig.useStationSubcollections && stationId == null) {
        return await _getUserByIdAcrossStations(id);
      }

      final collectionPath = _getCollectionPath(stationId);

      // Mode test : utiliser directement FirebaseFirestore
      if (_directFirestore != null) {
        final doc = await _directFirestore!.collection(collectionPath).doc(id).get();
        if (!doc.exists) return null;
        final data = doc.data()!;
        data['id'] = doc.id;
        return User.fromJson(data);
      }

      // Mode production : utiliser FirestoreService
      final data = await _firestoreService.getById(collectionPath, id);
      if (data != null) {
        return User.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Firestore error in getById: $e');
      rethrow;
    }
  }

  /// Cherche un utilisateur dans toutes les stations (DEV uniquement)
  Future<User?> _getUserByIdAcrossStations(String userId) async {
    try {
      final firestore = _directFirestore ?? FirebaseFirestore.instance;

      // Utiliser le chemin des stations depuis EnvironmentConfig (qui prend en compte le SDIS)
      final stationsPath = EnvironmentConfig.stationsCollectionPath;

      // Récupérer toutes les stations
      final stationsSnapshot = await firestore.collection(stationsPath).get();

      // Chercher l'utilisateur dans chaque station
      for (final stationDoc in stationsSnapshot.docs) {
        final userDoc = await firestore
            .collection(stationsPath)
            .doc(stationDoc.id)
            .collection('users')
            .doc(userId)
            .get();

        if (userDoc.exists) {
          final data = userDoc.data()!;
          data['id'] = userDoc.id;
          return User.fromJson(data);
        }
      }

      return null; // Utilisateur non trouvé
    } catch (e) {
      debugPrint('Error searching user across stations: $e');
      return null;
    }
  }

  /// Sauvegarde tous les utilisateurs
  /// IMPORTANT : utilise toFirestoreJson() pour ne JAMAIS écrire de PII en clair.
  Future<void> saveAll(List<User> users) async {
    try {
      // Mode test : utiliser directement FirebaseFirestore
      if (_directFirestore != null) {
        final batch = _directFirestore.batch();
        for (final user in users) {
          batch.set(
            _directFirestore.collection(_collectionName).doc(user.id),
            user.toFirestoreJson(),
            SetOptions(merge: true),
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
        'data': user.toFirestoreJson(),
      }).toList();
      await _firestoreService.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during saveAll: $e');
      rethrow;
    }
  }

  /// Met à jour ou insère un utilisateur
  /// IMPORTANT : utilise toFirestoreJson() pour ne JAMAIS écrire de PII en clair.
  Future<void> upsert(User user) async {
    try {
      debugPrint('🔄 [UserRepository] Upserting user ${user.id}');
      debugPrint('   Data: team=${user.team}, status=${user.status}, station=${user.station} (PII excluded)');

      final collectionPath = _getCollectionPath(user.station);
      final data = user.toFirestoreJson();

      // Mode test : utiliser directement FirebaseFirestore
      if (_directFirestore != null) {
        await _directFirestore.collection(collectionPath).doc(user.id).set(data, SetOptions(merge: true));
        debugPrint('✅ [UserRepository] User ${user.id} upserted successfully');
        return;
      }

      // Mode production : utiliser FirestoreService
      await _firestoreService.upsert(collectionPath, user.id, data);
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

  /// Supprime un utilisateur d'une station spécifique
  Future<void> deleteFromStation(String id, String stationId) async {
    try {
      final collectionPath = _getCollectionPath(stationId);

      // Mode test : utiliser directement FirebaseFirestore
      if (_directFirestore != null) {
        await _directFirestore.collection(collectionPath).doc(id).delete();
        return;
      }

      // Mode production : utiliser FirestoreService
      // Le chemin complet est passé comme nom de collection
      await _firestoreService.delete(collectionPath, id);
    } catch (e) {
      debugPrint('Firestore error during deleteFromStation: $e');
      rethrow;
    }
  }

  /// Vérifie si on peut retirer les privilèges (admin/leader) d'un utilisateur
  /// Retourne true s'il reste au moins un autre admin ou leader dans la station
  Future<bool> canRemovePrivileges(String stationId, String userId) async {
    try {
      final users = await getByStation(stationId);
      // Compter les admins et leaders AUTRES que l'utilisateur concerné
      final otherPrivileged = users.where((u) =>
          u.id != userId &&
          (u.admin || u.status == 'leader'));
      return otherPrivileged.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking privileges: $e');
      // En cas d'erreur, on bloque par sécurité
      return false;
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
