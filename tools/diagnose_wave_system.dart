/// Script de diagnostic du système de vagues
/// Vérifie l'état des demandes de remplacement et affiche les détails
///
/// Usage: dart run tools/diagnose_wave_system.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../lib/firebase_options.dart';
import '../lib/core/config/environment_config.dart';

Future<void> main() async {
  print('🔍 Diagnostic du système de vagues...\n');

  // Initialiser Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final firestore = FirebaseFirestore.instance;

  // Paramètres
  const String stationId = 'Nîmes';

  // 1. Vérifier les demandes de remplacement
  print('📋 Vérification des demandes de remplacement...');
  final requestsPath = EnvironmentConfig.getCollectionPath('replacementRequests', stationId);
  print('   Chemin: $requestsPath\n');

  final requestsSnapshot = await firestore
      .collection(requestsPath)
      .orderBy('createdAt', descending: true)
      .limit(5)
      .get();

  if (requestsSnapshot.docs.isEmpty) {
    print('⚠️  Aucune demande trouvée dans $requestsPath');
    print('   Vérification de l\'ancien chemin...');

    final legacySnapshot = await firestore
        .collection('replacementRequests')
        .orderBy('createdAt', descending: true)
        .limit(5)
        .get();

    if (legacySnapshot.docs.isNotEmpty) {
      print('✅ ${legacySnapshot.docs.length} demandes trouvées dans l\'ancien chemin (racine)');
      print('   ⚠️  PROBLÈME: Les données sont à l\'ancien emplacement !');
      print('   ⚠️  Vous devez exécuter le script de migration.\n');
    } else {
      print('❌ Aucune demande trouvée nulle part\n');
    }
    return;
  }

  print('✅ ${requestsSnapshot.docs.length} demandes trouvées\n');

  for (final doc in requestsSnapshot.docs) {
    final data = doc.data();
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📄 Demande: ${doc.id}');
    print('   Status: ${data['status']}');
    print('   Station: ${data['station']}');
    print('   Vague actuelle: ${data['currentWave'] ?? 'non définie'}');
    print('   Agents notifiés: ${(data['notifiedUserIds'] as List?)?.length ?? 0}');

    final notifiedIds = (data['notifiedUserIds'] as List?)?.cast<String>() ?? [];
    if (notifiedIds.isEmpty) {
      print('   ⚠️  Aucun agent notifié !');
    } else {
      print('   Agents: ${notifiedIds.join(', ')}');
    }

    final lastWaveSent = data['lastWaveSentAt'];
    if (lastWaveSent != null) {
      final timestamp = (lastWaveSent as Timestamp).toDate();
      print('   Dernière vague envoyée: $timestamp');
    } else {
      print('   ⚠️  Aucune vague envoyée');
    }
    print('');
  }

  // 2. Vérifier les utilisateurs de la station
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('👥 Vérification des utilisateurs...');

  final usersSnapshot = await firestore
      .collection('users')
      .where('station', isEqualTo: stationId)
      .get();

  print('✅ ${usersSnapshot.docs.length} utilisateurs trouvés pour la station "$stationId"\n');

  if (usersSnapshot.docs.length < 2) {
    print('⚠️  PROBLÈME: Pas assez d\'utilisateurs pour tester le système de vagues !');
    print('   Il faut au moins 2 utilisateurs (demandeur + candidat).\n');
  }

  // Grouper par équipe
  final usersByTeam = <String, List<String>>{};
  for (final doc in usersSnapshot.docs) {
    final data = doc.data();
    final team = data['team'] as String? ?? 'sans équipe';
    final name = '${data['firstName']} ${data['lastName']} (${doc.id})';
    usersByTeam.putIfAbsent(team, () => []).add(name);
  }

  print('📊 Répartition par équipe:');
  usersByTeam.forEach((team, users) {
    print('   • $team: ${users.length} membres');
    for (final user in users) {
      print('     - $user');
    }
  });
  print('');

  // 3. Vérifier les plannings
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📅 Vérification des plannings...');

  final planningsPath = EnvironmentConfig.getCollectionPath('plannings', stationId);
  print('   Chemin: $planningsPath\n');

  final planningsSnapshot = await firestore
      .collection(planningsPath)
      .orderBy('startTime', descending: true)
      .limit(3)
      .get();

  if (planningsSnapshot.docs.isEmpty) {
    print('⚠️  Aucun planning trouvé dans $planningsPath');
  } else {
    print('✅ ${planningsSnapshot.docs.length} plannings trouvés\n');

    for (final doc in planningsSnapshot.docs) {
      final data = doc.data();
      final agentsIds = (data['agentsId'] as List?)?.cast<String>() ?? [];
      print('📅 Planning: ${doc.id}');
      print('   Équipe: ${data['team'] ?? 'non définie'}');
      print('   Agents en astreinte: ${agentsIds.length}');
      print('');
    }
  }

  // 4. Vérifier la station
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🏢 Vérification de la configuration station...');

  final stationsPath = EnvironmentConfig.stationsCollectionPath;
  print('   Chemin: $stationsPath\n');

  final stationDoc = await firestore
      .collection(stationsPath)
      .doc(stationId)
      .get();

  if (!stationDoc.exists) {
    print('⚠️  Station "$stationId" non trouvée !');
  } else {
    final data = stationDoc.data()!;
    print('✅ Station trouvée');
    print('   Mode de remplacement: ${data['replacementMode'] ?? 'similarity (par défaut)'}');
    print('   Nom: ${data['name'] ?? stationId}');
  }

  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('✅ Diagnostic terminé\n');

  print('💡 Recommandations:');
  print('   1. Si les demandes sont à l\'ancien emplacement → exécuter la migration');
  print('   2. Si notifiedUserIds est vide → vérifier les logs de l\'app lors de la création');
  print('   3. Si pas assez d\'utilisateurs → en ajouter via l\'interface admin');
  print('   4. Vérifier que la station et l\'équipe correspondent entre demande et utilisateurs\n');
}
