import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:releve/core/data/models/user_model.dart';
import 'package:releve/core/data/models/user_stations_model.dart';
import 'package:releve/core/data/models/user_claims_model.dart';
import 'package:releve/core/repositories/user_repository.dart';
import 'package:releve/core/repositories/user_stations_repository.dart';
import 'package:releve/core/data/datasources/sdis_context.dart';
import 'package:releve/core/services/cloud_functions_service.dart';

/// Exception lancée quand l'utilisateur existe dans Firebase Auth
/// mais n'a pas de profil dans Firestore
class UserProfileNotFoundException implements Exception {
  final String matricule;

  UserProfileNotFoundException(this.matricule);

  @override
  String toString() => 'User profile not found in Firestore for matricule: $matricule';
}

/// Exception lancée quand l'utilisateur n'est affilié à aucune caserne
class NoStationAffiliationException implements Exception {
  final String authUid;

  NoStationAffiliationException(this.authUid);

  @override
  String toString() => 'User has no station affiliation: $authUid';
}

/// Résultat de l'authentification avec informations de stations
/// Utilisé quand un utilisateur appartient à plusieurs stations
class AuthenticationResult {
  final User? user;
  final UserStations? userStations;
  final UserClaims? claims; // Nouveau: custom claims

  AuthenticationResult({
    this.user,
    this.userStations,
    this.claims,
  });

  /// L'utilisateur doit-il sélectionner une station ?
  bool get needsStationSelection =>
      (userStations != null && userStations!.stations.length >= 2) ||
      (claims != null && claims!.stations.length >= 2);

  /// L'utilisateur n'a qu'une seule station
  bool get hasSingleStation =>
      (userStations != null && userStations!.stations.length == 1) ||
      (claims != null && claims!.stations.length == 1);

  /// L'utilisateur n'a aucune station (doit chercher une caserne)
  bool get hasNoStation =>
      (claims != null && claims!.stations.isEmpty) ||
      (userStations != null && userStations!.stations.isEmpty);
}

/// Service d'authentification Firebase
/// Gère l'authentification des utilisateurs avec Firebase Auth
/// et synchronise avec les données utilisateur dans Firestore
class FirebaseAuthService {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final UserRepository _userRepository = UserRepository();
  final UserStationsRepository _userStationsRepository = UserStationsRepository();

  // Cache des claims pour éviter les appels répétés
  UserClaims? _cachedClaims;

  /// Récupère l'utilisateur Firebase actuellement connecté
  firebase_auth.User? get currentFirebaseUser => _auth.currentUser;

  /// Stream des changements d'état d'authentification
  Stream<firebase_auth.User?> get authStateChanges => _auth.authStateChanges();

  /// Vérifie si un utilisateur est connecté
  bool get isAuthenticated => _auth.currentUser != null;

  /// Récupère les custom claims de l'utilisateur courant (avec cache)
  UserClaims? get cachedClaims => _cachedClaims;

  /// Récupère l'ID de l'utilisateur actuellement connecté
  String? get currentUserId => _auth.currentUser?.uid;

  // ============================================================
  // NOUVELLES MÉTHODES - Authentification avec email réel
  // ============================================================

  /// Connexion avec email réel et mot de passe (nouveau système)
  /// Charge automatiquement les custom claims après connexion
  Future<AuthenticationResult> signInWithRealEmail({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('Attempting Firebase sign in with real email: $email');

      // Authentification Firebase
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user == null) {
        throw Exception('Authentication failed: no user returned');
      }

      debugPrint('Firebase sign in successful: ${credential.user!.uid}');

      // Charger les custom claims
      final claims = await getUserClaims(forceRefresh: true);

      if (claims == null) {
        debugPrint('Warning: No custom claims found for user');
        // L'utilisateur n'a pas encore de claims (nouveau compte sans affiliation)
        return AuthenticationResult(
          user: null,
          userStations: null,
          claims: null,
        );
      }

      debugPrint('Claims loaded: sdisId=${claims.sdisId}, role=${claims.role}, stations=${claims.stations.keys.toList()}');

      // Définir le contexte SDIS global
      if (claims.sdisId.isNotEmpty) {
        SDISContext().setCurrentSDISId(claims.sdisId);
      }

      // Retourner le résultat avec les claims
      return AuthenticationResult(
        user: null, // Le profil sera chargé via callable function
        userStations: null,
        claims: claims,
      );
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth error: ${e.code} - ${e.message}');

      switch (e.code) {
        case 'user-not-found':
          throw Exception('Aucun compte ne correspond à cette adresse email');
        case 'wrong-password':
        case 'invalid-credential':
          throw Exception('Mot de passe incorrect');
        case 'invalid-email':
          throw Exception('Adresse email invalide');
        case 'user-disabled':
          throw Exception('Ce compte a été désactivé');
        case 'too-many-requests':
          throw Exception(
            'Trop de tentatives de connexion. Veuillez réessayer plus tard',
          );
        case 'network-request-failed':
          throw Exception(
            'Erreur réseau. Vérifiez votre connexion internet',
          );
        default:
          throw Exception('Erreur d\'authentification: ${e.message}');
      }
    } catch (e) {
      debugPrint('Sign in error: $e');
      rethrow;
    }
  }

  /// Récupère les custom claims de l'utilisateur courant
  /// [forceRefresh] force le rafraîchissement du token (après modification des claims)
  Future<UserClaims?> getUserClaims({bool forceRefresh = false}) async {
    try {
      final firebaseUser = _auth.currentUser;
      if (firebaseUser == null) {
        _cachedClaims = null;
        return null;
      }

      // Forcer le rafraîchissement du token si demandé
      final idTokenResult = await firebaseUser.getIdTokenResult(forceRefresh);
      final claimsMap = idTokenResult.claims;

      if (claimsMap == null) {
        _cachedClaims = null;
        return null;
      }

      // Parser les claims
      _cachedClaims = UserClaims.fromIdTokenClaims(claimsMap);
      return _cachedClaims;
    } catch (e) {
      debugPrint('Error getting user claims: $e');
      return null;
    }
  }

  /// Rafraîchit les custom claims (après modification côté serveur)
  Future<UserClaims?> refreshClaims() async {
    return getUserClaims(forceRefresh: true);
  }

  /// Envoie un email de réinitialisation de mot de passe (nouvelle version avec email réel)
  Future<void> sendPasswordResetEmailReal(String email) async {
    try {
      debugPrint('Sending password reset email to: $email');

      await _auth.sendPasswordResetEmail(email: email);

      debugPrint('Password reset email sent');
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Password reset error: ${e.code} - ${e.message}');

      switch (e.code) {
        case 'user-not-found':
          throw Exception('Aucun compte ne correspond à cette adresse email');
        case 'invalid-email':
          throw Exception('Adresse email invalide');
        default:
          throw Exception(
            'Erreur lors de l\'envoi de l\'email: ${e.message}',
          );
      }
    } catch (e) {
      debugPrint('Password reset error: $e');
      throw Exception('Erreur lors de l\'envoi de l\'email de réinitialisation: $e');
    }
  }

  /// Réauthentifie l'utilisateur actuel avec son email réel
  Future<void> reauthenticateWithRealEmail({
    required String email,
    required String password,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('Aucun utilisateur connecté');
      }

      final credential = firebase_auth.EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      debugPrint('Reauthenticating user: $email');

      await user.reauthenticateWithCredential(credential);

      debugPrint('Reauthentication successful');
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Reauthentication error: ${e.code} - ${e.message}');

      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          throw Exception('Mot de passe incorrect');
        case 'user-mismatch':
          throw Exception('L\'email ne correspond pas à l\'utilisateur connecté');
        case 'user-not-found':
          throw Exception('Utilisateur introuvable');
        default:
          throw Exception('Erreur de réauthentification: ${e.message}');
      }
    } catch (e) {
      debugPrint('Reauthentication error: $e');
      throw Exception('Erreur lors de la réauthentification: $e');
    }
  }

  /// Connexion avec email et mot de passe (nouvelle version avec gestion multi-stations et multi-SDIS)
  /// Retourne AuthenticationResult avec les informations de stations
  /// Si sdisId est fourni, utilise l'architecture multi-SDIS: {sdisId}_{matricule}@nexshift.app
  /// Sinon, utilise l'architecture legacy: {matricule}@nexshift.app
  Future<AuthenticationResult> signInWithStations({
    required String matricule,
    required String password,
    String? sdisId,
  }) async {
    try {
      // Convertir le matricule en email Firebase (avec ou sans SDIS)
      final email = _matriculeToEmail(matricule, sdisId: sdisId);

      debugPrint('Attempting Firebase sign in for matricule: $matricule (SDIS: ${sdisId ?? 'none'})');

      // Authentification Firebase
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user == null) {
        throw Exception('Authentication failed: no user returned');
      }

      debugPrint('Firebase sign in successful: ${credential.user!.uid}');

      // Définir le contexte SDIS global AVANT de charger les données
      // pour que tous les repositories utilisent les bons chemins
      if (sdisId != null) {
        SDISContext().setCurrentSDISId(sdisId);
      }

      // Récupérer les stations de l'utilisateur
      final userStations = await _userStationsRepository.getUserStations(
        matricule,
        sdisId: sdisId,
      );

      if (userStations == null || userStations.stations.isEmpty) {
        // L'utilisateur n'a pas de stations configurées
        throw UserProfileNotFoundException(matricule);
      }

      debugPrint('User stations loaded: ${userStations.stations}');

      // Si l'utilisateur a plusieurs stations, on retourne null pour le user
      // Le caller devra demander à l'utilisateur de choisir sa station
      if (userStations.stations.length >= 2) {
        debugPrint('User has multiple stations, station selection required');
        return AuthenticationResult(
          user: null,
          userStations: userStations,
        );
      }

      // L'utilisateur n'a qu'une seule station, charger son profil
      final stationId = userStations.stations.first;
      final user = await _userRepository.getById(matricule, stationId: stationId);

      if (user == null) {
        throw UserProfileNotFoundException(matricule);
      }

      // Fusionner les données personnelles depuis user_stations
      final mergedUser = _mergeUserWithPersonalData(user, userStations);

      debugPrint('User profile loaded: ${mergedUser.firstName} ${mergedUser.lastName} (${mergedUser.station})');

      return AuthenticationResult(
        user: mergedUser,
        userStations: userStations,
      );
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth error: ${e.code} - ${e.message}');

      switch (e.code) {
        case 'user-not-found':
          throw Exception('Aucun compte ne correspond à ce matricule');
        case 'wrong-password':
          throw Exception('Mot de passe incorrect');
        case 'invalid-email':
          throw Exception('Format de matricule invalide');
        case 'user-disabled':
          throw Exception('Ce compte a été désactivé');
        case 'too-many-requests':
          throw Exception(
            'Trop de tentatives de connexion. Veuillez réessayer plus tard',
          );
        case 'network-request-failed':
          throw Exception(
            'Erreur réseau. Vérifiez votre connexion internet',
          );
        default:
          throw Exception('Erreur d\'authentification: ${e.message}');
      }
    } catch (e) {
      debugPrint('Sign in error: $e');
      rethrow;
    }
  }

  /// Connexion avec email et mot de passe
  /// email = matricule@nexshift.app (généré automatiquement)
  /// @deprecated Utilisez signInWithStations() pour gérer les utilisateurs multi-stations
  Future<User> signInWithEmailAndPassword({
    required String matricule,
    required String password,
    String? sdisId,
  }) async {
    try {
      // Convertir le matricule en email Firebase
      final email = _matriculeToEmail(matricule, sdisId: sdisId);

      debugPrint('Attempting Firebase sign in for matricule: $matricule');

      // Authentification Firebase
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user == null) {
        throw Exception('Authentication failed: no user returned');
      }

      debugPrint('Firebase sign in successful: ${credential.user!.uid}');

      // Récupérer le profil utilisateur depuis Firestore
      final user = await _userRepository.getById(matricule);

      if (user == null) {
        // Si l'utilisateur n'existe pas dans Firestore, lancer une exception spécifique
        // qui sera gérée par la page de login pour afficher la popup de création
        throw UserProfileNotFoundException(matricule);
      }

      debugPrint('User profile loaded: ${user.firstName} ${user.lastName}');

      return user;
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth error: ${e.code} - ${e.message}');

      switch (e.code) {
        case 'user-not-found':
          throw Exception('Aucun compte ne correspond à ce matricule');
        case 'wrong-password':
          throw Exception('Mot de passe incorrect');
        case 'invalid-email':
          throw Exception('Format de matricule invalide');
        case 'user-disabled':
          throw Exception('Ce compte a été désactivé');
        case 'too-many-requests':
          throw Exception(
            'Trop de tentatives de connexion. Veuillez réessayer plus tard',
          );
        case 'network-request-failed':
          throw Exception(
            'Erreur réseau. Vérifiez votre connexion internet',
          );
        default:
          throw Exception('Erreur d\'authentification: ${e.message}');
      }
    } catch (e) {
      debugPrint('Sign in error: $e');
      throw Exception('Erreur lors de la connexion: $e');
    }
  }

  /// Crée un nouvel utilisateur Firebase Auth
  /// Utilisé pour la migration initiale des utilisateurs mock
  Future<firebase_auth.UserCredential> createUser({
    required String matricule,
    required String password,
    String? sdisId,
  }) async {
    try {
      final email = _matriculeToEmail(matricule, sdisId: sdisId);

      debugPrint('Creating Firebase user for matricule: $matricule');

      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      debugPrint('Firebase user created: ${credential.user!.uid}');

      return credential;
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Firebase user creation error: ${e.code} - ${e.message}');

      switch (e.code) {
        case 'email-already-in-use':
          throw Exception('Ce matricule est déjà enregistré');
        case 'weak-password':
          throw Exception('Le mot de passe est trop faible');
        case 'invalid-email':
          throw Exception('Format de matricule invalide');
        default:
          throw Exception('Erreur lors de la création du compte: ${e.message}');
      }
    } catch (e) {
      debugPrint('User creation error: $e');
      throw Exception('Erreur lors de la création de l\'utilisateur: $e');
    }
  }

  /// Crée un nouvel utilisateur Firebase Auth sans déconnecter l'utilisateur actuel
  /// Utilisé par les administrateurs pour créer de nouveaux agents
  Future<void> createUserAsAdmin({
    required String adminMatricule,
    required String adminPassword,
    required String newUserMatricule,
    required String newUserPassword,
    String? sdisId,
  }) async {
    try {
      debugPrint('Admin creating user: $newUserMatricule');

      // Créer le nouvel utilisateur (cela va automatiquement le connecter)
      await createUser(
        matricule: newUserMatricule,
        password: newUserPassword,
        sdisId: sdisId,
      );

      debugPrint('New user created, reconnecting as admin...');

      // Se déconnecter et reconnecter en tant qu'admin
      await signOut();
      await signInWithEmailAndPassword(
        matricule: adminMatricule,
        password: adminPassword,
        sdisId: sdisId,
      );

      debugPrint('Admin session restored');
    } catch (e) {
      debugPrint('Error in createUserAsAdmin: $e');
      rethrow;
    }
  }

  /// Déconnexion
  Future<void> signOut() async {
    try {
      debugPrint('Signing out user: ${_auth.currentUser?.email}');

      // Nettoyer le cache
      _cachedClaims = null;

      await _auth.signOut();
      debugPrint('Sign out successful');
    } catch (e) {
      debugPrint('Sign out error: $e');
      throw Exception('Erreur lors de la déconnexion: $e');
    }
  }

  /// Change le mot de passe de l'utilisateur actuellement connecté
  Future<void> updatePassword(String newPassword) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('Aucun utilisateur connecté');
      }

      debugPrint('Updating password for user: ${user.email}');

      await user.updatePassword(newPassword);

      debugPrint('Password updated successfully');
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Password update error: ${e.code} - ${e.message}');

      switch (e.code) {
        case 'weak-password':
          throw Exception('Le nouveau mot de passe est trop faible');
        case 'requires-recent-login':
          throw Exception(
            'Pour des raisons de sécurité, veuillez vous reconnecter avant de changer votre mot de passe',
          );
        default:
          throw Exception(
            'Erreur lors du changement de mot de passe: ${e.message}',
          );
      }
    } catch (e) {
      debugPrint('Password update error: $e');
      throw Exception('Erreur lors du changement de mot de passe: $e');
    }
  }

  /// Réauthentifie l'utilisateur actuel
  /// Nécessaire avant des opérations sensibles comme le changement de mot de passe
  Future<void> reauthenticate({
    required String matricule,
    required String password,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('Aucun utilisateur connecté');
      }

      final email = _matriculeToEmail(matricule);
      final credential = firebase_auth.EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      debugPrint('Reauthenticating user: $email');

      await user.reauthenticateWithCredential(credential);

      debugPrint('Reauthentication successful');
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Reauthentication error: ${e.code} - ${e.message}');

      switch (e.code) {
        case 'wrong-password':
          throw Exception('Mot de passe incorrect');
        case 'user-mismatch':
          throw Exception('Le matricule ne correspond pas à l\'utilisateur connecté');
        case 'user-not-found':
          throw Exception('Utilisateur introuvable');
        case 'invalid-credential':
          throw Exception('Identifiants invalides');
        default:
          throw Exception('Erreur de réauthentification: ${e.message}');
      }
    } catch (e) {
      debugPrint('Reauthentication error: $e');
      throw Exception('Erreur lors de la réauthentification: $e');
    }
  }

  /// Envoie un email de réinitialisation de mot de passe
  Future<void> sendPasswordResetEmail(String matricule) async {
    try {
      final email = _matriculeToEmail(matricule);

      debugPrint('Sending password reset email to: $email');

      await _auth.sendPasswordResetEmail(email: email);

      debugPrint('Password reset email sent');
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Password reset error: ${e.code} - ${e.message}');

      switch (e.code) {
        case 'user-not-found':
          throw Exception('Aucun compte ne correspond à ce matricule');
        case 'invalid-email':
          throw Exception('Format de matricule invalide');
        default:
          throw Exception(
            'Erreur lors de l\'envoi de l\'email: ${e.message}',
          );
      }
    } catch (e) {
      debugPrint('Password reset error: $e');
      throw Exception('Erreur lors de l\'envoi de l\'email de réinitialisation: $e');
    }
  }

  /// Supprime le compte utilisateur actuel
  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('Aucun utilisateur connecté');
      }

      debugPrint('Deleting user account: ${user.email}');

      await user.delete();

      debugPrint('User account deleted');
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Account deletion error: ${e.code} - ${e.message}');

      switch (e.code) {
        case 'requires-recent-login':
          throw Exception(
            'Pour des raisons de sécurité, veuillez vous reconnecter avant de supprimer votre compte',
          );
        default:
          throw Exception('Erreur lors de la suppression du compte: ${e.message}');
      }
    } catch (e) {
      debugPrint('Account deletion error: $e');
      throw Exception('Erreur lors de la suppression du compte: $e');
    }
  }

  /// Convertit un matricule en email Firebase
  /// Format avec SDIS: {sdisId}_{matricule}@nexshift.app
  /// Format legacy: {matricule}@nexshift.app
  String _matriculeToEmail(String matricule, {String? sdisId}) {
    if (sdisId != null && sdisId.isNotEmpty) {
      return '${sdisId}_${matricule.toLowerCase()}@nexshift.app';
    }
    return '${matricule.toLowerCase()}@nexshift.app';
  }

  /// Extrait le matricule depuis un email Firebase
  String _emailToMatricule(String email) {
    return email.split('@')[0];
  }

  /// Fusionne les données d'un utilisateur (depuis la station) avec les données personnelles (depuis user_stations)
  /// Les données personnelles (firstName, lastName, fcmToken) viennent de user_stations
  /// Les données spécifiques à la station (team, status, skills) viennent du profil station
  User _mergeUserWithPersonalData(User stationUser, UserStations userStations) {
    return User(
      id: stationUser.id,
      firstName: userStations.firstName,  // Depuis user_stations
      lastName: userStations.lastName,    // Depuis user_stations
      station: stationUser.station,       // Depuis la station
      status: stationUser.status,         // Depuis la station
      team: stationUser.team,             // Depuis la station
      skills: stationUser.skills,         // Depuis la station
      admin: stationUser.admin,           // Depuis la station
    );
  }

  /// Charge le profil utilisateur pour une station spécifique
  /// Utilisé après que l'utilisateur a sélectionné une station dans le menu
  Future<User?> loadUserProfileForStation(String matricule, String stationId) async {
    try {
      debugPrint('🟡 [AUTH_SERVICE] loadUserProfileForStation called: matricule=$matricule, stationId=$stationId');
      debugPrint('🟡 [AUTH_SERVICE] Current SDIS Context: ${SDISContext().currentSDISId}');

      final user = await _userRepository.getById(matricule, stationId: stationId);

      if (user == null) {
        debugPrint('❌ [AUTH_SERVICE] User profile not found for station: $stationId');
        return null;
      }

      debugPrint('🟡 [AUTH_SERVICE] User found in station: ${user.firstName} ${user.lastName}, station=${user.station}');

      // Récupérer les données personnelles depuis user_stations
      final userStations = await _userStationsRepository.getUserStations(matricule);

      if (userStations == null) {
        debugPrint('⚠️ [AUTH_SERVICE] User stations not found, using station data as-is');
        return user;
      }

      debugPrint('🟡 [AUTH_SERVICE] User stations found: ${userStations.stations}');

      // Fusionner avec les données personnelles
      final mergedUser = _mergeUserWithPersonalData(user, userStations);

      debugPrint('✅ [AUTH_SERVICE] User profile loaded successfully: ${mergedUser.firstName} ${mergedUser.lastName} (${mergedUser.station})');
      return mergedUser;
    } catch (e) {
      debugPrint('❌ [AUTH_SERVICE] Error loading user profile for station: $e');
      return null;
    }
  }

  /// Charge le profil utilisateur par authUid pour une station spécifique
  /// Utilisé avec le nouveau système d'authentification par email avec données chiffrées
  /// Utilise une Cloud Function pour déchiffrer les PII
  Future<User?> loadUserByAuthUidForStation(
    String authUid,
    String sdisId,
    String stationId,
  ) async {
    try {
      debugPrint('🟡 [AUTH_SERVICE] loadUserByAuthUidForStation called: authUid=$authUid, sdisId=$sdisId, stationId=$stationId');

      // Utiliser la Cloud Function qui déchiffre les données
      final cloudFunctions = CloudFunctionsService();
      final user = await cloudFunctions.getUserByAuthUidForStation(
        authUid: authUid,
        stationId: stationId,
      );

      if (user == null) {
        debugPrint('❌ [AUTH_SERVICE] User not found by authUid in station: $stationId');
        return null;
      }

      debugPrint('✅ [AUTH_SERVICE] User loaded by authUid: ${user.firstName} ${user.lastName} (${user.station})');
      return user;
    } catch (e) {
      debugPrint('❌ [AUTH_SERVICE] Error loading user by authUid: $e');
      return null;
    }
  }

  /// Récupère le profil utilisateur complet de l'utilisateur connecté
  Future<User?> getCurrentUserProfile() async {
    try {
      final firebaseUser = _auth.currentUser;
      if (firebaseUser == null) {
        return null;
      }

      final email = firebaseUser.email;
      if (email == null) {
        return null;
      }

      final matricule = _emailToMatricule(email);
      return await _userRepository.getById(matricule);
    } catch (e) {
      debugPrint('Error getting current user profile: $e');
      return null;
    }
  }

  /// Crée un profil utilisateur dans Firestore pour un utilisateur Firebase Auth existant
  /// Crée d'abord l'entrée dans user_stations avec les données personnelles
  /// Puis crée le profil dans la station si une station est fournie
  Future<User> createUserProfile({
    required String matricule,
    required String firstName,
    required String lastName,
    String? station, // Station optionnelle (héritée de l'utilisateur créateur)
    String? sdisId,  // SDIS optionnel (pour architecture multi-SDIS)
  }) async {
    try {
      debugPrint('Creating user profile for matricule: $matricule');

      // 1. Créer l'entrée dans user_stations avec les données personnelles
      final stations = station != null && station.isNotEmpty ? [station] : <String>[];

      final userStations = UserStations(
        userId: matricule,
        stations: stations,
        firstName: firstName,
        lastName: lastName,
        fcmToken: null, // Sera mis à jour par PushNotificationService au premier lancement
      );

      await _userStationsRepository.createOrUpdateUserStations(userStations, sdisId: sdisId);

      debugPrint('User stations created with personal data');

      // 2. Si une station est fournie, créer le profil dans la station
      if (station != null && station.isNotEmpty) {
        final newUser = User(
          id: matricule,
          firstName: firstName, // Sera surchargé par user_stations lors du login
          lastName: lastName,   // Sera surchargé par user_stations lors du login
          station: station,
          status: 'agent',
          team: '',
          skills: const [],
          admin: false,
        );

        await _userRepository.upsert(newUser);
        debugPrint('User profile created in station: $station');

        return newUser;
      }

      // 3. Si pas de station, retourner un User temporaire
      debugPrint('User profile created without station assignment');

      return User(
        id: matricule,
        firstName: firstName,
        lastName: lastName,
        station: '',
        status: 'agent',
        team: '',
        skills: const [],
        admin: false,
      );
    } catch (e) {
      debugPrint('Error creating user profile: $e');
      throw Exception('Erreur lors de la création du profil utilisateur: $e');
    }
  }

  /// Récupère la liste de tous les utilisateurs Firebase Auth
  Future<List<String>> getAllAuthMatricules() async {
    try {
      // Note: Firebase Auth ne permet pas de lister tous les utilisateurs côté client
      // Cette fonctionnalité nécessiterait Firebase Admin SDK côté serveur
      // Pour l'instant, on retourne une liste vide
      debugPrint('Warning: getAllAuthMatricules() requires Firebase Admin SDK');
      return [];
    } catch (e) {
      debugPrint('Error getting auth matricules: $e');
      return [];
    }
  }

  /// Supprime un utilisateur Firebase Auth en se connectant temporairement avec son compte
  /// ATTENTION: Cette méthode déconnecte l'utilisateur actuel temporairement
  /// Utilisée par les administrateurs pour supprimer complètement un utilisateur
  Future<void> deleteUserByCredentials({
    required String matricule,
    required String password,
    required String adminMatricule,
    required String adminPassword,
  }) async {
    try {
      final email = _matriculeToEmail(matricule);
      final adminEmail = _matriculeToEmail(adminMatricule);

      debugPrint('🔥 Suppression du compte Auth pour: $matricule');
      debugPrint('👤 Admin actuel: $adminMatricule');

      // 1. Se connecter temporairement avec le compte à supprimer
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final userToDelete = userCredential.user;
      if (userToDelete == null) {
        throw Exception('Utilisateur non trouvé');
      }

      debugPrint('✅ Connexion temporaire réussie');

      // 2. Supprimer le compte
      await userToDelete.delete();
      debugPrint('✅ Compte Authentication supprimé');

      // 3. Reconnecter l'utilisateur admin
      try {
        debugPrint('🔄 Reconnexion de l\'admin...');
        await _auth.signInWithEmailAndPassword(
          email: adminEmail,
          password: adminPassword,
        );
        debugPrint('✅ Admin reconnecté: $adminMatricule');
      } catch (e) {
        debugPrint('⚠️ Impossible de reconnecter l\'admin: $e');
        throw Exception('Compte supprimé mais impossible de vous reconnecter. Veuillez vous reconnecter manuellement.');
      }
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('❌ Erreur Firebase Auth: ${e.code} - ${e.message}');

      switch (e.code) {
        case 'user-not-found':
          throw Exception('Aucun compte ne correspond à ce matricule');
        case 'wrong-password':
          throw Exception('Mot de passe incorrect');
        case 'invalid-email':
          throw Exception('Format de matricule invalide');
        case 'too-many-requests':
          throw Exception('Trop de tentatives. Réessayez plus tard');
        default:
          throw Exception('Erreur lors de la suppression: ${e.message}');
      }
    } catch (e) {
      debugPrint('❌ Erreur lors de la suppression: $e');
      rethrow;
    }
  }
}
