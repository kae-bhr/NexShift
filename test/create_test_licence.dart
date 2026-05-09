/// Script pour créer une licence de test dans Firestore
///
/// Usage:
/// 1. Assurez-vous que l'émulateur ou Firebase dev est configuré
/// 2. Lancez avec: flutter run test/create_test_licence.dart
///
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:releve/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialiser Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final firestore = FirebaseFirestore.instance;

  // Créer une licence de test
  final testLicence = {
    'licence': 'TEST-LICENCE-001',
    'id': '12345',
    'station': 'Caserne Test',
    'consumed': false,
    'consumedAt': null,
  };

  try {
    await firestore
        .collection('auth')
        .doc('TEST-LICENCE-001')
        .set(testLicence);

    print('✅ Licence de test créée avec succès !');
    print('📋 Numéro de licence : TEST-LICENCE-001');
    print('👤 Matricule : 12345');
    print('🏢 Caserne : Caserne Test');
    print('\nVous pouvez maintenant utiliser cette licence dans l\'app.');
  } catch (e) {
    print('❌ Erreur lors de la création de la licence : $e');
  }
}
