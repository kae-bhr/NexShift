import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/availability_model.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/repositories/availability_repository.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';
import 'package:nexshift_app/core/services/firebase_auth_service.dart';

class LocalRepository {
  final _planningRepository = PlanningRepository();
  final _availabilityRepository = AvailabilityRepository();
  final _subshiftRepository = SubshiftRepository();
  final _authService = FirebaseAuthService();

  /// Retourne tous les plannings sans filtre
  Future<List<Planning>> getAllPlannings() async {
    return await _planningRepository.getAll();
  }

  /// Authentifie un utilisateur avec Firebase Authentication (nouvelle version multi-stations et multi-SDIS)
  /// Retourne AuthenticationResult qui peut contenir plusieurs stations
  Future<AuthenticationResult> loginWithStations(
    String id,
    String password, {
    String? sdisId,
  }) async {
    try {
      final result = await _authService.signInWithStations(
        matricule: id,
        password: password,
        sdisId: sdisId,
      );
      return result;
    } on UserProfileNotFoundException {
      // Propager l'exception spécifique pour que la page login puisse la gérer
      rethrow;
    } catch (e) {
      throw Exception('Identifiants invalides');
    }
  }

  /// Charge le profil utilisateur pour une station spécifique
  Future<User?> loadUserForStation(String matricule, String stationId) async {
    return await _authService.loadUserProfileForStation(matricule, stationId);
  }

  /// Charge le profil utilisateur par authUid pour une station spécifique
  /// Utilisé avec le nouveau système d'authentification par email
  Future<User?> loadUserByAuthUidForStation(
    String authUid,
    String sdisId,
    String stationId,
  ) async {
    return await _authService.loadUserByAuthUidForStation(
      authUid,
      sdisId,
      stationId,
    );
  }

  /// Authentifie un utilisateur avec Firebase Authentication
  /// Retourne le profil utilisateur complet depuis Firestore
  /// @deprecated Utilisez loginWithStations() pour gérer les utilisateurs multi-stations
  Future<User> login(String id, String password) async {
    try {
      final user = await _authService.signInWithEmailAndPassword(
        matricule: id,
        password: password,
      );
      return user;
    } on UserProfileNotFoundException {
      // Propager l'exception spécifique pour que la page login puisse la gérer
      rethrow;
    } catch (e) {
      throw Exception('Identifiants invalides');
    }
  }

  /// Récupère le profil utilisateur associé à un matricule.
  Future<User> getUserProfile(String id) async {
    final userRepo = UserRepository();
    final user = await userRepo.getById(id);
    if (user != null) {
      return user;
    }
    throw Exception('Matricule inconnu');
  }

  /// Met à jour le profil utilisateur (notamment les compétences).
  Future<void> updateUserProfile(User updatedUser) async {
    final userRepo = UserRepository();
    await userRepo.upsert(updatedUser);
  }

  /// Met à jour le mot de passe via Firebase Authentication
  Future<void> updatePassword(String matricule, String newPassword) async {
    try {
      await _authService.updatePassword(newPassword);
    } catch (e) {
      throw Exception('Erreur lors du changement de mot de passe: $e');
    }
  }

  /// Réauthentifie l'utilisateur avant une opération sensible
  Future<void> reauthenticate(String matricule, String password) async {
    try {
      await _authService.reauthenticate(
        matricule: matricule,
        password: password,
      );
    } catch (e) {
      throw Exception('Erreur de réauthentification: $e');
    }
  }

  /// Déconnecte l'utilisateur actuel
  Future<void> logout() async {
    try {
      await _authService.signOut();
    } catch (e) {
      throw Exception('Erreur lors de la déconnexion: $e');
    }
  }

  /// Vérifie si un utilisateur est connecté
  bool get isAuthenticated => _authService.isAuthenticated;

  /// Récupère le profil de l'utilisateur actuellement connecté
  Future<User?> getCurrentUser() async {
    return await _authService.getCurrentUserProfile();
  }

  // ---------- USERS ----------
  Future<List<User>> getAllUsers() async {
    final userRepo = UserRepository();
    return await userRepo.getAll();
  }

  // ---------- PLANNINGS ----------

  /// Retourne la liste des plannings visibles pour un utilisateur donné.
  Future<List<Planning>> getPlanningsForUser(User user, bool agentView) async {
    final now = DateTime.now();
    final startWindow = now.subtract(const Duration(days: 1));
    final endWindow = now.add(const Duration(days: 30));

    final allPlannings = await _planningRepository.getAll();
    return allPlannings.where((p) {
      final inWindow =
          p.startTime.isAfter(startWindow) && p.startTime.isBefore(endWindow);
      if (!inWindow) return false;
      if (agentView) return p.agentsId.contains(user.id);
      return _matchUserScope(p, user);
    }).toList();
  }

  /// Retourne tous les plannings qui chevauchent l'intervalle [start, end).
  /// Inclus si p.endTime > start && p.startTime < end (chevauchement strict).
  Future<List<Planning>> getAllPlanningsInRange(
    DateTime start,
    DateTime end,
  ) async {
    return await _planningRepository.getAllInRange(start, end);
  }

  /// Retourne les plannings d'une station dans un intervalle
  Future<List<Planning>> getPlanningsByStationInRange(
    String stationId,
    DateTime start,
    DateTime end,
  ) async {
    return await _planningRepository.getByStationInRange(stationId, start, end);
  }

  /// Variante de getPlanningsForUser avec une période explicite.
  Future<List<Planning>> getPlanningsForUserInRange(
    User user,
    bool agentView,
    DateTime start,
    DateTime end,
  ) async {
    final allPlannings = await _planningRepository.getByStationInRange(
      user.station,
      start,
      end,
    );
    return allPlannings.where((p) {
      if (agentView) return p.agentsId.contains(user.id);
      return _matchUserScope(p, user);
    }).toList();
  }

  /// Logique d'accès selon le rôle utilisateur
  bool _matchUserScope(Planning p, User user) {
    switch (user.status) {
      case KConstants.statusAgent:
        return p.agentsId.contains(user.id);
      case KConstants.statusChief:
        return p.team == user.team;
      case KConstants.statusLeader:
        return true;
      default:
        return false;
    }
  }

  // --- Subshifts management ---
  Future<List<Subshift>> getSubshifts({String? stationId}) async {
    return await _subshiftRepository.getAll(stationId: stationId);
  }

  /// Retourne un planning par identifiant s'il existe.
  /// En mode subcollections, nécessite le stationId pour construire le bon chemin
  Future<Planning?> getPlanningById(String id, {String? stationId}) async {
    return await _planningRepository.getById(id, stationId: stationId);
  }

  Future<void> saveSubshifts(List<Subshift> subshifts) async {
    await _subshiftRepository.saveAll(subshifts);
  }

  // --- Availabilities management ---

  /// Récupère toutes les disponibilités
  Future<List<Availability>> getAvailabilities() async {
    return await _availabilityRepository.getAll();
  }

  /// Récupère les disponibilités d'un agent spécifique
  Future<List<Availability>> getAvailabilitiesForAgent(String agentId) async {
    return await _availabilityRepository.getByAgentId(agentId);
  }

  /// Récupère les disponibilités pour un planning
  Future<List<Availability>> getAvailabilitiesForPlanning(
    String planningId,
  ) async {
    return await _availabilityRepository.getByPlanningId(planningId);
  }

  /// Récupère les disponibilités dans une plage temporelle
  Future<List<Availability>> getAvailabilitiesInRange(
    DateTime start,
    DateTime end,
  ) async {
    return await _availabilityRepository.getInRange(start, end);
  }

  /// Ajoute une nouvelle disponibilité
  /// Valide que l'heure de début n'est pas dans le passé
  Future<void> addAvailability(Availability availability) async {
    final now = DateTime.now();
    if (availability.start.isBefore(now)) {
      throw Exception(
        'Impossible d\'ajouter une disponibilité avec une heure de début antérieure à maintenant',
      );
    }
    await _availabilityRepository.upsert(availability);
  }

  /// Supprime une disponibilité
  /// Si la disponibilité est en cours, elle est découpée (fin = maintenant)
  /// Si la disponibilité est terminée, elle ne peut pas être supprimée
  Future<void> deleteAvailability(String availabilityId) async {
    final all = await _availabilityRepository.getAll();
    final availability = all.where((a) => a.id == availabilityId).firstOrNull;

    if (availability == null) {
      throw Exception('Disponibilité introuvable');
    }

    final now = DateTime.now();

    // Si la disponibilité est terminée, on ne peut pas la supprimer
    if (availability.end.isBefore(now)) {
      throw Exception(
        'Impossible de supprimer une disponibilité déjà terminée',
      );
    }

    // Si la disponibilité est en cours ou future, on utilise deleteOngoing
    // qui gère automatiquement le découpage
    await _availabilityRepository.deleteOngoing(availabilityId);
  }

  /// Met à jour une disponibilité existante
  Future<void> updateAvailability(Availability availability) async {
    await _availabilityRepository.upsert(availability);
  }
}
