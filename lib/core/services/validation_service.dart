import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/replacement_acceptance_model.dart';

/// Information sur la couverture d'une demande de remplacement
class CoverageInfo {
  final double coveragePercentage; // 0.0 à 1.0
  final Duration totalDuration; // Durée totale de la demande
  final Duration coveredDuration; // Durée couverte par les acceptations
  final List<DateTimeRange> gaps; // Périodes non couvertes

  CoverageInfo({
    required this.coveragePercentage,
    required this.totalDuration,
    required this.coveredDuration,
    required this.gaps,
  });

  bool get isFullyCovered => coveragePercentage >= 1.0;
}

/// Plage de dates/heures
class DateTimeRange {
  final DateTime start;
  final DateTime end;

  DateTimeRange({required this.start, required this.end});

  Duration get duration => end.difference(start);
}

/// Service de gestion de la validation des remplacements par les chefs d'équipe
///
/// Phase 1 : Stub service - Interfaces définies, implémentation à venir
class ValidationService {
  final FirebaseFirestore _firestore;

  ValidationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Valide une acceptation de remplacement
  ///
  /// [acceptanceId] : ID de l'acceptation à valider
  /// [validatorId] : ID du chef validant (chef d'équipe/centre/admin)
  /// [comment] : Commentaire optionnel
  ///
  /// Crée un subshift et notifie l'agent remplaçant
  Future<void> validateAcceptance({
    required String acceptanceId,
    required String validatorId,
    String? comment,
  }) async {
    // TODO Phase 5 : Implémenter la logique de validation
    // 1. Vérifier les permissions du validateur
    // 2. Mettre à jour l'acceptation (status = validated)
    // 3. Créer le subshift
    // 4. Vérifier si la demande est complètement couverte
    // 5. Envoyer les notifications
    throw UnimplementedError('ValidationService.validateAcceptance() - À implémenter en Phase 5');
  }

  /// Rejette une acceptation de remplacement
  ///
  /// [acceptanceId] : ID de l'acceptation à rejeter
  /// [validatorId] : ID du chef rejetant
  /// [reason] : Motif du rejet (obligatoire)
  ///
  /// Notifie l'agent et reprend les vagues si nécessaire
  Future<void> rejectAcceptance({
    required String acceptanceId,
    required String validatorId,
    required String reason,
  }) async {
    // TODO Phase 5 : Implémenter la logique de rejet
    // 1. Vérifier les permissions du validateur
    // 2. Mettre à jour l'acceptation (status = rejected, rejectionReason)
    // 3. Notifier l'agent
    // 4. Reprendre les vagues si la demande n'est plus couverte
    throw UnimplementedError('ValidationService.rejectAcceptance() - À implémenter en Phase 5');
  }

  /// Calcule la couverture totale d'une demande de remplacement
  ///
  /// [requestId] : ID de la demande de remplacement
  ///
  /// Returns : [CoverageInfo] avec le pourcentage de couverture et les gaps
  Future<CoverageInfo> calculateCoverage(String requestId) async {
    // TODO Phase 5 : Implémenter le calcul de couverture
    // 1. Récupérer la demande de remplacement
    // 2. Récupérer toutes les acceptations (pending + validated)
    // 3. Calculer les intervalles couverts
    // 4. Calculer le pourcentage et identifier les gaps
    throw UnimplementedError('ValidationService.calculateCoverage() - À implémenter en Phase 5');
  }

  /// Envoie un rappel de validation au chef d'équipe
  ///
  /// [acceptanceId] : ID de l'acceptation
  ///
  /// Conditions d'envoi :
  /// - Acceptation créée il y a >24h ET/OU
  /// - Remplacement commence dans <12h
  Future<void> sendValidationReminder({
    required String acceptanceId,
  }) async {
    // TODO Phase 5 : Implémenter les rappels
    // 1. Vérifier les conditions (>24h OU <12h avant début)
    // 2. Trouver le chef d'équipe
    // 3. Créer un trigger de notification
    // 4. Mettre à jour lastReminderSentAt
    throw UnimplementedError('ValidationService.sendValidationReminder() - À implémenter en Phase 5');
  }

  /// Récupère les acceptations en attente de validation pour un chef
  ///
  /// [leaderId] : ID du chef d'équipe
  /// [stationId] : ID de la caserne (pour chefs de centre/admins)
  ///
  /// Returns : Stream des acceptations en attente
  Stream<List<ReplacementAcceptance>> getPendingValidations({
    required String leaderId,
    String? stationId,
  }) {
    // TODO Phase 5 : Implémenter la requête
    // 1. Filtrer par status = pending_validation
    // 2. Filtrer par équipe (chef d'équipe) ou caserne (chef de centre/admin)
    // 3. Trier par createdAt
    throw UnimplementedError('ValidationService.getPendingValidations() - À implémenter en Phase 5');
  }

  /// Vérifie si un utilisateur peut valider des acceptations
  ///
  /// [userId] : ID de l'utilisateur
  ///
  /// Returns : true si l'utilisateur est chef d'équipe, chef de centre ou admin
  Future<bool> canValidate(String userId) async {
    // TODO Phase 5 : Implémenter la vérification des permissions
    // Vérifier le statut de l'utilisateur (leader, chief, admin)
    throw UnimplementedError('ValidationService.canValidate() - À implémenter en Phase 5');
  }
}
