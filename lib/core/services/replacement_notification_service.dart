import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';
import 'package:nexshift_app/core/data/models/position_model.dart';
import 'package:nexshift_app/core/data/models/availability_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/repositories/availability_repository.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';
import 'package:nexshift_app/core/repositories/position_repository.dart';

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

  /// Constructeur avec injection de dépendances (pour les tests)
  ReplacementNotificationService({
    FirebaseFirestore? firestore,
    UserRepository? userRepository,
    AvailabilityRepository? availabilityRepository,
    SubshiftRepository? subshiftRepository,
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
              : SubshiftRepository());

  /// Crée une demande de remplacement et envoie les notifications
  /// Retourne l'ID de la demande créée
  ///
  /// [excludedUserIds] : Liste des IDs utilisateurs à exclure des notifications
  /// (utilisé pour les remplacements partiels : exclure ceux déjà notifiés)
  /// [requestType] : Type de demande (replacement ou availability)
  /// [requiredSkills] : Compétences requises (pour demandes de disponibilité)
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
  }) async {
    try {
      debugPrint(
        '📤 Creating ${requestType == RequestType.availability ? "availability" : "replacement"} request...',
      );
      debugPrint('  Requester: $requesterId');
      debugPrint('  Period: $startTime - $endTime');
      if (requiredSkills != null && requiredSkills.isNotEmpty) {
        debugPrint('  Required skills: ${requiredSkills.join(", ")}');
      }

      // Créer la demande dans Firestore
      final requestRef = firestore.collection('replacementRequests').doc();
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
      await _triggerNotifications(request, excludedUserIds: excludedUserIds);

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
  }) async {
    try {
      // Récupérer les informations du demandeur
      final requester = await _userRepository.getById(request.requesterId);
      if (requester == null) {
        throw Exception('Requester not found: ${request.requesterId}');
      }

      // Récupérer tous les utilisateurs pour déterminer les vagues
      final allUsers = await _userRepository.getAll();

      // Récupérer le planning pour connaître les agents en astreinte
      final planningDoc = await firestore
          .collection('plannings')
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
      final stationDoc = await firestore
          .collection('stations')
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

      // Choisir la logique selon le mode de remplacement
      if (replacementMode == ReplacementMode.position) {
        await _triggerPositionBasedNotifications(
          request,
          requester,
          allUsers,
          agentsInPlanning,
          planningTeam,
          excludedUserIds,
        );
        return;
      }

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
        await firestore
            .collection('replacementRequests')
            .doc(request.id)
            .update({
              'currentWave': 1,
              'notifiedUserIds': [],
              // NE PAS mettre lastWaveSentAt, pour forcer le traitement immédiat
            });

        // Créer un document trigger spécial pour traiter la vague suivante immédiatement
        await firestore.collection('waveSkipTriggers').add({
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
      await firestore.collection('replacementRequests').doc(request.id).update({
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

      await firestore.collection('notificationTriggers').add(notificationData);

      debugPrint(
        '✅ Wave 1 notification trigger created for ${targetUserIds.length} users',
      );
    } catch (e) {
      debugPrint('❌ Error triggering notifications: $e');
      // Ne pas rethrow pour ne pas bloquer la création de la demande
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
      final stationDoc = await firestore
          .collection('stations')
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
          station.allowUnderQualifiedReplacement,
          1, // currentWave = 1 (on skip la vague 1)
        );
        return;
      }

      final targetUserIds = samePositionUsers.map((u) => u.id).toList();

      // Mettre à jour la demande
      await firestore.collection('replacementRequests').doc(request.id).update({
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

      await firestore.collection('notificationTriggers').add(notificationData);

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

    if (teamUsers.isEmpty) {
      debugPrint('⚠️ No team members available');
      await firestore.collection('replacementRequests').doc(request.id).update({
        'currentWave': 1,
        'notifiedUserIds': [],
      });
      return;
    }

    final targetUserIds = teamUsers.map((u) => u.id).toList();

    await firestore.collection('replacementRequests').doc(request.id).update({
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

    await firestore.collection('notificationTriggers').add(notificationData);
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

    if (targetUsers.isEmpty) {
      debugPrint('⚠️ Wave $nextWave ($waveDescription): No users found, search complete');
      await firestore.collection('replacementRequests').doc(request.id).update({
        'currentWave': nextWave,
        'notifiedUserIds': [],
      });
      return;
    }

    debugPrint('📨 Wave $nextWave ($waveDescription): Found ${targetUsers.length} users');

    final targetUserIds = targetUsers.map((u) => u.id).toList();

    await firestore.collection('replacementRequests').doc(request.id).update({
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

    await firestore.collection('notificationTriggers').add(notificationData);
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
      final subshiftsSnapshot = await firestore
          .collection('subshifts')
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

      if (availableUsers.isEmpty) {
        debugPrint('⚠️ No available users found');
        await firestore
            .collection('replacementRequests')
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
      await firestore.collection('replacementRequests').doc(request.id).update({
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

      await firestore.collection('notificationTriggers').add(notificationData);

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

  /// Accepte une demande de remplacement (totale ou partielle)
  /// Crée le subshift et envoie les notifications de confirmation
  /// Si acceptedStart/acceptedEnd sont fournis, crée une nouvelle demande pour le temps restant
  Future<void> acceptReplacementRequest({
    required String requestId,
    required String replacerId,
    DateTime? acceptedStartTime,
    DateTime? acceptedEndTime,
  }) async {
    try {
      debugPrint('✅ Accepting replacement request: $requestId');
      debugPrint('  Replacer: $replacerId');

      // Variables pour stocker les données de la requête
      late ReplacementRequest request;
      late DateTime actualStartTime;
      late DateTime actualEndTime;

      // TRANSACTION ATOMIQUE pour éviter les race conditions
      await firestore.runTransaction((transaction) async {
        final requestRef = firestore
            .collection('replacementRequests')
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

        // Mise à jour atomique du statut
        transaction.update(requestRef, {
          'status': ReplacementRequestStatus.accepted.toString().split('.').last,
          'replacerId': replacerId,
          'acceptedAt': FieldValue.serverTimestamp(),
          'acceptedStartTime': Timestamp.fromDate(actualStartTime),
          'acceptedEndTime': Timestamp.fromDate(actualEndTime),
        });
      });

      debugPrint('  Transaction completed - request status updated atomically');

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
        await _subshiftRepository.save(subshift);
        debugPrint('✅ Subshift created: ${subshift.id}');
      }

      // Vérifier si c'est un remplacement partiel
      final isPartialReplacement =
          actualStartTime.isAfter(request.startTime) ||
          actualEndTime.isBefore(request.endTime);

      if (isPartialReplacement) {
        debugPrint('⚠️ Partial replacement detected');

        // Calculer les utilisateurs à exclure des nouvelles demandes
        // = tous les utilisateurs notifiés SAUF ceux de la vague courante
        // (car ceux de la vague courante n'ont peut-être pas eu le temps de répondre)
        final notifiedUserIds = request.notifiedUserIds;
        final currentWave = request.currentWave;

        // Récupérer tous les utilisateurs pour déterminer qui était dans quelle vague
        final allUsers = await _userRepository.getAll();
        final planningDoc = await firestore
            .collection('plannings')
            .doc(request.planningId)
            .get();

        List<String> excludedUserIds = [];

        if (planningDoc.exists) {
          final planningData = planningDoc.data();
          final agentsInPlanning = List<String>.from(
            planningData?['agentsId'] ?? [],
          );
          final planningTeam = planningData?['team'] as String?;

          // Pour chaque utilisateur notifié, vérifier s'il était dans une vague < currentWave
          for (final userId in notifiedUserIds) {
            final user = allUsers.firstWhere(
              (u) => u.id == userId,
              orElse: () => allUsers.first,
            );

            // Vague 1 = même équipe (hors astreinte)
            final isWave1 =
                user.team == planningTeam &&
                !agentsInPlanning.contains(user.id);

            // Si l'utilisateur était dans une vague < currentWave, l'exclure
            if (isWave1 && currentWave > 1) {
              excludedUserIds.add(userId);
            } else if (!isWave1 && currentWave > 2) {
              // Pour les vagues 2+, on pourrait faire un calcul de similarité
              // mais pour simplifier, on exclut tous ceux notifiés avant la vague courante
              excludedUserIds.add(userId);
            }
          }
        }

        debugPrint(
          '  Excluding ${excludedUserIds.length} users from new requests (already notified in previous waves)',
        );

        // Créer de nouvelles demandes pour les périodes non couvertes
        if (actualStartTime.isAfter(request.startTime)) {
          // Période avant le remplacement accepté
          debugPrint(
            '  Creating request for period before: ${request.startTime} - $actualStartTime',
          );
          await createReplacementRequest(
            requesterId: request.requesterId,
            planningId: request.planningId,
            startTime: request.startTime,
            endTime: actualStartTime,
            station: request.station,
            team: request.team,
            excludedUserIds: excludedUserIds,
            requestType: request.requestType,
            requiredSkills: request.requiredSkills,
          );
        }

        if (actualEndTime.isBefore(request.endTime)) {
          // Période après le remplacement accepté
          debugPrint(
            '  Creating request for period after: $actualEndTime - ${request.endTime}',
          );
          await createReplacementRequest(
            requesterId: request.requesterId,
            planningId: request.planningId,
            startTime: actualEndTime,
            endTime: request.endTime,
            station: request.station,
            team: request.team,
            excludedUserIds: excludedUserIds,
            requestType: request.requestType,
            requiredSkills: request.requiredSkills,
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

      final planningDoc = await firestore
          .collection('plannings')
          .doc(request.planningId)
          .get();

      if (planningDoc.exists) {
        final planningData = planningDoc.data();
        final planningTeam = planningData?['team'] as String?;
        final planningStation = planningData?['station'] as String?;

        if (planningTeam != null && planningStation != null) {
          // Chercher le chef de garde : status 'chief' ou 'leader' dans cette équipe
          final allUsers = await _userRepository.getAll();
          final chief = allUsers.firstWhere(
            (u) =>
                u.station == planningStation &&
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
      // 1. Notification au demandeur
      await firestore.collection('notificationTriggers').add({
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
        await firestore.collection('notificationTriggers').add({
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
  Future<void> cancelReplacementRequest(String requestId) async {
    try {
      await firestore.collection('replacementRequests').doc(requestId).update({
        'status': ReplacementRequestStatus.cancelled.toString().split('.').last,
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Replacement request cancelled: $requestId');
    } catch (e) {
      debugPrint('❌ Error cancelling replacement request: $e');
      rethrow;
    }
  }

  /// Récupère les demandes de remplacement en attente pour un utilisateur
  Stream<List<ReplacementRequest>> getPendingRequestsForUser(String userId) {
    return firestore
        .collection('replacementRequests')
        .where(
          'station',
          isEqualTo: userId,
        ) // TODO: Filtrer par station de l'utilisateur
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
