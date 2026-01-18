import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';
import 'package:nexshift_app/core/data/models/position_model.dart';
import 'package:nexshift_app/core/data/models/availability_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/data/models/replacement_acceptance_model.dart';
import 'package:nexshift_app/core/repositories/availability_repository.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';
import 'package:nexshift_app/core/repositories/replacement_acceptance_repository.dart';
import 'package:nexshift_app/core/repositories/station_repository.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/services/wave_calculation_service.dart';
import 'package:nexshift_app/core/services/skill_criticality_service.dart';
// ReplacementMode est importé depuis station_model.dart

/// Type de notification de remplacement
enum ReplacementNotificationType {
  searchRequest, // Recherche de remplaçant
  replacementFound, // Remplaçant trouvé (envoyé au remplacé)
  replacementAssigned, // Assignation de remplacement (envoyé au chef)
}

/// Type de demande
enum RequestType {
  replacement, // Recherche de remplaçant
  availability, // Recherche d'agent disponible
}

/// Données d'une demande de remplacement pour notification
class ReplacementRequest {
  final String id;
  final String requesterId; // ID de la personne cherchant un remplaçant
  final String planningId;
  final DateTime startTime;
  final DateTime endTime;
  final String station;
  final String? team;
  final DateTime createdAt;
  final ReplacementRequestStatus status;
  final String? replacerId; // ID du remplaçant si accepté
  final DateTime? acceptedAt; // Date d'acceptation
  final DateTime?
  acceptedStartTime; // Heure de début du remplacement accepté (peut être partiel)
  final DateTime?
  acceptedEndTime; // Heure de fin du remplacement accepté (peut être partiel)
  final int
  currentWave; // Vague de notification actuelle (1 = équipe, 2 = skills identiques, 3 = 80%+, 4 = 60%+, 5 = autres)
  final List<String> notifiedUserIds; // IDs des utilisateurs déjà notifiés
  final DateTime? lastWaveSentAt; // Date d'envoi de la dernière vague
  final RequestType
  requestType; // Type de demande (replacement ou availability)
  final List<String>?
  requiredSkills; // Compétences requises (pour demandes de disponibilité)

  // NOUVEAUX CHAMPS - Phase 1
  final List<String> seenByUserIds; // IDs des utilisateurs ayant marqué "Vu"
  final List<String> declinedByUserIds; // IDs des utilisateurs ayant refusé
  final List<String> pendingValidationUserIds; // IDs des utilisateurs en attente de validation par le chef
  final ReplacementMode mode; // Mode de remplacement
  final bool wavesSuspended; // True si vagues suspendues (couverture atteinte)

  // NOUVEAU CHAMP - Phase 6
  final bool isSOS; // Mode urgence (bypass validations)

  ReplacementRequest({
    required this.id,
    required this.requesterId,
    required this.planningId,
    required this.startTime,
    required this.endTime,
    required this.station,
    this.team,
    required this.createdAt,
    required this.status,
    this.replacerId,
    this.acceptedAt,
    this.acceptedStartTime,
    this.acceptedEndTime,
    this.currentWave = 0,
    this.notifiedUserIds = const [],
    this.lastWaveSentAt,
    this.requestType = RequestType.replacement,
    this.requiredSkills,
    // Nouveaux champs avec valeurs par défaut
    this.seenByUserIds = const [],
    this.declinedByUserIds = const [],
    this.pendingValidationUserIds = const [],
    this.mode = ReplacementMode.similarity,
    this.wavesSuspended = false,
    this.isSOS = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'requesterId': requesterId,
      'planningId': planningId,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'station': station,
      'team': team,
      'createdAt': Timestamp.fromDate(createdAt),
      'status': status.toString().split('.').last,
      if (replacerId != null) 'replacerId': replacerId,
      if (acceptedAt != null) 'acceptedAt': Timestamp.fromDate(acceptedAt!),
      if (acceptedStartTime != null)
        'acceptedStartTime': Timestamp.fromDate(acceptedStartTime!),
      if (acceptedEndTime != null)
        'acceptedEndTime': Timestamp.fromDate(acceptedEndTime!),
      'currentWave': currentWave,
      'notifiedUserIds': notifiedUserIds,
      if (lastWaveSentAt != null)
        'lastWaveSentAt': Timestamp.fromDate(lastWaveSentAt!),
      'requestType': requestType.toString().split('.').last,
      if (requiredSkills != null) 'requiredSkills': requiredSkills,
      // Nouveaux champs
      'seenByUserIds': seenByUserIds,
      'declinedByUserIds': declinedByUserIds,
      'pendingValidationUserIds': pendingValidationUserIds,
      'mode': mode.toString().split('.').last,
      'wavesSuspended': wavesSuspended,
      'isSOS': isSOS,
    };
  }

  factory ReplacementRequest.fromJson(Map<String, dynamic> json) {
    return ReplacementRequest(
      id: json['id'] as String,
      requesterId: json['requesterId'] as String,
      planningId: json['planningId'] as String,
      startTime: (json['startTime'] as Timestamp).toDate(),
      endTime: (json['endTime'] as Timestamp).toDate(),
      station: json['station'] as String,
      team: json['team'] as String?,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      status: ReplacementRequestStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => ReplacementRequestStatus.pending,
      ),
      replacerId: json['replacerId'] as String?,
      acceptedAt: json['acceptedAt'] != null
          ? (json['acceptedAt'] as Timestamp).toDate()
          : null,
      acceptedStartTime: json['acceptedStartTime'] != null
          ? (json['acceptedStartTime'] as Timestamp).toDate()
          : null,
      acceptedEndTime: json['acceptedEndTime'] != null
          ? (json['acceptedEndTime'] as Timestamp).toDate()
          : null,
      currentWave: json['currentWave'] as int? ?? 0,
      notifiedUserIds: json['notifiedUserIds'] != null
          ? List<String>.from(json['notifiedUserIds'] as List)
          : const [],
      lastWaveSentAt: json['lastWaveSentAt'] != null
          ? (json['lastWaveSentAt'] as Timestamp).toDate()
          : null,
      requestType: json['requestType'] != null
          ? RequestType.values.firstWhere(
              (e) => e.toString().split('.').last == json['requestType'],
              orElse: () => RequestType.replacement,
            )
          : RequestType.replacement,
      requiredSkills: json['requiredSkills'] != null
          ? List<String>.from(json['requiredSkills'] as List)
          : null,
      // Nouveaux champs avec valeurs par défaut pour compatibilité
      seenByUserIds: json['seenByUserIds'] != null
          ? List<String>.from(json['seenByUserIds'] as List)
          : const [],
      declinedByUserIds: json['declinedByUserIds'] != null
          ? List<String>.from(json['declinedByUserIds'] as List)
          : const [],
      pendingValidationUserIds: json['pendingValidationUserIds'] != null
          ? List<String>.from(json['pendingValidationUserIds'] as List)
          : const [],
      mode: json['mode'] != null
          ? ReplacementMode.values.firstWhere(
              (e) => e.toString().split('.').last == json['mode'],
              orElse: () => ReplacementMode.similarity,
            )
          : ReplacementMode.similarity,
      wavesSuspended: json['wavesSuspended'] as bool? ?? false,
      isSOS: json['isSOS'] as bool? ?? false,
    );
  }
}

/// Statut d'une demande de remplacement
enum ReplacementRequestStatus {
  pending, // En attente de réponse
  accepted, // Acceptée par un remplaçant
  cancelled, // Annulée par le demandeur
  expired, // Expirée (pas de réponse dans le délai)
}

/// Service de gestion des notifications de remplacement
/// Gère la logique métier et les appels à la Cloud Function
class ReplacementNotificationService {
  // Exposer firestore pour permettre l'accès depuis le dialog
  final FirebaseFirestore firestore;
  final UserRepository _userRepository;
  final AvailabilityRepository _availabilityRepository;
  final SubshiftRepository _subshiftRepository;
  final ReplacementAcceptanceRepository _acceptanceRepository;
  final StationRepository _stationRepository;
  final SkillCriticalityService _criticalityService = SkillCriticalityService();

  /// Constructeur avec injection de dépendances (pour les tests)
  ReplacementNotificationService({
    FirebaseFirestore? firestore,
    UserRepository? userRepository,
    AvailabilityRepository? availabilityRepository,
    SubshiftRepository? subshiftRepository,
    ReplacementAcceptanceRepository? acceptanceRepository,
    StationRepository? stationRepository,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        _userRepository = userRepository ??
            (firestore != null
              ? UserRepository.forTest(firestore)
              : UserRepository()),
        _availabilityRepository = availabilityRepository ??
            (firestore != null
              ? AvailabilityRepository.forTest(firestore)
              : AvailabilityRepository()),
        _subshiftRepository = subshiftRepository ??
            (firestore != null
              ? SubshiftRepository.forTest(firestore)
              : SubshiftRepository()),
        _acceptanceRepository = acceptanceRepository ??
            (firestore != null
              ? ReplacementAcceptanceRepository.forTest(firestore)
              : ReplacementAcceptanceRepository()),
        _stationRepository = stationRepository ?? StationRepository();

  /// Retourne le chemin de collection pour les demandes de remplacement
  /// En dev avec SDIS: /sdis/{sdisId}/stations/{stationId}/replacements/automatic/replacementRequests
  /// En prod ou sans stationId: /replacementRequests
  String _getReplacementRequestsPath(String stationId) {
    if (EnvironmentConfig.useStationSubcollections && stationId.isNotEmpty) {
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null && sdisId.isNotEmpty) {
        return 'sdis/$sdisId/stations/$stationId/replacements/automatic/replacementRequests';
      }
      return 'stations/$stationId/replacements/automatic/replacementRequests';
    }
    return 'replacementRequests';
  }

  /// Retourne le chemin de collection pour les triggers de notification
  /// En dev avec SDIS: /sdis/{sdisId}/stations/{stationId}/replacements/automatic/notificationTriggers
  /// En prod: /notificationTriggers
  String _getNotificationTriggersPath(String stationId) {
    if (EnvironmentConfig.useStationSubcollections && stationId.isNotEmpty) {
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null && sdisId.isNotEmpty) {
        return 'sdis/$sdisId/stations/$stationId/replacements/automatic/notificationTriggers';
      }
      return 'stations/$stationId/replacements/automatic/notificationTriggers';
    }
    return 'notificationTriggers';
  }

  /// Retourne le chemin de collection pour les triggers de skip de vague
  /// En dev avec SDIS: /sdis/{sdisId}/stations/{stationId}/replacements/automatic/waveSkipTriggers
  String _getWaveSkipTriggersPath(String stationId) {
    if (EnvironmentConfig.useStationSubcollections && stationId.isNotEmpty) {
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null && sdisId.isNotEmpty) {
        return 'sdis/$sdisId/stations/$stationId/replacements/automatic/waveSkipTriggers';
      }
      return 'stations/$stationId/replacements/automatic/waveSkipTriggers';
    }
    return 'waveSkipTriggers';
  }

  /// Retourne le chemin de collection pour les acceptations de remplacement
  /// En dev avec SDIS: /sdis/{sdisId}/stations/{stationId}/replacements/automatic/replacementAcceptances
  /// En prod ou sans stationId: /replacementAcceptances
  String _getReplacementAcceptancesPath(String stationId) {
    if (EnvironmentConfig.useStationSubcollections && stationId.isNotEmpty) {
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null && sdisId.isNotEmpty) {
        return 'sdis/$sdisId/stations/$stationId/replacements/automatic/replacementAcceptances';
      }
      return 'stations/$stationId/replacements/automatic/replacementAcceptances';
    }
    return 'replacementAcceptances';
  }

  /// Retourne le chemin de collection pour les subshifts
  /// En dev avec SDIS: /sdis/{sdisId}/stations/{stationId}/replacements/subshifts
  /// En prod ou sans stationId: /subshifts
  String _getSubshiftsPath(String stationId) {
    if (EnvironmentConfig.useStationSubcollections && stationId.isNotEmpty) {
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null && sdisId.isNotEmpty) {
        return 'sdis/$sdisId/stations/$stationId/replacements/subshifts';
      }
      return 'stations/$stationId/replacements/subshifts';
    }
    return 'subshifts';
  }

  /// Crée une demande de remplacement et envoie les notifications
  /// Retourne l'ID de la demande créée
  ///
  /// [excludedUserIds] : Liste des IDs utilisateurs à exclure des notifications
  /// (utilisé pour les remplacements partiels : exclure ceux déjà notifiés)
  /// [requestType] : Type de demande (replacement ou availability)
  /// [requiredSkills] : Compétences requises (pour demandes de disponibilité)
  /// [initialWave] : Vague initiale pour la nouvelle demande (utilisé pour les demandes résiduelles)
  Future<String> createReplacementRequest({
    required String requesterId,
    required String planningId,
    required DateTime startTime,
    required DateTime endTime,
    required String station,
    String? team,
    List<String>? excludedUserIds,
    RequestType requestType = RequestType.replacement,
    List<String>? requiredSkills,
    int? initialWave,
    bool isResidualRequest = false,
    bool isSOS = false,
  }) async {
    try {
      debugPrint(
        '📤 Creating ${requestType == RequestType.availability ? "availability" : "replacement"} request${isResidualRequest ? " (residual)" : ""}...',
      );
      debugPrint('  Requester: $requesterId');
      debugPrint('  Period: $startTime - $endTime');
      if (requiredSkills != null && requiredSkills.isNotEmpty) {
        debugPrint('  Required skills: ${requiredSkills.join(", ")}');
      }
      if (initialWave != null) {
        debugPrint('  Initial wave: $initialWave');
      }
      if (isSOS) {
        debugPrint('  🚨 SOS MODE: All waves will be sent simultaneously');
      }

      // Créer la demande dans Firestore
      final requestsPath = _getReplacementRequestsPath(station);
      final requestRef = firestore.collection(requestsPath).doc();
      final request = ReplacementRequest(
        id: requestRef.id,
        requesterId: requesterId,
        planningId: planningId,
        startTime: startTime,
        endTime: endTime,
        station: station,
        team: team,
        createdAt: DateTime.now(),
        status: ReplacementRequestStatus.pending,
        requestType: requestType,
        requiredSkills: requiredSkills,
        currentWave: initialWave ?? 0, // Utiliser initialWave si fourni, sinon 0
        isSOS: isSOS,
      );

      await requestRef.set(request.toJson());

      debugPrint('✅ Request created: ${request.id}');
      if (excludedUserIds != null && excludedUserIds.isNotEmpty) {
        debugPrint(
          '  Excluding ${excludedUserIds.length} users from notifications',
        );
      }

      // Déclencher l'envoi des notifications via Cloud Function
      // La Cloud Function écoute les nouvelles demandes et envoie les notifications
      await _triggerNotifications(
        request,
        excludedUserIds: excludedUserIds,
        isResidualRequest: isResidualRequest,
      );

      return request.id;
    } catch (e) {
      debugPrint('❌ Error creating replacement request: $e');
      rethrow;
    }
  }

  /// Déclenche l'envoi des notifications
  ///
  /// Pour les demandes de REMPLACEMENT (système de vagues) :
  /// - Vague 0 (jamais notifiés) : Agents en astreinte durant le remplacement
  /// - Vague 1 : Agents de la même équipe (hors astreinte)
  /// - Vague 2 : Agents avec exactement les mêmes compétences
  /// - Vague 3 : Agents avec compétences très proches (80%+)
  /// - Vague 4 : Agents avec compétences relativement proches (60%+)
  /// - Vague 5 : Tous les autres agents
  ///
  /// Pour les demandes de DISPONIBILITÉ (vague unique) :
  /// - Envoie uniquement aux agents "Disponibles" ou "Remplacement partiel"
  ///
  /// [excludedUserIds] : IDs des utilisateurs à exclure (pour remplacements partiels)
  ///
  /// Cette méthode crée un document trigger que la Cloud Function va détecter
  Future<void> _triggerNotifications(
    ReplacementRequest request, {
    List<String>? excludedUserIds,
    bool isResidualRequest = false,
  }) async {
    try {
      // Si c'est une demande résiduelle (d'une acceptation partielle),
      // envoyer les notifications à la vague actuelle
      if (request.currentWave > 0 && !isResidualRequest) {
        debugPrint('⏭️ Skipping notifications: request already at wave ${request.currentWave}');
        return;
      }

      // Si c'est une demande résiduelle, notifier la vague actuelle
      if (isResidualRequest && request.currentWave > 0) {
        debugPrint('🔄 Sending notifications for residual request at wave ${request.currentWave}');
        await _notifyCurrentWaveForResidualRequest(request, excludedUserIds);
        return;
      }

      // Récupérer les informations du demandeur
      final requester = await _userRepository.getById(request.requesterId);
      if (requester == null) {
        throw Exception('Requester not found: ${request.requesterId}');
      }

      // Récupérer tous les utilisateurs de la station pour déterminer les vagues
      final allUsers = await _userRepository.getByStation(request.station);

      // Récupérer le planning pour connaître les agents en astreinte
      final planningsPath = EnvironmentConfig.getCollectionPath('plannings', request.station);
      final planningDoc = await firestore
          .collection(planningsPath)
          .doc(request.planningId)
          .get();

      final List<String> agentsInPlanning = [];
      String? planningTeam;
      if (planningDoc.exists) {
        final data = planningDoc.data();
        agentsInPlanning.addAll(List<String>.from(data?['agentsId'] ?? []));
        planningTeam = data?['team'] as String?;
      }

      debugPrint('📋 Planning has ${agentsInPlanning.length} agents on duty');

      // Si c'est une demande de disponibilité, utiliser une logique différente
      if (request.requestType == RequestType.availability) {
        await _triggerAvailabilityNotifications(
          request,
          requester,
          allUsers,
          agentsInPlanning,
          excludedUserIds,
        );
        return;
      }

      // Récupérer la configuration de la station pour déterminer le mode de remplacement
      final stationsPath = EnvironmentConfig.stationsCollectionPath;
      final stationDoc = await firestore
          .collection(stationsPath)
          .doc(request.station)
          .get();

      ReplacementMode replacementMode = ReplacementMode.similarity;
      if (stationDoc.exists) {
        final station = Station.fromJson({
          'id': stationDoc.id,
          ...stationDoc.data()!,
        });
        replacementMode = station.replacementMode;
        debugPrint('🔧 Station replacement mode: ${replacementMode.name}');
      }

      // MODE SOS: Envoyer toutes les vagues simultanément
      if (request.isSOS) {
        debugPrint('🚨 SOS MODE: Sending all waves simultaneously...');
        await _sendAllWavesSimultaneously(
          request,
          requester,
          allUsers,
          agentsInPlanning,
          planningTeam,
          excludedUserIds,
        );
        return;
      }

      // Mode de remplacement par similarité (seul mode supporté)
      // Vague 1: Membres de la même équipe que l'astreinte, NON présents dans le shift
      // Exclure: le demandeur, les agents en astreinte ET les utilisateurs exclus (remplacement partiel)
      final wave1Users = allUsers
          .where(
            (u) =>
                u.station == request.station &&
                u.team == (planningTeam ?? request.team) &&
                u.id != request.requesterId &&
                !agentsInPlanning.contains(u.id) &&
                !(excludedUserIds?.contains(u.id) ?? false),
          )
          .toList();

      debugPrint(
        '📨 Wave 1: Found ${wave1Users.length} team members available (${agentsInPlanning.length} excluded from planning)',
      );

      if (wave1Users.isEmpty) {
        debugPrint('⚠️ No team members available, wave 1 is empty');
        // Mettre à jour currentWave sans lastWaveSentAt pour permettre
        // le traitement immédiat de la vague suivante
        final requestsPath = _getReplacementRequestsPath(request.station);
        await firestore
            .collection(requestsPath)
            .doc(request.id)
            .update({
              'currentWave': 1,
              'notifiedUserIds': [],
              // NE PAS mettre lastWaveSentAt, pour forcer le traitement immédiat
            });

        // Créer un document trigger spécial pour traiter la vague suivante immédiatement
        final skipTriggersPath = _getWaveSkipTriggersPath(request.station);
        await firestore.collection(skipTriggersPath).add({
          'requestId': request.id,
          'skippedWave': 1,
          'createdAt': FieldValue.serverTimestamp(),
          'processed': false,
        });

        debugPrint('  → Wave skip trigger created, next wave will be processed immediately');
        return;
      }

      final targetUserIds = wave1Users.map((u) => u.id).toList();

      // Mettre à jour la demande avec les utilisateurs notifiés
      final requestsPath = _getReplacementRequestsPath(request.station);
      await firestore.collection(requestsPath).doc(request.id).update({
        'currentWave': 1,
        'notifiedUserIds': targetUserIds,
        'lastWaveSentAt': FieldValue.serverTimestamp(),
      });

      // Créer un document de notification trigger pour la vague 1
      // La Cloud Function va lire ce document et envoyer les notifications
      final notificationData = {
        'type': 'replacement_request',
        'requestId': request.id,
        'requesterId': request.requesterId,
        'requesterName': '${requester.firstName} ${requester.lastName}',
        'planningId': request.planningId,
        'startTime': Timestamp.fromDate(request.startTime),
        'endTime': Timestamp.fromDate(request.endTime),
        'station': request.station,
        'team': request.team,
        'targetUserIds': targetUserIds,
        'wave': 1,
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      };

      final triggersPath = _getNotificationTriggersPath(request.station);
      await firestore.collection(triggersPath).add(notificationData);

      debugPrint(
        '✅ Wave 1 notification trigger created for ${targetUserIds.length} users',
      );
    } catch (e) {
      debugPrint('❌ Error triggering notifications: $e');
      // Ne pas rethrow pour ne pas bloquer la création de la demande
    }
  }

  /// Envoie toutes les vagues simultanément en mode SOS
  /// Les compétences-clés (keySkills) restent vérifiées
  Future<void> _sendAllWavesSimultaneously(
    ReplacementRequest request,
    User requester,
    List<User> allUsers,
    List<String> agentsInPlanning,
    String? planningTeam,
    List<String>? excludedUserIds,
  ) async {
    try {
      // Calculer les vagues pour tous les utilisateurs
      final waveCalculationService = WaveCalculationService();

      // Récupérer les poids de rareté des compétences
      final skillRarityWeights = _criticalityService.calculateSkillRarityWeights(
        teamMembers: allUsers,
        requesterSkills: requester.skills,
      );

      // Grouper les utilisateurs par vague (de 1 à 5)
      final Map<int, List<String>> waveGroups = {};

      for (final user in allUsers) {
        // Exclure le demandeur et les utilisateurs exclus
        if (user.id == request.requesterId ||
            (excludedUserIds?.contains(user.id) ?? false)) {
          continue;
        }

        // Calculer la vague pour cet utilisateur
        final wave = waveCalculationService.calculateWave(
          requester: requester,
          candidate: user,
          planningTeam: planningTeam ?? request.team ?? '',
          agentsInPlanning: agentsInPlanning,
          skillRarityWeights: skillRarityWeights,
        );

        // Ignorer vague 0 (non notifiés)
        if (wave > 0 && wave <= 5) {
          waveGroups.putIfAbsent(wave, () => []);
          waveGroups[wave]!.add(user.id);
        }
      }

      // Collecter tous les utilisateurs notifiés
      final allNotifiedUserIds = <String>[];
      for (final userIds in waveGroups.values) {
        allNotifiedUserIds.addAll(userIds);
      }

      debugPrint('🚨 SOS Mode - Wave distribution:');
      for (var wave = 1; wave <= 5; wave++) {
        final count = waveGroups[wave]?.length ?? 0;
        if (count > 0) {
          debugPrint('  Wave $wave: $count users');
        }
      }
      debugPrint('  Total: ${allNotifiedUserIds.length} users to notify');

      // Mettre à jour la demande avec tous les utilisateurs notifiés
      // currentWave = 5 (dernière vague) pour indiquer que toutes les vagues ont été envoyées
      final requestsPath = _getReplacementRequestsPath(request.station);
      await firestore.collection(requestsPath).doc(request.id).update({
        'currentWave': 5,
        'notifiedUserIds': allNotifiedUserIds,
        'lastWaveSentAt': FieldValue.serverTimestamp(),
      });

      // Créer un trigger de notification pour chaque vague (en parallèle)
      final triggersPath = _getNotificationTriggersPath(request.station);
      final List<Future<void>> triggerFutures = [];

      for (var wave = 1; wave <= 5; wave++) {
        final waveUserIds = waveGroups[wave];
        if (waveUserIds == null || waveUserIds.isEmpty) continue;

        final notificationData = {
          'type': 'replacement_request',
          'requestId': request.id,
          'requesterId': request.requesterId,
          'requesterName': '${requester.firstName} ${requester.lastName}',
          'planningId': request.planningId,
          'startTime': Timestamp.fromDate(request.startTime),
          'endTime': Timestamp.fromDate(request.endTime),
          'station': request.station,
          'team': request.team,
          'targetUserIds': waveUserIds,
          'wave': wave,
          'isSOS': true, // Marquer comme SOS
          'createdAt': FieldValue.serverTimestamp(),
          'processed': false,
        };

        triggerFutures.add(
          firestore.collection(triggersPath).add(notificationData),
        );
      }

      // Attendre que tous les triggers soient créés
      await Future.wait(triggerFutures);

      debugPrint('✅ SOS Mode: All ${triggerFutures.length} wave triggers created simultaneously');
    } catch (e) {
      debugPrint('❌ Error sending all waves simultaneously: $e');
      rethrow;
    }
  }

  /// Notifie tous les utilisateurs jusqu'à la vague actuelle pour une demande résiduelle
  /// Utilisé après une acceptation partielle pour continuer les notifications
  /// Notifie TOUTES les vagues de 1 à currentWave (sauf utilisateurs exclus = ceux qui ont refusé)
  Future<void> _notifyCurrentWaveForResidualRequest(
    ReplacementRequest request,
    List<String>? excludedUserIds,
  ) async {
    try {
      debugPrint('🔄 Calculating users for waves 1-${request.currentWave} (residual request)');

      // Récupérer les informations du demandeur
      final requester = await _userRepository.getById(request.requesterId);
      if (requester == null) {
        debugPrint('❌ Requester not found: ${request.requesterId}');
        return;
      }

      // Récupérer la station
      final station = await _stationRepository.getById(request.station);
      if (station == null) {
        debugPrint('❌ Station not found: ${request.station}');
        return;
      }

      // Récupérer tous les utilisateurs et le planning
      final allUsers = await _userRepository.getByStation(request.station);
      final planningsPath = EnvironmentConfig.getCollectionPath('plannings', request.station);
      final planningDoc = await firestore.collection(planningsPath).doc(request.planningId).get();

      if (!planningDoc.exists) {
        debugPrint('❌ Planning not found: ${request.planningId}');
        return;
      }

      final planningData = planningDoc.data()!;
      final agentsInPlanning = List<String>.from(planningData['agentsId'] ?? []);
      final planningTeam = planningData['team'] as String? ?? '';

      // Calculer la distribution des vagues pour tous les utilisateurs
      final waveService = WaveCalculationService();

      // Calculer les poids de rareté des compétences
      final skillRarityWeights = <String, int>{};
      for (final user in allUsers) {
        for (final skill in user.skills) {
          skillRarityWeights[skill] = (skillRarityWeights[skill] ?? 0) + 1;
        }
      }

      // Calculer la vague pour chaque utilisateur et grouper par vague
      final waveDistribution = <int, List<String>>{};
      for (final user in allUsers) {
        if (user.id == request.requesterId) continue;
        if (user.station != request.station) continue;
        if (excludedUserIds?.contains(user.id) ?? false) continue;

        final userWave = waveService.calculateWave(
          requester: requester,
          candidate: user,
          planningTeam: planningTeam,
          agentsInPlanning: agentsInPlanning,
          skillRarityWeights: skillRarityWeights,
          stationSkillWeights: station.skillWeights,
        );

        // Grouper par vague
        waveDistribution[userWave] = [...(waveDistribution[userWave] ?? []), user.id];
      }

      // Récupérer TOUS les utilisateurs des vagues 1 à currentWave
      final allUsersToNotify = <String>[];
      for (int wave = 1; wave <= request.currentWave; wave++) {
        final waveUsers = waveDistribution[wave] ?? [];
        allUsersToNotify.addAll(waveUsers);
        debugPrint('  → Wave $wave: ${waveUsers.length} users');
      }

      debugPrint('  → Total users to notify: ${allUsersToNotify.length}');

      if (allUsersToNotify.isEmpty) {
        debugPrint('⚠️ No users to notify, request will not be notified');
        return;
      }

      // Mettre à jour la demande avec les utilisateurs notifiés
      final requestsPath = _getReplacementRequestsPath(request.station);
      await firestore.collection(requestsPath).doc(request.id).update({
        'notifiedUserIds': FieldValue.arrayUnion(allUsersToNotify),
        'lastWaveSentAt': FieldValue.serverTimestamp(),
      });

      // Créer un document de notification trigger pour chaque vague
      final triggersPath = _getNotificationTriggersPath(request.station);

      for (int wave = 1; wave <= request.currentWave; wave++) {
        final waveUsers = waveDistribution[wave] ?? [];
        if (waveUsers.isEmpty) continue;

        final notificationData = {
          'type': 'replacement_request',
          'requestId': request.id,
          'requesterId': request.requesterId,
          'requesterName': '${requester.firstName} ${requester.lastName}',
          'planningId': request.planningId,
          'startTime': Timestamp.fromDate(request.startTime),
          'endTime': Timestamp.fromDate(request.endTime),
          'station': request.station,
          'team': request.team,
          'targetUserIds': waveUsers,
          'wave': wave,
          'createdAt': FieldValue.serverTimestamp(),
          'processed': false,
        };

        await firestore.collection(triggersPath).add(notificationData);
        debugPrint('  ✅ Notification trigger created for wave $wave (${waveUsers.length} users)');
      }

      debugPrint(
        '✅ All notification triggers created for waves 1-${request.currentWave} (${allUsersToNotify.length} total users)',
      );
    } catch (e) {
      debugPrint('❌ Error notifying waves for residual request: $e');
      // Ne pas propager l'erreur pour ne pas bloquer la création de la demande résiduelle
    }
  }

  /// Déclenche les notifications basées sur les postes hiérarchiques
  ///
  /// Logique:
  /// - Vague 1: Agents avec le même poste (même ordre)
  /// - Vague 2+: Agents avec postes supérieurs (ordre inférieur)
  /// - Vagues finales (si allowUnderQualified): Agents avec postes inférieurs (ordre supérieur)
  Future<void> _triggerPositionBasedNotifications(
    ReplacementRequest request,
    User requester,
    List<User> allUsers,
    List<String> agentsInPlanning,
    String? planningTeam,
    List<String>? excludedUserIds,
  ) async {
    try {
      debugPrint('🎯 Using POSITION-BASED replacement mode');

      // Récupérer la configuration de la station
      final stationsPath = EnvironmentConfig.stationsCollectionPath;
      final stationDoc = await firestore
          .collection(stationsPath)
          .doc(request.station)
          .get();

      if (!stationDoc.exists) {
        debugPrint('⚠️ Station not found, falling back to similarity mode');
        // Fallback sur le mode similarité
        return;
      }

      final station = Station.fromJson({
        'id': stationDoc.id,
        ...stationDoc.data()!,
      });

      // Récupérer toutes les positions de la station
      final positionsSnapshot = await firestore
          .collection('positions')
          .where('stationId', isEqualTo: request.station)
          .orderBy('order')
          .get();

      if (positionsSnapshot.docs.isEmpty) {
        debugPrint('⚠️ No positions configured, falling back to similarity mode');
        return;
      }

      final positions = positionsSnapshot.docs
          .map((doc) => Position.fromFirestore(doc))
          .toList();

      // Trouver le poste du demandeur
      if (requester.positionId == null) {
        debugPrint('⚠️ Requester has no position assigned, using team-based wave');
        // Envoyer à toute l'équipe si pas de poste
        await _sendWaveToTeam(
          request,
          requester,
          allUsers,
          agentsInPlanning,
          planningTeam,
          excludedUserIds,
        );
        return;
      }

      final requesterPosition = positions.firstWhere(
        (p) => p.id == requester.positionId,
        orElse: () => Position(
          id: '',
          name: 'Unknown',
          stationId: request.station,
          order: 999,
        ),
      );

      if (requesterPosition.id.isEmpty) {
        debugPrint('⚠️ Requester position not found, using team-based wave');
        await _sendWaveToTeam(
          request,
          requester,
          allUsers,
          agentsInPlanning,
          planningTeam,
          excludedUserIds,
        );
        return;
      }

      debugPrint('📍 Requester position: ${requesterPosition.name} (order: ${requesterPosition.order})');

      // Vague 1: Agents avec le même poste
      final samePositionUsers = allUsers
          .where(
            (u) =>
                u.station == request.station &&
                u.positionId == requesterPosition.id &&
                u.id != request.requesterId &&
                !agentsInPlanning.contains(u.id) &&
                !(excludedUserIds?.contains(u.id) ?? false),
          )
          .toList();

      debugPrint('📨 Wave 1 (same position): Found ${samePositionUsers.length} agents');

      if (samePositionUsers.isEmpty) {
        // Passer directement à la vague suivante (postes supérieurs)
        await _sendNextPositionWave(
          request,
          requester,
          requesterPosition,
          positions,
          allUsers,
          agentsInPlanning,
          excludedUserIds,
          station.allowUnderQualifiedAutoAcceptance,
          1, // currentWave = 1 (on skip la vague 1)
        );
        return;
      }

      final targetUserIds = samePositionUsers.map((u) => u.id).toList();

      // Mettre à jour la demande
      final requestsPath = _getReplacementRequestsPath(request.station);
      await firestore.collection(requestsPath).doc(request.id).update({
        'currentWave': 1,
        'notifiedUserIds': targetUserIds,
        'lastWaveSentAt': FieldValue.serverTimestamp(),
      });

      // Créer le trigger de notification
      final notificationData = {
        'type': 'replacement_request',
        'requestId': request.id,
        'requesterId': request.requesterId,
        'requesterName': '${requester.firstName} ${requester.lastName}',
        'planningId': request.planningId,
        'startTime': Timestamp.fromDate(request.startTime),
        'endTime': Timestamp.fromDate(request.endTime),
        'station': request.station,
        'team': request.team,
        'targetUserIds': targetUserIds,
        'wave': 1,
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      };

      final triggersPath = _getNotificationTriggersPath(request.station);
      await firestore.collection(triggersPath).add(notificationData);

      debugPrint('✅ Position-based Wave 1 trigger created for ${targetUserIds.length} users');
    } catch (e) {
      debugPrint('❌ Error in position-based notifications: $e');
    }
  }

  /// Envoie une vague à toute l'équipe (fallback si pas de poste)
  Future<void> _sendWaveToTeam(
    ReplacementRequest request,
    User requester,
    List<User> allUsers,
    List<String> agentsInPlanning,
    String? planningTeam,
    List<String>? excludedUserIds,
  ) async {
    final teamUsers = allUsers
        .where(
          (u) =>
              u.station == request.station &&
              u.team == (planningTeam ?? request.team) &&
              u.id != request.requesterId &&
              !agentsInPlanning.contains(u.id) &&
              !(excludedUserIds?.contains(u.id) ?? false),
        )
        .toList();

    final requestsPath = _getReplacementRequestsPath(request.station);

    if (teamUsers.isEmpty) {
      debugPrint('⚠️ No team members available');
      await firestore.collection(requestsPath).doc(request.id).update({
        'currentWave': 1,
        'notifiedUserIds': [],
      });
      return;
    }

    final targetUserIds = teamUsers.map((u) => u.id).toList();

    await firestore.collection(requestsPath).doc(request.id).update({
      'currentWave': 1,
      'notifiedUserIds': targetUserIds,
      'lastWaveSentAt': FieldValue.serverTimestamp(),
    });

    final notificationData = {
      'type': 'replacement_request',
      'requestId': request.id,
      'requesterId': request.requesterId,
      'requesterName': '${requester.firstName} ${requester.lastName}',
      'planningId': request.planningId,
      'startTime': Timestamp.fromDate(request.startTime),
      'endTime': Timestamp.fromDate(request.endTime),
      'station': request.station,
      'team': request.team,
      'targetUserIds': targetUserIds,
      'wave': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'processed': false,
    };

    final triggersPath = _getNotificationTriggersPath(request.station);
    await firestore.collection(triggersPath).add(notificationData);
    debugPrint('✅ Team-based wave created for ${targetUserIds.length} users');
  }

  /// Envoie la prochaine vague basée sur les postes supérieurs/inférieurs
  Future<void> _sendNextPositionWave(
    ReplacementRequest request,
    User requester,
    Position requesterPosition,
    List<Position> allPositions,
    List<User> allUsers,
    List<String> agentsInPlanning,
    List<String>? excludedUserIds,
    bool allowUnderQualified,
    int currentWave,
  ) async {
    debugPrint('🔄 Sending next position wave (current: $currentWave)');

    // Trier les positions par ordre
    final sortedPositions = List<Position>.from(allPositions)
      ..sort((a, b) => a.order.compareTo(b.order));

    // Identifier les postes supérieurs (ordre inférieur) et inférieurs (ordre supérieur)
    final higherPositions = sortedPositions
        .where((p) => p.order < requesterPosition.order)
        .toList();
    final lowerPositions = sortedPositions
        .where((p) => p.order > requesterPosition.order)
        .toList();

    // Calculer quelle vague envoyer
    final nextWave = currentWave + 1;
    final higherWaveIndex = nextWave - 2; // Wave 2 = index 0, Wave 3 = index 1, etc.

    List<User> targetUsers = [];
    String waveDescription = '';

    if (higherWaveIndex < higherPositions.length) {
      // Encore des postes supérieurs à notifier
      final targetPosition = higherPositions[higherWaveIndex];
      waveDescription = 'higher position: ${targetPosition.name}';

      targetUsers = allUsers
          .where(
            (u) =>
                u.station == request.station &&
                u.positionId == targetPosition.id &&
                u.id != request.requesterId &&
                !agentsInPlanning.contains(u.id) &&
                !(excludedUserIds?.contains(u.id) ?? false),
          )
          .toList();
    } else if (allowUnderQualified) {
      // Plus de postes supérieurs, passer aux postes inférieurs si autorisé
      final lowerWaveIndex = higherWaveIndex - higherPositions.length;

      if (lowerWaveIndex < lowerPositions.length) {
        final targetPosition = lowerPositions[lowerWaveIndex];
        waveDescription = 'lower position: ${targetPosition.name}';

        targetUsers = allUsers
            .where(
              (u) =>
                  u.station == request.station &&
                  u.positionId == targetPosition.id &&
                  u.id != request.requesterId &&
                  !agentsInPlanning.contains(u.id) &&
                  !(excludedUserIds?.contains(u.id) ?? false),
            )
            .toList();
      }
    }

    final requestsPath = _getReplacementRequestsPath(request.station);

    if (targetUsers.isEmpty) {
      debugPrint('⚠️ Wave $nextWave ($waveDescription): No users found, search complete');
      await firestore.collection(requestsPath).doc(request.id).update({
        'currentWave': nextWave,
        'notifiedUserIds': [],
      });
      return;
    }

    debugPrint('📨 Wave $nextWave ($waveDescription): Found ${targetUsers.length} users');

    final targetUserIds = targetUsers.map((u) => u.id).toList();

    await firestore.collection(requestsPath).doc(request.id).update({
      'currentWave': nextWave,
      'notifiedUserIds': targetUserIds,
      'lastWaveSentAt': FieldValue.serverTimestamp(),
    });

    final notificationData = {
      'type': 'replacement_request',
      'requestId': request.id,
      'requesterId': request.requesterId,
      'requesterName': '${requester.firstName} ${requester.lastName}',
      'planningId': request.planningId,
      'startTime': Timestamp.fromDate(request.startTime),
      'endTime': Timestamp.fromDate(request.endTime),
      'station': request.station,
      'team': request.team,
      'targetUserIds': targetUserIds,
      'wave': nextWave,
      'createdAt': FieldValue.serverTimestamp(),
      'processed': false,
    };

    final triggersPath = _getNotificationTriggersPath(request.station);
    await firestore.collection(triggersPath).add(notificationData);
    debugPrint('✅ Position-based Wave $nextWave trigger created');
  }

  /// Déclenche les notifications pour une demande de disponibilité
  /// Envoie uniquement aux agents "Disponibles" (catégorie 0) ou "Remplacement partiel" (catégorie 1)
  Future<void> _triggerAvailabilityNotifications(
    ReplacementRequest request,
    User requester,
    List<User> allUsers,
    List<String> agentsInPlanning,
    List<String>? excludedUserIds,
  ) async {
    try {
      // Récupérer tous les subshifts pour ce planning
      final subshiftsPath = _getSubshiftsPath(request.station);
      final subshiftsSnapshot = await firestore
          .collection(subshiftsPath)
          .where('planningId', isEqualTo: request.planningId)
          .get();

      final existingSubshifts = subshiftsSnapshot.docs
          .map((doc) => doc.data())
          .toList();

      // Filtrer les agents disponibles ou en remplacement partiel
      final availableUsers = <User>[];

      debugPrint('📊 Analyzing ${allUsers.length} users for availability');
      debugPrint('  Agents in planning: ${agentsInPlanning.length}');
      debugPrint('  Existing subshifts: ${existingSubshifts.length}');

      for (final user in allUsers) {
        // Exclure le demandeur et les utilisateurs exclus
        if (user.id == request.requesterId) continue;
        if (excludedUserIds?.contains(user.id) ?? false) continue;
        if (user.station != request.station) continue;

        // Vérifier les compétences requises si spécifiées
        if (request.requiredSkills != null &&
            request.requiredSkills!.isNotEmpty) {
          final hasAllSkills = request.requiredSkills!.every(
            (skill) => user.skills.contains(skill),
          );
          if (!hasAllSkills) {
            debugPrint(
              '  User ${user.id} (${user.firstName} ${user.lastName}): missing required skills',
            );
            continue;
          }
        }

        // Calculer la catégorie de l'utilisateur
        final category = _calculateUserCategory(
          user,
          request.startTime,
          request.endTime,
          agentsInPlanning,
          existingSubshifts,
          request.planningId,
        );

        debugPrint(
          '  User ${user.id} (${user.firstName} ${user.lastName}): category $category',
        );

        // Catégorie 0 = Disponible, Catégorie 1 = Remplacement partiel
        if (category == 0 || category == 1) {
          availableUsers.add(user);
          debugPrint('    ✓ Added to available users');
        }
      }

      debugPrint(
        '📨 Availability request: Found ${availableUsers.length} available/partial users',
      );

      final requestsPath = _getReplacementRequestsPath(request.station);

      if (availableUsers.isEmpty) {
        debugPrint('⚠️ No available users found');
        await firestore
            .collection(requestsPath)
            .doc(request.id)
            .update({
              'currentWave': 1,
              'notifiedUserIds': [],
              'lastWaveSentAt': FieldValue.serverTimestamp(),
            });
        return;
      }

      final targetUserIds = availableUsers.map((u) => u.id).toList();

      // Mettre à jour la demande avec les utilisateurs notifiés
      await firestore.collection(requestsPath).doc(request.id).update({
        'currentWave': 1,
        'notifiedUserIds': targetUserIds,
        'lastWaveSentAt': FieldValue.serverTimestamp(),
      });

      // Créer un document de notification trigger
      final notificationData = {
        'type': 'availability_request',
        'requestId': request.id,
        'requesterId': request.requesterId,
        'requesterName': '${requester.firstName} ${requester.lastName}',
        'planningId': request.planningId,
        'startTime': Timestamp.fromDate(request.startTime),
        'endTime': Timestamp.fromDate(request.endTime),
        'station': request.station,
        'team': request.team,
        'targetUserIds': targetUserIds,
        'wave': 1,
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      };

      final triggersPath = _getNotificationTriggersPath(request.station);
      await firestore.collection(triggersPath).add(notificationData);

      debugPrint(
        '✅ Availability notification trigger created for ${targetUserIds.length} users',
      );
    } catch (e) {
      debugPrint('❌ Error triggering availability notifications: $e');
      // Ne pas rethrow pour ne pas bloquer la création de la demande
    }
  }

  /// Calcule la catégorie d'un utilisateur pour une période donnée
  /// Catégorie: 0=Disponible, 1=Partiel, 2=Remplacement total, 3=Astreinte, 4=Autres
  int _calculateUserCategory(
    User user,
    DateTime startTime,
    DateTime endTime,
    List<String> agentsInPlanning,
    List<Map<String, dynamic>> existingSubshifts,
    String planningId,
  ) {
    final selStart = startTime;
    final selEnd = endTime;
    final selDur = selEnd.difference(selStart);
    const tolerance = Duration(minutes: 1);

    final isPlanned = agentsInPlanning.contains(user.id);

    // Calculer le temps de chevauchement pour les remplacements où l'utilisateur est remplacé
    Duration replacedOverlaps = Duration.zero;
    for (final s in existingSubshifts) {
      if (s['planningId'] == planningId && s['replacedId'] == user.id) {
        final subStart = (s['start'] as Timestamp).toDate();
        final subEnd = (s['end'] as Timestamp).toDate();
        replacedOverlaps += _overlapDuration(
          subStart,
          subEnd,
          selStart,
          selEnd,
        );
      }
    }

    // Calculer le temps de chevauchement pour les remplacements où l'utilisateur est remplaçant
    Duration replacerOverlaps = Duration.zero;
    for (final s in existingSubshifts) {
      if (s['planningId'] == planningId && s['replacerId'] == user.id) {
        final subStart = (s['start'] as Timestamp).toDate();
        final subEnd = (s['end'] as Timestamp).toDate();
        replacerOverlaps += _overlapDuration(
          subStart,
          subEnd,
          selStart,
          selEnd,
        );
      }
    }

    final fullyReplaced = replacedOverlaps >= selDur - tolerance;
    final partiallyReplaced =
        replacedOverlaps > Duration.zero &&
        replacedOverlaps < selDur - tolerance;
    final replacerFull = replacerOverlaps >= selDur - tolerance;
    final replacerPartial =
        replacerOverlaps > Duration.zero &&
        replacerOverlaps < selDur - tolerance;
    final astreinteActive = isPlanned && replacedOverlaps == Duration.zero;

    final disponible =
        !astreinteActive &&
        replacerOverlaps == Duration.zero &&
        (!isPlanned || fullyReplaced);

    if (disponible) return 0;
    if (replacerPartial || partiallyReplaced) return 1;
    if (replacerFull) return 2;
    if (astreinteActive) return 3;
    return 4;
  }

  /// Calcule la durée de chevauchement entre deux périodes
  Duration _overlapDuration(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) {
    final overlaps = aStart.isBefore(bEnd) && aEnd.isAfter(bStart);
    if (!overlaps) return Duration.zero;
    final start = aStart.isAfter(bStart) ? aStart : bStart;
    final end = aEnd.isBefore(bEnd) ? aEnd : bEnd;
    return end.difference(start);
  }

  /// Vérifie si un agent est qualifié pour un remplacement
  /// Retourne true si l'agent possède toutes les compétences du demandeur ou plus
  bool _isAgentQualified(User requester, User acceptor) {
    final requesterSkills = Set<String>.from(requester.skills);
    final acceptorSkills = Set<String>.from(acceptor.skills);

    // L'accepteur est qualifié s'il possède toutes les compétences du demandeur
    return requesterSkills.difference(acceptorSkills).isEmpty;
  }

  /// Accepte une demande de remplacement (totale ou partielle)
  /// Selon la configuration de la station et les compétences de l'agent:
  /// - Si qualifié OU allowUnderQualifiedAutoAcceptance=true : acceptation automatique
  /// - Sinon : crée une ReplacementAcceptance en attente de validation par le chef
  Future<void> acceptReplacementRequest({
    required String requestId,
    required String replacerId,
    required String stationId,
    DateTime? acceptedStartTime,
    DateTime? acceptedEndTime,
  }) async {
    try {
      debugPrint('✅ Accepting replacement request: $requestId');
      debugPrint('  Replacer: $replacerId');
      debugPrint('  Station: $stationId');

      // Variables pour stocker les données de la requête
      late ReplacementRequest request;
      late DateTime actualStartTime;
      late DateTime actualEndTime;

      final requestsPath = _getReplacementRequestsPath(stationId);

      await firestore.runTransaction((transaction) async {
        final requestRef = firestore
            .collection(requestsPath)
            .doc(requestId);

        final requestDoc = await transaction.get(requestRef);

        if (!requestDoc.exists) {
          throw Exception('Replacement request not found: $requestId');
        }

        request = ReplacementRequest.fromJson(requestDoc.data()!);

        // Vérification atomique du statut
        if (request.status != ReplacementRequestStatus.pending) {
          throw Exception(
            'Cette demande a déjà été acceptée par quelqu\'un d\'autre',
          );
        }

        // Utiliser les heures acceptées ou les heures de la demande par défaut (remplacement total)
        actualStartTime = acceptedStartTime ?? request.startTime;
        actualEndTime = acceptedEndTime ?? request.endTime;

        // Vérifier que la plage acceptée est dans la plage demandée
        if (actualStartTime.isBefore(request.startTime) ||
            actualEndTime.isAfter(request.endTime) ||
            actualStartTime.isAfter(actualEndTime)) {
          throw Exception('Invalid time range for replacement');
        }
      });

      debugPrint('  Transaction completed - request status verified');

      // Récupérer le demandeur et l'accepteur pour vérifier les compétences
      final requester = await _userRepository.getById(request.requesterId);
      final acceptor = await _userRepository.getById(replacerId);

      if (requester == null || acceptor == null) {
        throw Exception('User not found');
      }

      // Récupérer la configuration de la station
      final station = await _stationRepository.getById(stationId);
      if (station == null) {
        throw Exception('Station not found: $stationId');
      }

      // Vérifier si l'agent est qualifié
      final isQualified = _isAgentQualified(requester, acceptor);

      debugPrint('  Agent qualified: $isQualified');
      debugPrint('  Station allowUnderQualifiedAutoAcceptance: ${station.allowUnderQualifiedAutoAcceptance}');

      // LOGIQUE DE DÉCISION : Acceptation automatique VS validation conditionnelle
      if (isQualified || station.allowUnderQualifiedAutoAcceptance) {
        // CAS 1: Acceptation automatique
        debugPrint('  → Acceptation automatique');

        // Mise à jour du statut de la demande
        final requestRef = firestore.collection(requestsPath).doc(requestId);
        await requestRef.update({
          'status': ReplacementRequestStatus.accepted.toString().split('.').last,
          'replacerId': replacerId,
          'acceptedAt': FieldValue.serverTimestamp(),
          'acceptedStartTime': Timestamp.fromDate(actualStartTime),
          'acceptedEndTime': Timestamp.fromDate(actualEndTime),
        });

        // Si c'est une demande de disponibilité, créer une availability
        if (request.requestType == RequestType.availability) {
          debugPrint('📅 Creating availability for agent: $replacerId');
          final availability = Availability.create(
            agentId: replacerId,
            start: actualStartTime,
            end: actualEndTime,
            planningId: request.planningId,
          );
          await _availabilityRepository.upsert(availability);
          debugPrint('✅ Availability created: ${availability.id}');
        }

        // Créer le subshift (pour les demandes de remplacement)
        if (request.requestType == RequestType.replacement) {
          debugPrint('📋 Creating subshift for replacement');
          final subshift = Subshift.create(
            replacedId: request.requesterId,
            replacerId: replacerId,
            start: actualStartTime,
            end: actualEndTime,
            planningId: request.planningId,
          );
          await _subshiftRepository.save(subshift, stationId: request.station, requestId: request.id);
          debugPrint('✅ Subshift created: ${subshift.id}');
        }

        // Ne PAS rejeter les acceptations en attente ici
        // Elles seront transférées vers les nouvelles demandes si c'est un remplacement partiel
        // Ou rejetées plus tard si c'est un remplacement total
      } else {
        // CAS 2: Validation conditionnelle requise
        debugPrint('  → Validation conditionnelle requise (agent sous-qualifié)');

        // Récupérer l'équipe de l'astreinte concernée
        final planningsPath = EnvironmentConfig.getCollectionPath('plannings', request.station);
        final planningDoc = await firestore
            .collection(planningsPath)
            .doc(request.planningId)
            .get();

        String chiefTeamId = '';
        if (planningDoc.exists) {
          final planningData = planningDoc.data();
          chiefTeamId = planningData?['team'] as String? ?? '';
        }

        // Créer une ReplacementAcceptance en attente de validation
        final acceptance = ReplacementAcceptance(
          id: firestore.collection('replacementAcceptances').doc().id,
          requestId: requestId,
          userId: replacerId,
          userName: '${acceptor.firstName} ${acceptor.lastName}',
          acceptedStartTime: actualStartTime,
          acceptedEndTime: actualEndTime,
          status: ReplacementAcceptanceStatus.pendingValidation,
          createdAt: DateTime.now(),
          chiefTeamId: chiefTeamId,
        );

        await _acceptanceRepository.upsert(acceptance, stationId: stationId);
        debugPrint('✅ ReplacementAcceptance created: ${acceptance.id} (pending validation)');
        debugPrint('   → chiefTeamId: "$chiefTeamId" (from planning team)');

        // Ajouter l'utilisateur dans pendingValidationUserIds de la demande
        final requestRef = firestore.collection(requestsPath).doc(requestId);
        await requestRef.update({
          'pendingValidationUserIds': FieldValue.arrayUnion([replacerId]),
        });
        debugPrint('✅ User added to pendingValidationUserIds: $replacerId');

        // Envoyer notification au chef d'équipe
        await _notifyChiefsForValidation(
          acceptance: acceptance,
          stationId: stationId,
          chiefTeamId: chiefTeamId,
          requester: requester,
          acceptor: acceptor,
        );

        // La demande reste PENDING (d'autres agents peuvent toujours accepter)
        return;
      }

      // Vérifier si c'est un remplacement partiel
      final isPartialReplacement =
          actualStartTime.isAfter(request.startTime) ||
          actualEndTime.isBefore(request.endTime);

      if (isPartialReplacement) {
        debugPrint('⚠️ Partial replacement detected');

        // Charger toutes les acceptations en attente pour cette demande
        final acceptancesPath = _getReplacementAcceptancesPath(stationId);
        final pendingAcceptancesSnapshot = await firestore
            .collection(acceptancesPath)
            .where('requestId', isEqualTo: requestId)
            .where('status', isEqualTo: 'pendingValidation')
            .get();

        final pendingAcceptances = pendingAcceptancesSnapshot.docs
            .map((doc) => ReplacementAcceptance.fromJson(doc.data()))
            .toList();

        debugPrint(
          '  Found ${pendingAcceptances.length} pending acceptances to transfer',
        );

        // Charger tous les refus pour cette demande
        final declinesPath = EnvironmentConfig.useStationSubcollections && stationId.isNotEmpty
            ? (SDISContext().currentSDISId != null && SDISContext().currentSDISId!.isNotEmpty
                ? 'sdis/${SDISContext().currentSDISId}/stations/$stationId/replacements/automatic/replacementRequestDeclines'
                : 'stations/$stationId/replacements/automatic/replacementRequestDeclines')
            : 'replacementRequestDeclines';

        final declinesSnapshot = await firestore
            .collection(declinesPath)
            .where('requestId', isEqualTo: requestId)
            .get();

        final declines = declinesSnapshot.docs.map((doc) => doc.data()).toList();

        debugPrint(
          '  Found ${declines.length} declines to transfer',
        );

        // Calculer les utilisateurs à exclure des nouvelles demandes
        // = UNIQUEMENT ceux qui ont refusé la demande originale
        // Si un utilisateur a refusé T1, il refusera mathématiquement T2 ⊂ T1
        // TOUS les autres utilisateurs (toutes vagues) doivent être re-notifiés car ils n'ont peut-être pas eu le temps de répondre
        final currentWave = request.currentWave;

        // Récupérer les utilisateurs qui ont refusé la demande originale
        List<String> excludedUserIds = [];
        for (final decline in declines) {
          final userId = decline['userId'] as String;
          if (!excludedUserIds.contains(userId)) {
            excludedUserIds.add(userId);
          }
        }

        debugPrint(
          '  Excluding ${excludedUserIds.length} users from new requests (users who declined original request)',
        );

        // Créer de nouvelles demandes pour les périodes non couvertes
        if (actualStartTime.isAfter(request.startTime)) {
          // Période avant le remplacement accepté
          debugPrint(
            '  Creating request for period before: ${request.startTime} - $actualStartTime',
          );
          final newRequestId = await createReplacementRequest(
            requesterId: request.requesterId,
            planningId: request.planningId,
            startTime: request.startTime,
            endTime: actualStartTime,
            station: request.station,
            team: request.team,
            excludedUserIds: excludedUserIds,
            requestType: request.requestType,
            requiredSkills: request.requiredSkills,
            initialWave: currentWave, // Conserver la vague actuelle
            isResidualRequest: true, // C'est une demande résiduelle
          );

          // Transférer les acceptations en attente qui couvrent cette période
          await _transferPendingAcceptances(
            pendingAcceptances,
            newRequestId,
            request.startTime,
            actualStartTime,
            stationId,
          );

          // Transférer les refus qui couvrent cette période
          await _transferDeclines(
            declines,
            newRequestId,
            request.startTime,
            actualStartTime,
            stationId,
            declinesPath,
          );
        }

        if (actualEndTime.isBefore(request.endTime)) {
          // Période après le remplacement accepté
          debugPrint(
            '  Creating request for period after: $actualEndTime - ${request.endTime}',
          );
          final newRequestId = await createReplacementRequest(
            requesterId: request.requesterId,
            planningId: request.planningId,
            startTime: actualEndTime,
            endTime: request.endTime,
            station: request.station,
            team: request.team,
            excludedUserIds: excludedUserIds,
            requestType: request.requestType,
            requiredSkills: request.requiredSkills,
            initialWave: currentWave, // Conserver la vague actuelle
            isResidualRequest: true, // C'est une demande résiduelle
          );

          // Transférer les acceptations en attente qui couvrent cette période
          await _transferPendingAcceptances(
            pendingAcceptances,
            newRequestId,
            actualEndTime,
            request.endTime,
            stationId,
          );

          // Transférer les refus qui couvrent cette période
          await _transferDeclines(
            declines,
            newRequestId,
            actualEndTime,
            request.endTime,
            stationId,
            declinesPath,
          );
        }
      }

      // Déclencher les notifications de confirmation avec les heures réelles
      await _sendConfirmationNotifications(
        request,
        replacerId,
        actualStartTime: actualStartTime,
        actualEndTime: actualEndTime,
      );

      debugPrint('✅ Replacement request accepted');
    } catch (e) {
      debugPrint('❌ Error accepting replacement request: $e');
      rethrow;
    }
  }

  /// Valide une acceptation de remplacement et crée le Subshift
  /// Appelé par le chef d'équipe depuis PendingAcceptancesTab
  Future<void> validateAcceptance({
    required String acceptanceId,
    required String validatedBy,
    required String stationId,
  }) async {
    try {
      debugPrint('✅ Validating acceptance: $acceptanceId');

      // 1. Récupérer l'acceptation
      final acceptance = await _acceptanceRepository.getById(
        acceptanceId,
        stationId: stationId,
      );

      if (acceptance == null) {
        throw Exception('Acceptation non trouvée: $acceptanceId');
      }

      // Vérifier que l'acceptation est bien en attente de validation
      if (acceptance.status != ReplacementAcceptanceStatus.pendingValidation) {
        throw Exception('Cette acceptation a déjà été traitée (statut: ${acceptance.status})');
      }

      // 2. Récupérer la demande de remplacement
      final requestsPath = _getReplacementRequestsPath(stationId);
      final requestDoc = await firestore
          .collection(requestsPath)
          .doc(acceptance.requestId)
          .get();

      if (!requestDoc.exists) {
        throw Exception('Demande de remplacement non trouvée: ${acceptance.requestId}');
      }

      final request = ReplacementRequest.fromJson(requestDoc.data()!);

      // 3. Valider l'acceptation de manière atomique
      await _acceptanceRepository.validate(
        acceptanceId,
        validatedBy,
        stationId: stationId,
      );

      // Retirer l'utilisateur de pendingValidationUserIds
      await firestore.collection(requestsPath).doc(acceptance.requestId).update({
        'pendingValidationUserIds': FieldValue.arrayRemove([acceptance.userId]),
      });
      debugPrint('✅ User removed from pendingValidationUserIds: ${acceptance.userId}');

      // 4. Créer le Subshift
      if (request.requestType == RequestType.replacement) {
        debugPrint('📋 Creating subshift for validated acceptance');
        final subshift = Subshift.create(
          replacedId: request.requesterId,
          replacerId: acceptance.userId,
          start: acceptance.acceptedStartTime,
          end: acceptance.acceptedEndTime,
          planningId: request.planningId,
        );
        await _subshiftRepository.save(subshift, stationId: stationId, requestId: request.id);
        debugPrint('✅ Subshift created: ${subshift.id}');
      }

      // 5. Vérifier si la demande est totalement couverte
      final isFullyCovered = await _checkIfRequestFullyCovered(
        request,
        acceptance,
        stationId,
      );

      // Vérifier si c'est une validation partielle
      final isPartialReplacement =
          acceptance.acceptedStartTime.isAfter(request.startTime) ||
          acceptance.acceptedEndTime.isBefore(request.endTime);

      if (isFullyCovered) {
        // Mettre à jour le statut de la demande
        await firestore.collection(requestsPath).doc(request.id).update({
          'status': ReplacementRequestStatus.accepted.toString().split('.').last,
          'replacerId': acceptance.userId,
          'acceptedAt': FieldValue.serverTimestamp(),
          'acceptedStartTime': Timestamp.fromDate(acceptance.acceptedStartTime),
          'acceptedEndTime': Timestamp.fromDate(acceptance.acceptedEndTime),
        });
        debugPrint('✅ Request fully covered and marked as accepted');

        // Rejeter automatiquement les autres acceptations en attente
        await _rejectOtherPendingAcceptances(
          requestId: request.id,
          validatedAcceptanceId: acceptanceId,
          validatedBy: validatedBy,
          stationId: stationId,
        );
      } else if (isPartialReplacement) {
        // VALIDATION PARTIELLE - Utiliser la même logique que l'auto-acceptation partielle
        debugPrint('⚠️ Partial replacement validation detected');

        // Charger toutes les acceptations en attente SAUF celle qui vient d'être validée
        final acceptancesPath = _getReplacementAcceptancesPath(stationId);
        final pendingAcceptancesSnapshot = await firestore
            .collection(acceptancesPath)
            .where('requestId', isEqualTo: request.id)
            .where('status', isEqualTo: 'pendingValidation')
            .get();

        final pendingAcceptances = pendingAcceptancesSnapshot.docs
            .map((doc) => ReplacementAcceptance.fromJson(doc.data()))
            .where((acc) => acc.id != acceptanceId) // Exclure l'acceptation validée
            .toList();

        debugPrint(
          '  Found ${pendingAcceptances.length} other pending acceptances to transfer',
        );

        // Charger tous les refus pour cette demande
        final declinesPath = EnvironmentConfig.useStationSubcollections && stationId.isNotEmpty
            ? (SDISContext().currentSDISId != null && SDISContext().currentSDISId!.isNotEmpty
                ? 'sdis/${SDISContext().currentSDISId}/stations/$stationId/replacements/automatic/replacementRequestDeclines'
                : 'stations/$stationId/replacements/automatic/replacementRequestDeclines')
            : 'replacementRequestDeclines';

        final declinesSnapshot = await firestore
            .collection(declinesPath)
            .where('requestId', isEqualTo: request.id)
            .get();

        final declines = declinesSnapshot.docs.map((doc) => doc.data()).toList();

        debugPrint(
          '  Found ${declines.length} declines to transfer',
        );

        // Calculer les utilisateurs à exclure = uniquement ceux qui ont refusé
        final currentWave = request.currentWave;
        List<String> excludedUserIds = [];
        for (final decline in declines) {
          final userId = decline['userId'] as String;
          if (!excludedUserIds.contains(userId)) {
            excludedUserIds.add(userId);
          }
        }

        debugPrint(
          '  Excluding ${excludedUserIds.length} users from new requests (users who declined original request)',
        );

        // Marquer la demande originale comme accepted avec les horaires de l'acceptation validée
        await firestore.collection(requestsPath).doc(request.id).update({
          'status': ReplacementRequestStatus.accepted.toString().split('.').last,
          'replacerId': acceptance.userId,
          'acceptedAt': FieldValue.serverTimestamp(),
          'acceptedStartTime': Timestamp.fromDate(acceptance.acceptedStartTime),
          'acceptedEndTime': Timestamp.fromDate(acceptance.acceptedEndTime),
        });
        debugPrint('✅ Request marked as accepted (partial)');

        // Créer de nouvelles demandes pour les périodes non couvertes
        if (acceptance.acceptedStartTime.isAfter(request.startTime)) {
          // Période avant le remplacement accepté
          debugPrint(
            '  Creating request for period before: ${request.startTime} - ${acceptance.acceptedStartTime}',
          );
          final newRequestId = await createReplacementRequest(
            requesterId: request.requesterId,
            planningId: request.planningId,
            startTime: request.startTime,
            endTime: acceptance.acceptedStartTime,
            station: request.station,
            team: request.team,
            excludedUserIds: excludedUserIds,
            requestType: request.requestType,
            requiredSkills: request.requiredSkills,
            initialWave: currentWave,
            isResidualRequest: true,
          );

          // Transférer les acceptations en attente qui couvrent cette période
          await _transferPendingAcceptances(
            pendingAcceptances,
            newRequestId,
            request.startTime,
            acceptance.acceptedStartTime,
            stationId,
          );

          // Transférer les refus qui couvrent cette période
          await _transferDeclines(
            declines,
            newRequestId,
            request.startTime,
            acceptance.acceptedStartTime,
            stationId,
            declinesPath,
          );
        }

        if (acceptance.acceptedEndTime.isBefore(request.endTime)) {
          // Période après le remplacement accepté
          debugPrint(
            '  Creating request for period after: ${acceptance.acceptedEndTime} - ${request.endTime}',
          );
          final newRequestId = await createReplacementRequest(
            requesterId: request.requesterId,
            planningId: request.planningId,
            startTime: acceptance.acceptedEndTime,
            endTime: request.endTime,
            station: request.station,
            team: request.team,
            excludedUserIds: excludedUserIds,
            requestType: request.requestType,
            requiredSkills: request.requiredSkills,
            initialWave: currentWave,
            isResidualRequest: true,
          );

          // Transférer les acceptations en attente qui couvrent cette période
          await _transferPendingAcceptances(
            pendingAcceptances,
            newRequestId,
            acceptance.acceptedEndTime,
            request.endTime,
            stationId,
          );

          // Transférer les refus qui couvrent cette période
          await _transferDeclines(
            declines,
            newRequestId,
            acceptance.acceptedEndTime,
            request.endTime,
            stationId,
            declinesPath,
          );
        }

        debugPrint('✅ Partial replacement handled with state transfer');
      } else {
        // Cas improbable : acceptation totale mais pas fully covered?
        debugPrint('⚠️ Unexpected case: acceptance covers request but not marked as fully covered');

        // Rejeter les autres acceptations en attente
        await _rejectOtherPendingAcceptances(
          requestId: request.id,
          validatedAcceptanceId: acceptanceId,
          validatedBy: validatedBy,
          stationId: stationId,
        );
      }

      // 6. Envoyer notifications de confirmation
      await _sendValidationConfirmationNotifications(
        request: request,
        acceptance: acceptance,
        stationId: stationId,
      );

      debugPrint('✅ Acceptance validated successfully');
    } catch (e) {
      debugPrint('❌ Error validating acceptance: $e');
      rethrow;
    }
  }

  /// Rejette TOUTES les acceptations en attente pour une demande (acceptation automatique)
  Future<void> _rejectAllPendingAcceptances({
    required String requestId,
    required String acceptedUserId,
    required String requesterName,
    required String stationId,
  }) async {
    try {
      debugPrint('🔄 Rejecting all pending acceptances for request: $requestId');

      // Récupérer toutes les acceptations en attente pour cette demande
      final allAcceptances = await _acceptanceRepository.getByRequestId(
        requestId,
        stationId: stationId,
      );

      // Filtrer pour ne garder que celles en attente
      final pendingToReject = allAcceptances.where((acc) =>
        acc.status == ReplacementAcceptanceStatus.pendingValidation
      ).toList();

      if (pendingToReject.isEmpty) {
        debugPrint('✅ No pending acceptances to reject');
        return;
      }

      debugPrint('🔄 Found ${pendingToReject.length} pending acceptance(s) to reject');

      // Rejeter chaque acceptation en attente avec notification
      for (final acceptance in pendingToReject) {
        final reason = 'Le remplacement de l\'agent $requesterName a été accepté par un autre utilisateur.';

        await _acceptanceRepository.reject(
          acceptance.id,
          'SYSTEM', // Rejet automatique par le système
          reason,
          stationId: stationId,
        );

        debugPrint('✅ Rejected acceptance: ${acceptance.id} for user: ${acceptance.userId}');

        // Envoyer une notification à l'utilisateur dont l'acceptation est rejetée
        try {
          await _sendRejectionNotification(
            userId: acceptance.userId,
            requesterName: requesterName,
            reason: reason,
            stationId: stationId,
          );
        } catch (e) {
          debugPrint('⚠️ Failed to send rejection notification to user ${acceptance.userId}: $e');
        }
      }

      debugPrint('✅ All pending acceptances rejected');
    } catch (e) {
      debugPrint('❌ Error rejecting pending acceptances: $e');
      // Ne pas propager l'erreur pour ne pas bloquer l'acceptation principale
    }
  }

  /// Rejette automatiquement les autres acceptations en attente pour une demande (validation manuelle)
  Future<void> _rejectOtherPendingAcceptances({
    required String requestId,
    required String validatedAcceptanceId,
    required String validatedBy,
    required String stationId,
  }) async {
    try {
      debugPrint('🔄 Rejecting other pending acceptances for request: $requestId');

      // Récupérer la demande pour avoir le nom du remplacé
      final requestsPath = _getReplacementRequestsPath(stationId);
      final requestDoc = await firestore.collection(requestsPath).doc(requestId).get();

      String requesterName = 'l\'agent';
      if (requestDoc.exists) {
        final requestData = requestDoc.data();
        final requesterId = requestData?['requesterId'] as String?;
        if (requesterId != null) {
          try {
            final requester = await _userRepository.getById(requesterId);
            if (requester != null) {
              requesterName = '${requester.firstName} ${requester.lastName}';
            }
          } catch (e) {
            debugPrint('⚠️ Could not load requester name: $e');
          }
        }
      }

      // Récupérer toutes les acceptations en attente pour cette demande
      final otherAcceptances = await _acceptanceRepository.getByRequestId(
        requestId,
        stationId: stationId,
      );

      // Filtrer pour ne garder que celles en attente et différentes de celle validée
      final pendingToReject = otherAcceptances.where((acc) =>
        acc.id != validatedAcceptanceId &&
        acc.status == ReplacementAcceptanceStatus.pendingValidation
      ).toList();

      if (pendingToReject.isEmpty) {
        debugPrint('✅ No other pending acceptances to reject');
        return;
      }

      debugPrint('🔄 Found ${pendingToReject.length} pending acceptance(s) to reject');

      // Rejeter chaque acceptation en attente avec notification
      for (final acceptance in pendingToReject) {
        final reason = 'Le remplacement de l\'agent $requesterName a été accepté par un autre utilisateur.';

        await _acceptanceRepository.reject(
          acceptance.id,
          validatedBy,
          reason,
          stationId: stationId,
        );

        debugPrint('✅ Rejected acceptance: ${acceptance.id} for user: ${acceptance.userId}');

        // Envoyer une notification à l'utilisateur dont l'acceptation est rejetée
        try {
          await _sendRejectionNotification(
            userId: acceptance.userId,
            requesterName: requesterName,
            reason: reason,
            stationId: stationId,
          );
        } catch (e) {
          debugPrint('⚠️ Failed to send rejection notification to user ${acceptance.userId}: $e');
        }
      }

      debugPrint('✅ All other pending acceptances rejected');
    } catch (e) {
      debugPrint('❌ Error rejecting other pending acceptances: $e');
      // Ne pas propager l'erreur pour ne pas bloquer la validation principale
    }
  }

  /// Adapte les acceptations en attente vers une nouvelle demande de remplacement
  /// Utilisé lors d'une acceptation partielle pour préserver les acceptations qui couvrent la période résiduelle
  /// CRÉATION de NOUVELLES acceptations au lieu de MODIFICATION (permet le split en plusieurs périodes)
  Future<void> _transferPendingAcceptances(
    List<ReplacementAcceptance> pendingAcceptances,
    String newRequestId,
    DateTime periodStart,
    DateTime periodEnd,
    String stationId,
  ) async {
    try {
      debugPrint('🔄 Adapting pending acceptances for new request: $newRequestId');
      debugPrint('  New period: $periodStart -> $periodEnd');

      final acceptancesPath = _getReplacementAcceptancesPath(stationId);
      final requestsPath = _getReplacementRequestsPath(stationId);

      int createdCount = 0;
      int deletedCount = 0;
      final Set<String> originalRequestIds = {};
      final Set<String> usersToAddToNewRequest = {};
      final Set<String> originalAcceptanceIdsToDelete = {}; // IDs des acceptations originales à supprimer

      for (final acceptance in pendingAcceptances) {
        debugPrint('  Checking acceptance for user ${acceptance.userId}: ${acceptance.acceptedStartTime} -> ${acceptance.acceptedEndTime}');

        // Vérifier si l'acceptation couvre (même partiellement) la nouvelle période
        final acceptanceCoversNewPeriod =
            acceptance.acceptedStartTime.isBefore(periodEnd) &&
            acceptance.acceptedEndTime.isAfter(periodStart);

        if (acceptanceCoversNewPeriod) {
          // Calculer les nouvelles heures (intersection avec la nouvelle période)
          final newStart = acceptance.acceptedStartTime.isBefore(periodStart)
              ? periodStart
              : acceptance.acceptedStartTime;
          final newEnd = acceptance.acceptedEndTime.isAfter(periodEnd)
              ? periodEnd
              : acceptance.acceptedEndTime;

          debugPrint('    ✅ Couvre la nouvelle période, adaptation: $newStart -> $newEnd');

          // CRÉER une NOUVELLE acceptation pour cette période au lieu de modifier l'existante
          // Cela permet de gérer le cas où une acceptation couvre plusieurs périodes résiduelles
          final newAcceptanceId = firestore.collection(acceptancesPath).doc().id;
          final newAcceptance = ReplacementAcceptance(
            id: newAcceptanceId,
            requestId: newRequestId,
            userId: acceptance.userId,
            userName: acceptance.userName,
            acceptedStartTime: newStart,
            acceptedEndTime: newEnd,
            status: ReplacementAcceptanceStatus.pendingValidation,
            createdAt: DateTime.now(),
            chiefTeamId: acceptance.chiefTeamId,
          );

          await firestore
              .collection(acceptancesPath)
              .doc(newAcceptanceId)
              .set(newAcceptance.toJson());

          // Marquer l'acceptation originale pour suppression (sera faite à la fin)
          originalAcceptanceIdsToDelete.add(acceptance.id);

          // Garder trace de la demande originale et de l'utilisateur
          originalRequestIds.add(acceptance.requestId);
          usersToAddToNewRequest.add(acceptance.userId);

          createdCount++;
          debugPrint('    ✅ Created new acceptance $newAcceptanceId for user ${acceptance.userId} on request $newRequestId');
        } else {
          // L'acceptation ne couvre pas la période résiduelle -> supprimer immédiatement
          debugPrint('    ❌ Ne couvre pas la nouvelle période, suppression');

          await firestore
              .collection(acceptancesPath)
              .doc(acceptance.id)
              .delete();

          // Envoyer une notification de rejet
          final requestSnapshot = await firestore
              .collection(requestsPath)
              .doc(acceptance.requestId)
              .get();

          if (requestSnapshot.exists) {
            final requestData = requestSnapshot.data();
            final requesterName = requestData?['requesterName'] as String? ?? 'Agent';

            await _sendRejectionNotification(
              userId: acceptance.userId,
              requesterName: requesterName,
              reason: 'La période que vous aviez acceptée est maintenant entièrement couverte.',
              stationId: stationId,
            );
          }

          originalRequestIds.add(acceptance.requestId);
          deletedCount++;
          debugPrint('    ✅ Deleted acceptance ${acceptance.id} for user ${acceptance.userId}');
        }
      }

      // Supprimer les acceptations originales qui ont été splitées en nouvelles acceptations
      for (final acceptanceId in originalAcceptanceIdsToDelete) {
        // Vérifier si cette acceptation existe encore (elle pourrait avoir été supprimée par un appel précédent)
        final acceptanceDoc = await firestore
            .collection(acceptancesPath)
            .doc(acceptanceId)
            .get();

        if (acceptanceDoc.exists) {
          await firestore
              .collection(acceptancesPath)
              .doc(acceptanceId)
              .delete();
          deletedCount++;
          debugPrint('    🗑️ Deleted original acceptance $acceptanceId after split');
        } else {
          debugPrint('    ℹ️ Original acceptance $acceptanceId already deleted');
        }
      }

      // Ajouter tous les utilisateurs transférés dans pendingValidationUserIds ET notifiedUserIds de la nouvelle demande
      if (usersToAddToNewRequest.isNotEmpty) {
        await firestore.collection(requestsPath).doc(newRequestId).update({
          'pendingValidationUserIds': FieldValue.arrayUnion(usersToAddToNewRequest.toList()),
          'notifiedUserIds': FieldValue.arrayUnion(usersToAddToNewRequest.toList()),
        });
        debugPrint('  ✅ Added ${usersToAddToNewRequest.length} users to new request');
      }

      // Nettoyer pendingValidationUserIds des demandes originales
      for (final originalRequestId in originalRequestIds) {
        // Récupérer les acceptations restantes pour cette demande
        final remainingAcceptances = await firestore
            .collection(acceptancesPath)
            .where('requestId', isEqualTo: originalRequestId)
            .where('status', isEqualTo: 'pendingValidation')
            .get();

        // Mettre à jour pendingValidationUserIds avec seulement les utilisateurs restants
        final remainingUserIds = remainingAcceptances.docs
            .map((doc) => doc.data()['userId'] as String)
            .toList();

        await firestore.collection(requestsPath).doc(originalRequestId).update({
          'pendingValidationUserIds': remainingUserIds,
        });

        debugPrint(
          '  🧹 Cleaned up pendingValidationUserIds for request $originalRequestId (${remainingUserIds.length} remaining)',
        );
      }

      debugPrint('✅ Created $createdCount new acceptances, deleted $deletedCount acceptances');
    } catch (e) {
      debugPrint('❌ Error adapting pending acceptances: $e');
      // Ne pas propager l'erreur pour ne pas bloquer la création de la nouvelle demande
    }
  }

  /// Transfère les refus vers une nouvelle demande de remplacement
  /// Utilisé lors d'une acceptation partielle pour reporter les refus sur les périodes résiduelles
  Future<void> _transferDeclines(
    List<Map<String, dynamic>> declines,
    String newRequestId,
    DateTime periodStart,
    DateTime periodEnd,
    String stationId,
    String declinesPath,
  ) async {
    try {
      debugPrint('🔄 Transferring declines to new request: $newRequestId');

      int transferredCount = 0;

      for (final decline in declines) {
        final userId = decline['userId'] as String;

        // Créer un nouveau refus pour la nouvelle demande
        await firestore.collection(declinesPath).add({
          'requestId': newRequestId,
          'userId': userId,
          'declinedAt': FieldValue.serverTimestamp(),
          'reason': decline['reason'] ?? 'Refusé sur période plus large',
        });

        transferredCount++;
        debugPrint('  ✅ Transferred decline for user $userId');
      }

      debugPrint('✅ Transferred $transferredCount declines');
    } catch (e) {
      debugPrint('❌ Error transferring declines: $e');
      // Ne pas propager l'erreur pour ne pas bloquer la création de la nouvelle demande
    }
  }

  /// Envoie une notification de rejet à un utilisateur
  Future<void> _sendRejectionNotification({
    required String userId,
    required String requesterName,
    required String reason,
    required String stationId,
  }) async {
    try {
      final notificationTriggersPath = EnvironmentConfig.getCollectionPath(
        'notificationTriggers',
        stationId,
      );

      await firestore.collection(notificationTriggersPath).add({
        'userId': userId,
        'type': 'replacement_acceptance_rejected',
        'title': 'Remplacement refusé',
        'body': reason,
        'data': {
          'requesterName': requesterName,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });

      debugPrint('📨 Rejection notification sent to user: $userId');
    } catch (e) {
      debugPrint('❌ Error sending rejection notification: $e');
    }
  }

  /// Vérifie si une demande est totalement couverte par une acceptation
  Future<bool> _checkIfRequestFullyCovered(
    ReplacementRequest request,
    ReplacementAcceptance acceptance,
    String stationId,
  ) async {
    // Si l'acceptation couvre toute la période demandée
    final coversStart = !acceptance.acceptedStartTime.isAfter(request.startTime);
    final coversEnd = !acceptance.acceptedEndTime.isBefore(request.endTime);

    if (coversStart && coversEnd) {
      return true;
    }

    // Vérifier s'il existe d'autres acceptations validées qui couvrent le reste
    // Pour simplifier, on retourne false pour l'instant
    // TODO: Implémenter la logique de vérification de couverture multiple
    return false;
  }

  /// Crée de nouvelles demandes pour les périodes non couvertes
  Future<void> _createRequestsForUncoveredPeriods(
    ReplacementRequest request,
    ReplacementAcceptance acceptance,
    String stationId,
  ) async {
    final periods = <Map<String, DateTime>>[];

    // Période avant l'acceptation
    if (acceptance.acceptedStartTime.isAfter(request.startTime)) {
      periods.add({
        'start': request.startTime,
        'end': acceptance.acceptedStartTime,
      });
    }

    // Période après l'acceptation
    if (acceptance.acceptedEndTime.isBefore(request.endTime)) {
      periods.add({
        'start': acceptance.acceptedEndTime,
        'end': request.endTime,
      });
    }

    // Créer les nouvelles demandes
    for (final period in periods) {
      debugPrint('  Creating request for uncovered period: ${period['start']} - ${period['end']}');
      await createReplacementRequest(
        requesterId: request.requesterId,
        planningId: request.planningId,
        startTime: period['start']!,
        endTime: period['end']!,
        station: request.station,
        team: request.team,
        requestType: request.requestType,
        requiredSkills: request.requiredSkills,
      );
    }
  }

  /// Envoie les notifications après validation d'une acceptation
  Future<void> _sendValidationConfirmationNotifications({
    required ReplacementRequest request,
    required ReplacementAcceptance acceptance,
    required String stationId,
  }) async {
    try {
      final requester = await _userRepository.getById(request.requesterId);
      final acceptor = await _userRepository.getById(acceptance.userId);

      if (requester == null || acceptor == null) return;

      final notificationTriggersPath = EnvironmentConfig.getCollectionPath(
        'notificationTriggers',
        stationId,
      );

      // Notification au demandeur
      await firestore.collection(notificationTriggersPath).add({
        'userId': requester.id,
        'type': 'replacement_found',
        'title': 'Remplaçant trouvé',
        'body': 'Votre demande de remplacement est complète.',
        'data': {
          'requestId': request.id,
          'replacerId': acceptor.id,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });

      // Notification à l'accepteur
      await firestore.collection(notificationTriggersPath).add({
        'userId': acceptor.id,
        'type': 'acceptance_validated',
        'title': 'Remplacement accepté',
        'body': 'Votre proposition de remplacement de l\'agent ${requester.firstName} ${requester.lastName} a été acceptée.',
        'data': {
          'requestId': request.id,
          'acceptanceId': acceptance.id,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });

      debugPrint('📨 Validation confirmation notifications sent');
    } catch (e) {
      debugPrint('❌ Error sending validation confirmation: $e');
    }
  }

  /// Envoie une notification aux chefs d'équipe pour validation d'acceptation
  Future<void> _notifyChiefsForValidation({
    required ReplacementAcceptance acceptance,
    required String stationId,
    required String chiefTeamId,
    required User requester,
    required User acceptor,
  }) async {
    try {
      // Récupérer tous les chefs de l'équipe concernée
      final allUsers = await _userRepository.getByStation(stationId);
      final chiefs = allUsers.where((u) =>
        (u.status == 'chief' || u.status == 'leader') &&
        u.team == chiefTeamId
      ).toList();

      if (chiefs.isEmpty) {
        debugPrint('⚠️ No chief found for team $chiefTeamId');
        return;
      }

      // Calculer les compétences manquantes pour le message
      final missingSkills = ReplacementAcceptance.getMissingSkills(
        requester.skills,
        acceptor.skills,
      );

      final missingSkillsText = missingSkills.isNotEmpty
        ? ' (manque: ${missingSkills.join(', ')})'
        : '';

      // Créer le trigger de notification pour chaque chef
      for (final chief in chiefs) {
        final notificationTriggersPath = EnvironmentConfig.getCollectionPath(
          'notificationTriggers',
          stationId,
        );

        await firestore.collection(notificationTriggersPath).add({
          'userId': chief.id,
          'type': 'replacement_validation_required',
          'title': 'Validation requise',
          'body': '${acceptor.firstName} ${acceptor.lastName} souhaite remplacer${missingSkillsText}',
          'data': {
            'acceptanceId': acceptance.id,
            'requestId': acceptance.requestId,
            'acceptorId': acceptor.id,
            'requesterId': requester.id,
          },
          'createdAt': FieldValue.serverTimestamp(),
          'processed': false,
        });

        debugPrint('📨 Notification envoyée au chef ${chief.firstName} ${chief.lastName}');
      }
    } catch (e) {
      debugPrint('❌ Error notifying chiefs for validation: $e');
      // Ne pas bloquer le processus si la notification échoue
    }
  }

  /// Envoie les notifications de confirmation
  /// - Au demandeur: "Remplaçant trouvé: [Nom]"
  /// - Au chef d'équipe: "[Nom] sera remplacé par [Nom] du DD/MM/YY HH:mm au DD/MM/YY HH:mm"
  Future<void> _sendConfirmationNotifications(
    ReplacementRequest request,
    String replacerId, {
    DateTime? actualStartTime,
    DateTime? actualEndTime,
  }) async {
    try {
      // Récupérer les infos du demandeur et du remplaçant
      final requester = await _userRepository.getById(request.requesterId);
      final replacer = await _userRepository.getById(replacerId);

      if (requester == null || replacer == null) {
        throw Exception('User not found');
      }

      // Trouver le chef de garde de l'astreinte (via l'équipe du planning)
      String? chiefId;

      final planningsPath = EnvironmentConfig.getCollectionPath('plannings', request.station);
      final planningDoc = await firestore
          .collection(planningsPath)
          .doc(request.planningId)
          .get();

      if (planningDoc.exists) {
        final planningData = planningDoc.data();
        final planningTeam = planningData?['team'] as String?;
        final planningStation = planningData?['station'] as String?;

        if (planningTeam != null && planningStation != null) {
          // Chercher le chef de garde : status 'chief' ou 'leader' dans cette équipe
          final allUsers = await _userRepository.getByStation(planningStation);
          final chief = allUsers.firstWhere(
            (u) =>
                u.team == planningTeam &&
                (u.status == 'chief' || u.status == 'leader') &&
                u.id != request.requesterId,
            orElse: () => allUsers.firstWhere(
              (u) => u.id == request.requesterId,
              orElse: () => requester,
            ),
          );
          chiefId = chief.id;
        }
      }

      // Si on n'a pas trouvé de chef, ne pas envoyer de notification
      chiefId ??= request.requesterId;

      // Utiliser les heures réelles ou celles de la demande
      final notifStartTime = actualStartTime ?? request.startTime;
      final notifEndTime = actualEndTime ?? request.endTime;

      // Créer les triggers de notification
      final notificationTriggersPath = _getNotificationTriggersPath(request.station);

      // 1. Notification au demandeur
      await firestore.collection(notificationTriggersPath).add({
        'type': 'replacement_found',
        'requestId': request.id,
        'targetUserIds': [request.requesterId],
        'replacerName': '${replacer.firstName} ${replacer.lastName}',
        'startTime': Timestamp.fromDate(notifStartTime),
        'endTime': Timestamp.fromDate(notifEndTime),
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });

      // 2. Notification au chef de garde (si différent du demandeur)
      if (chiefId != request.requesterId) {
        await firestore.collection(notificationTriggersPath).add({
          'type': 'replacement_assigned',
          'requestId': request.id,
          'targetUserIds': [chiefId],
          'replacedName': '${requester.firstName} ${requester.lastName}',
          'replacerName': '${replacer.firstName} ${replacer.lastName}',
          'startTime': Timestamp.fromDate(notifStartTime),
          'endTime': Timestamp.fromDate(notifEndTime),
          'createdAt': FieldValue.serverTimestamp(),
          'processed': false,
        });
      }

      debugPrint('✅ Confirmation notifications triggered');
    } catch (e) {
      debugPrint('❌ Error sending confirmation notifications: $e');
    }
  }

  /// Annule une demande de remplacement
  /// Le stationId DOIT être fourni pour éviter les erreurs avec collectionGroup
  Future<void> cancelReplacementRequest(String requestId, {required String stationId}) async {
    try {
      debugPrint('🗑️ Cancelling replacement request: $requestId (station: $stationId)');

      final requestsPath = _getReplacementRequestsPath(stationId);
      await firestore.collection(requestsPath).doc(requestId).update({
        'status': ReplacementRequestStatus.cancelled.toString().split('.').last,
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Replacement request cancelled: $requestId');
    } catch (e) {
      debugPrint('❌ Error cancelling replacement request: $e');
      rethrow;
    }
  }

  /// DEV UNIQUEMENT : Simule le passage à la vague suivante
  /// En production, c'est géré par les Cloud Functions
  /// Si une vague est vide, continue automatiquement aux vagues suivantes jusqu'à la vague 5
  Future<void> simulateNextWave(String requestId, String stationId) async {
    if (!EnvironmentConfig.isDev) {
      debugPrint('⚠️ simulateNextWave should only be called in DEV mode');
      return;
    }

    try {
      debugPrint('🔄 [DEV] Simulating next wave for request $requestId');

      // 1. Récupérer la demande
      final requestsPath = _getReplacementRequestsPath(stationId);
      final requestDoc = await firestore.collection(requestsPath).doc(requestId).get();

      if (!requestDoc.exists) {
        debugPrint('❌ Request not found: $requestId');
        return;
      }

      final request = ReplacementRequest.fromJson(requestDoc.data()!);

      if (request.status != ReplacementRequestStatus.pending) {
        debugPrint('⚠️ Request is not pending, skipping wave simulation');
        return;
      }

      // 2. Récupérer le demandeur et la station
      final requester = await _userRepository.getById(request.requesterId);
      if (requester == null) {
        debugPrint('❌ Requester not found: ${request.requesterId}');
        return;
      }

      final station = await _stationRepository.getById(request.station);
      if (station == null) {
        debugPrint('❌ Station not found: ${request.station}');
        return;
      }

      // 3. Récupérer tous les utilisateurs et le planning
      final allUsers = await _userRepository.getByStation(request.station);
      final planningsPath = EnvironmentConfig.getCollectionPath('plannings', request.station);
      final planningDoc = await firestore.collection(planningsPath).doc(request.planningId).get();

      if (!planningDoc.exists) {
        debugPrint('❌ Planning not found: ${request.planningId}');
        return;
      }

      final planningData = planningDoc.data()!;
      final agentsInPlanning = List<String>.from(planningData['agentsId'] ?? []);

      // 4. Calculer toutes les vagues et trouver la prochaine non vide
      final currentWave = request.currentWave;
      int nextWave = currentWave + 1;
      List<String> nextWaveUserIds = [];

      if (station.replacementMode == ReplacementMode.similarity) {
        // Mode similarité : calculer la vague pour chaque utilisateur
        final waveService = WaveCalculationService();

        // Récupérer l'équipe du planning
        final planningTeam = planningData['team'] as String? ?? '';

        // Calculer les poids de rareté des compétences
        final skillRarityWeights = <String, int>{};
        for (final user in allUsers) {
          for (final skill in user.skills) {
            skillRarityWeights[skill] = (skillRarityWeights[skill] ?? 0) + 1;
          }
        }

        // Calculer la vague pour chaque utilisateur et grouper par vague
        final waveDistribution = <int, List<String>>{};
        for (final user in allUsers) {
          if (user.id == request.requesterId) continue;
          if (user.station != request.station) continue;

          final userWave = waveService.calculateWave(
            requester: requester,
            candidate: user,
            planningTeam: planningTeam,
            agentsInPlanning: agentsInPlanning,
            skillRarityWeights: skillRarityWeights,
            stationSkillWeights: station.skillWeights,
          );

          // Grouper par vague
          waveDistribution[userWave] = [...(waveDistribution[userWave] ?? []), user.id];
        }

        // Afficher la distribution des vagues pour debug
        debugPrint('  → Wave distribution:');
        waveDistribution.forEach((wave, users) {
          debugPrint('     Wave $wave: ${users.length} users');
        });

        // Chercher la prochaine vague non vide jusqu'à la vague 5
        while (nextWave <= 5 && nextWaveUserIds.isEmpty) {
          debugPrint('📨 Processing wave $nextWave (previous: $currentWave)');

          nextWaveUserIds = waveDistribution[nextWave] ?? [];

          if (nextWaveUserIds.isEmpty) {
            debugPrint('  → Wave $nextWave is empty, trying next wave...');
            nextWave++;
          } else {
            debugPrint('  → Found ${nextWaveUserIds.length} users in wave $nextWave');
          }
        }

        // Si on a atteint la vague 5 et qu'elle est vide, on l'utilise quand même
        if (nextWave > 5) {
          nextWave = 5;
          nextWaveUserIds = waveDistribution[5] ?? [];
          debugPrint('  → Reached wave 5 (final wave) with ${nextWaveUserIds.length} users');
        }
      } else {
        // Mode position : pas de vagues multiples
        debugPrint('  → Position mode does not support multiple waves');
      }

      // 5. Mettre à jour la demande avec la nouvelle vague
      final updatedNotifiedUsers = List<String>.from(request.notifiedUserIds);
      updatedNotifiedUsers.addAll(nextWaveUserIds);

      await firestore.collection(requestsPath).doc(requestId).update({
        'currentWave': nextWave,
        'notifiedUserIds': updatedNotifiedUsers,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ [DEV] Wave $nextWave processed:');
      debugPrint('  → ${nextWaveUserIds.length} new users notified');
      debugPrint('  → Total notified: ${updatedNotifiedUsers.length}');

    } catch (e, stackTrace) {
      debugPrint('❌ Error simulating next wave: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Récupère les demandes de remplacement en attente pour une station
  Stream<List<ReplacementRequest>> getPendingRequestsForStation(String stationId) {
    final requestsPath = _getReplacementRequestsPath(stationId);
    return firestore
        .collection(requestsPath)
        .where(
          'status',
          isEqualTo: ReplacementRequestStatus.pending
              .toString()
              .split('.')
              .last,
        )
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ReplacementRequest.fromJson(doc.data()))
              .toList(),
        );
  }
}
