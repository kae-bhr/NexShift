# NexShift

Application de gestion des astreintes pour centres de secours et casernes de pompiers.

![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?logo=flutter)
![Firebase](https://img.shields.io/badge/Firebase-Enabled-FFCA28?logo=firebase)
![License](https://img.shields.io/badge/License-Proprietary-red)

## 📋 Description

NexShift est une application mobile professionnelle destinée à la gestion des plannings d'astreinte pour les centres de secours. Elle permet d'optimiser l'organisation opérationnelle, de garantir la conformité réglementaire des équipages et de faciliter la communication entre les agents.

### Fonctionnalités principales

- **Gestion des plannings** : Création et visualisation des astreintes
- **Gestion des disponibilités** : Déclaration et suivi des disponibilités des agents
- **Système de remplacements** : Organisation facilitée des remplacements entre agents
- **Gestion des compétences** : Suivi des qualifications et compétences de chaque agent
- **Composition des équipages** : Vérification automatique de la conformité réglementaire
- **Notifications en temps réel** : Alertes pour les demandes de remplacement et changements de planning
- **Mode hors ligne** : Accès aux données essentielles sans connexion Internet
- **Système de logs** : Traçabilité complète des actions importantes

## 🚀 Technologies

- **Framework** : Flutter 3.0+
- **Langage** : Dart
- **Backend** : Firebase (Firestore, Authentication, Cloud Messaging, Storage)
- **État** : Riverpod
- **Notifications** : Firebase Cloud Messaging (FCM)
- **Persistance locale** : Shared Preferences

## 📱 Plateformes supportées

- Android (API 21+)
- iOS (11.0+)

## 🏗️ Architecture

L'application suit une architecture en couches inspirée de Clean Architecture :

```
lib/
├── core/                  # Fonctionnalités partagées
│   ├── data/               # Modèles de données et repositories
│   ├── services/           # Services (authentification, Firebase, logs)
│   ├── utils/              # Utilitaires et constantes
│   └── presentation/       # Widgets et pages partagés
├── features/              # Fonctionnalités métier
│   ├── auth/               # Authentification
│   ├── home/               # Page d'accueil et dashboard
│   ├── planning/           # Gestion des plannings
│   ├── availability/       # Gestion des disponibilités
│   └── settings/           # Paramètres utilisateur
└── main.dart              # Point d'entrée
```

## 🔧 Installation et configuration

### Prérequis

- Flutter SDK 3.0+
- Dart SDK 3.0+
- Android Studio / Xcode
- Compte Firebase configuré

### Installation

1. Cloner le repository :
```bash
git clone https://github.com/votre-repo/nexshift_app.git
cd nexshift_app
```

2. Installer les dépendances :
```bash
flutter pub get
```

3. Configurer Firebase :
   - Créer un projet Firebase
   - Télécharger `google-services.json` (Android) et `GoogleService-Info.plist` (iOS)
   - Placer les fichiers dans les répertoires appropriés
   - Générer `firebase_options.dart` :
   ```bash
   flutterfire configure
   ```

4. Créer le fichier `android/key.properties` pour la signature de l'APK :
```properties
storeFile=path/to/keystore.jks
storePassword=your_store_password
keyAlias=your_key_alias
keyPassword=your_key_password
```

### Lancer l'application

**Mode développement :**
```bash
flutter run
```

**Build APK de production :**
```bash
flutter build apk --release --obfuscate --split-debug-info=build/app/outputs/symbols
```

**Build App Bundle (Google Play) :**
```bash
flutter build appbundle --release --obfuscate --split-debug-info=build/app/outputs/symbols
```

## 🔐 Sécurité

- Authentification Firebase avec gestion des rôles (Admin, Leader, Chief, Agent)
- Règles de sécurité Firestore basées sur les rôles (RBAC)
- Obfuscation du code en production
- Fichiers sensibles exclus du contrôle de version (.gitignore)
- Conformité RGPD pour la gestion des données personnelles

## 📄 Documentation légale

- [LICENSE](LICENSE.md) - Licence propriétaire
- [Mentions légales](assets/legal/mentions_legales.html)
- CGU accessibles depuis l'application

## 👤 Auteur

**Benjamin HOLZER**
- Email : bhr.holzer@gmail.com
- SIRET : 982291874

## 📝 Licence

Ce projet est sous licence propriétaire. Toute utilisation, reproduction ou distribution nécessite une autorisation écrite explicite de l'auteur.

L'accès à l'application est réservé aux centres de secours disposant d'une licence annuelle valide.

## 🤝 Support

Pour toute question ou demande de support :
- Email : bhr.holzer@gmail.com

## 📊 État du projet

**Version actuelle** : 1.0.0
**Statut** : Production

---

© 2025-2026 NexShift - Tous droits réservés
