/// Script de migration des données PROD vers architecture sous-collections DEV
///
/// Utilisation : dart run tools/migrate_to_subcollections.dart
///
/// IMPORTANT: Ce script NE MODIFIE PAS les données PROD
/// Il copie uniquement les données vers l'architecture DEV
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  print('=== Migration vers sous-collections DEV ===\n');

  // Initialiser Firebase
  // TODO: Configurer avec vos credentials Firebase
  await Firebase.initializeApp();

  final firestore = FirebaseFirestore.instance;

  print('📊 Analyse de la structure actuelle...\n');

  // 1. Récupérer toutes les stations
  final stationsSnapshot = await firestore.collection('administration').get();
  final stations = stationsSnapshot.docs.map((doc) => doc.id).toList();

  print('✅ ${stations.length} stations trouvées\n');

  for (final stationId in stations) {
    print('🏢 Migration de la station: $stationId');

    // Migrer les équipes
    await _migrateCollection(
      firestore,
      'teams',
      stationId,
      'stationId',
    );

    // Migrer les utilisateurs
    await _migrateCollection(
      firestore,
      'users',
      stationId,
      'station',
    );

    // Migrer les plannings
    await _migrateCollection(
      firestore,
      'plannings',
      stationId,
      'station',
    );

    // Migrer les véhicules
    await _migrateCollection(
      firestore,
      'trucks',
      stationId,
      'station',
    );

    // Migrer les shift_rules
    await _migrateCollection(
      firestore,
      'shift_rules',
      stationId,
      'station',
    );

    // Migrer les shift_exceptions
    await _migrateCollection(
      firestore,
      'shift_exceptions',
      stationId,
      'station',
    );

    // Migrer les availabilities
    await _migrateCollection(
      firestore,
      'availabilities',
      stationId,
      'userId',
      filterByUserStation: true,
    );

    print('  ✅ Migration de $stationId terminée\n');
  }

  print('🎉 Migration complète terminée!\n');
  print('⚠️  N\'oubliez pas de déployer les nouvelles Security Rules');
  exit(0);
}

/// Migre une collection vers les sous-collections
Future<void> _migrateCollection(
  FirebaseFirestore firestore,
  String collectionName,
  String stationId,
  String stationFieldName, {
  bool filterByUserStation = false,
}) async {
  try {
    // Récupérer tous les documents de la station
    Query query = firestore.collection(collectionName);

    if (!filterByUserStation) {
      query = query.where(stationFieldName, isEqualTo: stationId);
    }

    final snapshot = await query.get();
    final docs = snapshot.docs;

    if (docs.isEmpty) {
      print('  ℹ️  $collectionName: aucun document');
      return;
    }

    // Filtrage spécial pour availabilities
    List<QueryDocumentSnapshot> filteredDocs = docs;
    if (filterByUserStation) {
      // Récupérer les IDs des utilisateurs de cette station
      final usersSnapshot = await firestore
          .collection('users')
          .where('station', isEqualTo: stationId)
          .get();
      final userIds = usersSnapshot.docs.map((doc) => doc.id).toSet();

      filteredDocs = docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return userIds.contains(data['userId']);
      }).toList();
    }

    // Créer un batch pour l'écriture
    final batch = firestore.batch();
    int batchCount = 0;

    for (final doc in filteredDocs) {
      final data = doc.data() as Map<String, dynamic>;

      // Créer le document dans la sous-collection
      final newDocRef = firestore
          .collection('stations')
          .doc(stationId)
          .collection(collectionName)
          .doc(doc.id);

      batch.set(newDocRef, data);
      batchCount++;

      // Firestore limite les batch à 500 opérations
      if (batchCount >= 450) {
        await batch.commit();
        batchCount = 0;
      }
    }

    // Commiter le dernier batch
    if (batchCount > 0) {
      await batch.commit();
    }

    print('  ✅ $collectionName: ${filteredDocs.length} documents migrés');
  } catch (e) {
    print('  ❌ Erreur lors de la migration de $collectionName: $e');
  }
}
