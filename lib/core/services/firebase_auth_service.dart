import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';

/// Exception lancée quand l'utilisateur existe dans Firebase Auth
/// mais n'a pas de profil dans Firestore
class UserProfileNotFoundException implements Exception {
  final String matricule;

  UserProfileNotFoundException(this.matricule);

  @override
  String toString() => 'User profile not found in Firestore for matricule: $matricule';
}

/// Service d'authentification Firebase
/// Gère l'authentification des utilisateurs avec Firebase Auth
/// et synchronise avec les données utilisateur dans Firestore
class FirebaseAuthService {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final UserRepository _userRepository = UserRepository();

  /// Récupère l'utilisateur Firebase actuellement connecté
  firebase_auth.User? get currentFirebaseUser => _auth.currentUser;

  /// Stream des changements d'état d'authentification
  Stream<firebase_auth.User?> get authStateChanges => _auth.authStateChanges();

  /// Vérifie si un utilisateur est connecté
  bool get isAuthenticated => _auth.currentUser != null;

  /// Récupère l'ID de l'utilisateur actuellement connecté
  String? get currentUserId => _auth.currentUser?.uid;

  /// Connexion avec email et mot de passe
  /// email = matricule@nexshift.app (généré automatiquement)
  Future<User> signInWithEmailAndPassword({
    required String matricule,
    required String password,
  }) async {
    try {
      // Convertir le matricule en email Firebase
      final email = _matriculeToEmail(matricule);

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
  }) async {
    try {
      final email = _matriculeToEmail(matricule);

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

  /// Déconnexion
  Future<void> signOut() async {
    try {
      debugPrint('Signing out user: ${_auth.currentUser?.email}');
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
  /// Format: matricule@nexshift.app
  String _matriculeToEmail(String matricule) {
    return '${matricule.toLowerCase()}@nexshift.app';
  }

  /// Extrait le matricule depuis un email Firebase
  String _emailToMatricule(String email) {
    return email.split('@')[0];
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
  Future<User> createUserProfile({
    required String matricule,
    required String firstName,
    required String lastName,
    String? station, // Station optionnelle (héritée de l'utilisateur créateur)
  }) async {
    try {
      debugPrint('Creating user profile for matricule: $matricule');

      // Créer un nouvel utilisateur avec les données minimales
      final newUser = User(
        id: matricule,
        firstName: firstName,
        lastName: lastName,
        station: station ?? '', // Hériter de la station si fournie, sinon vide
        status: 'agent', // Statut par défaut
        team: '', // Pas d'équipe par défaut
        skills: const [], // Pas de compétences par défaut
        admin: false,
      );

      // Sauvegarder dans Firestore
      await _userRepository.upsert(newUser);

      debugPrint('User profile created successfully');

      return newUser;
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
