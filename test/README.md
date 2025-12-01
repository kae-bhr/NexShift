# 🧪 Guide des Tests - NexShift

Ce guide explique comment exécuter les tests du projet NexShift.

## 📋 **Structure des Tests**

```
test/
├── unit/                    # Tests unitaires (fonctions isolées)
├── integration/             # Tests d'intégration (flux complets)
│   └── replacement/
│       ├── partial_replacement_test.dart     # ✅ Tests de remplacements partiels
│       ├── conflict_test.dart                # ✅ Tests de détection de conflits
│       ├── validation_test.dart              # ✅ Tests de validations métier
│       ├── race_condition_test.dart          # ⚠️ Tests race conditions (fake)
│       └── race_condition_emulator_test.dart # 🔧 Tests avec émulateur Firebase
├── widget/                  # Tests de widgets (UI)
└── helpers/                 # Utilitaires de test
    └── test_data.dart       # Données de test réutilisables
```

## 🚀 **Exécuter les Tests**

### **Tests Unitaires et d'Intégration (Fake Firestore)**

Ces tests utilisent `fake_cloud_firestore` pour simuler Firestore en mémoire. Ils sont **rapides** et ne nécessitent pas de connexion réseau.

```bash
# Tous les tests
flutter test

# Un fichier spécifique
flutter test test/integration/replacement/race_condition_test.dart

# Avec couverture de code
flutter test --coverage
```

### **Tests avec Firebase Emulator (Recommandé pour CI/CD)**

⚠️ **Note** : Les tests avec émulateur nécessitent Firebase CLI installé.

```bash
# Démarrer l'émulateur manuellement
firebase emulators:start --only firestore

# Dans un autre terminal, lancer les tests
flutter test test/integration/replacement/race_condition_emulator_test.dart
```

**Ou** utiliser le script qui démarre et arrête l'émulateur automatiquement :

```powershell
# Windows PowerShell
.\test\run_with_emulator.ps1

# Bash/Linux/Mac
./test/run_with_emulator.sh
```

## ⚠️ **Limitations Connues**

### **Transactions Atomiques avec `fake_cloud_firestore`**

`fake_cloud_firestore` **ne simule PAS** les transactions atomiques de Firestore. Les tests de race conditions avec ce package passeront même si la logique de transaction a un bug.

**Solution** :
- Les tests avec `fake_cloud_firestore` testent la **logique métier** (validations, vérifications)
- Les tests de **transactions réelles** nécessitent Firebase Emulator ou des tests manuels en environnement de staging

### **Tests Actuellement Implémentés**

#### ✅ **Tests de remplacements partiels** (`partial_replacement_test.dart`) :
- ✅ Situation 1: Acceptation du début (14h-16h sur 14h-17h) → nouvelle demande 16h-17h
- ✅ Situation 2: Acceptation de la fin (15h-17h sur 14h-17h) → nouvelle demande 14h-15h
- ✅ Situation 3: Acceptation du milieu (15h-16h sur 14h-17h) → 2 nouvelles demandes
- ✅ Acceptation totale ne crée pas de nouvelle demande
- ✅ Exclusion des utilisateurs déjà notifiés dans les vagues précédentes
- **Total: 5 tests ✅**

#### ✅ **Tests de détection de conflits** (`conflict_test.dart`) :
- ✅ Conflit avec planning existant (agent déjà de service)
- ✅ Conflit avec subshift existant (agent déjà en remplacement)
- ✅ Overlap partiel au début
- ✅ Overlap partiel à la fin
- ✅ Subshift complètement inclus
- ✅ Pas de conflit avec créneaux séparés
- ✅ Détection des disponibilités existantes
- **Total: 7 tests ✅**

#### ✅ **Tests de validation** (`validation_test.dart`) :
- ✅ Heure de fin avant heure de début → Erreur
- ✅ Acceptation hors plage demandée → Erreur
- ✅ Acceptation avant le début de la demande → Erreur
- ✅ Acceptation après la fin de la demande → Erreur
- ✅ Auto-acceptation (comportement documenté)
- ✅ Demande inexistante → Erreur
- ✅ Demande déjà acceptée → Erreur
- ✅ Demande refusée peut être acceptée par quelqu'un d'autre
- ✅ Dates dans le passé sont permises
- ✅ Plage horaire partielle valide → Succès
- **Total: 10 tests ✅**

#### ⚠️ **Tests avec limitations** (`race_condition_test.dart`) :
- ⚠️ Race conditions simulées (fake_cloud_firestore ne supporte pas les vraies transactions)
- **Total: 3 tests ⚠️ (limitations connues)**

#### 🔧 **Tests nécessitant Firebase Emulator** (`race_condition_emulator_test.dart`) :
- 🔧 Race conditions réelles avec vraies transactions atomiques
- 🔧 Nécessite `firebase emulators:exec` pour fonctionner
- **Total: 2 tests 🔧 (configuration manuelle requise)**

#### ✅ **Tests unitaires de services** :

##### **WaveCalculationService** (`test/unit/services/wave_calculation_service_test.dart`) :
- ✅ Vague 0 : Agents en astreinte jamais notifiés
- ✅ Vague 1 : Agents de la même équipe
- ✅ Vague 2 : Compétences exactement identiques
- ✅ Vague 3 : Compétences très proches (≥80%)
- ✅ Vague 4 : Compétences relativement proches (≥60%)
- ✅ Vague 5 : Compétences peu similaires (<60%)
- ✅ Cas limites (sans compétences, priorités)
- ⏭️ 1 test skippé (pondération rareté - fonctionnalité future)
- **Total: 11 tests ✅, 1 skippé ⏭️**

##### **SubshiftNormalizer** (`test/core/utils/subshift_normalizer_test.dart`) :
- ✅ Résolution de cascade simple (C→B→A)
- ✅ Triple cascade avec découpage temporel
- ✅ Remplacements indépendants (pas de cascade)
- ✅ Overlaps complexes
- ✅ Liste vide
- **Total: 5 tests ✅**

**📊 Total général: 44 tests implémentés**
- 38 tests passants ✅
- 3 tests avec limitations connues ⚠️
- 2 tests nécessitant émulateur 🔧
- 1 test skippé (fonctionnalité future) ⏭️

## 📊 **Objectif de Couverture**

- **Cible** : 80-90% de couverture de code
- **Priorités** :
  1. Services critiques (ReplacementNotificationService, etc.)
  2. Repositories
  3. Modèles
  4. Widgets principaux

## 🔧 **Configuration CI/CD (CodeMagic)**

✅ **Configuration complète disponible dans `codemagic.yaml`**

Le fichier `codemagic.yaml` à la racine du projet contient 4 workflows :

### **1. test-workflow** (Exécuté sur chaque push/PR)
- ✅ Installation des dépendances
- ✅ Analyse du code (`flutter analyze`)
- ✅ Exécution de tous les tests (sauf tests émulateur)
- ✅ Vérification de couverture (seuil: 80%)
- ✅ Génération de rapport HTML de couverture
- 🎯 **Artifact** : Rapports de couverture

### **2. android-workflow** (Exécuté sur push vers master/main)
- ✅ Tests avant build
- ✅ Build APK Android
- ✅ Build App Bundle Android
- 🎯 **Artifacts** : APK et AAB

### **3. ios-workflow** (Exécuté sur push vers master/main)
- ✅ Tests avant build
- ✅ Installation des pods iOS
- ✅ Build iOS
- 🎯 **Artifacts** : App iOS

### **4. dev-tests** (Exécuté sur chaque PR)
- ✅ Tests rapides d'intégration uniquement
- ⚡ Workflow léger pour développement

### **Commandes de test dans CI/CD**

Les tests émulateur sont exclus automatiquement avec :

```bash
flutter test --exclude-tags=emulator --coverage
```

### **Exemple de configuration manuelle si nécessaire** :

```yaml
scripts:
  - name: Run tests with coverage
    script: flutter test --exclude-tags=emulator --coverage

  - name: Check coverage threshold
    script: |
      # Vérifier que la couverture est >= 80%
      lcov --list coverage/lcov.info
```

## 🛠️ **Ajouter de Nouveaux Tests**

### **1. Tests Unitaires**

Créer un fichier dans `test/unit/` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

void main() {
  group('MonService Tests', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MonService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = MonService(firestore: fakeFirestore);
    });

    test('Description du test', () async {
      // ARRANGE - Préparer les données

      // ACT - Exécuter l'action

      // ASSERT - Vérifier le résultat
    });
  });
}
```

### **2. Tests d'Intégration**

Créer un fichier dans `test/integration/` et tester des flux complets.

### **3. Tests de Widgets**

Créer un fichier dans `test/widget/` :

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MonWidget affiche le texte', (WidgetTester tester) async {
    await tester.pumpWidget(MonWidget());
    expect(find.text('Hello'), findsOneWidget);
  });
}
```

## 📚 **Ressources**

- [Documentation Flutter Testing](https://docs.flutter.dev/testing)
- [fake_cloud_firestore](https://pub.dev/packages/fake_cloud_firestore)
- [Firebase Emulator Suite](https://firebase.google.com/docs/emulator-suite)
- [mockito](https://pub.dev/packages/mockito)

## 🐛 **Dépannage**

### **Erreur : "No Firebase App"**

Les tests avec Firestore réel nécessitent l'émulateur. Utilisez `fake_cloud_firestore` pour les tests unitaires.

### **Tests lents**

- Utilisez `fake_cloud_firestore` au lieu de l'émulateur pour les tests unitaires
- L'émulateur est pour les tests d'intégration et CI/CD

### **Couverture faible**

```bash
# Voir les fichiers non couverts
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html  # Mac/Linux
start coverage/html/index.html # Windows
```
