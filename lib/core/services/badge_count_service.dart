import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';

/// Service centralisé pour le calcul des compteurs de badges.
///
/// Ce service est un singleton qui écoute les streams Firestore une seule fois
/// et expose des ValueNotifier pour chaque compteur, garantissant une cohérence
/// entre tous les niveaux de l'UI (sous-onglets, onglets principaux, drawer).
class BadgeCountService {
  static final BadgeCountService _instance = BadgeCountService._internal();
  factory BadgeCountService() => _instance;
  BadgeCountService._internal();

  // === COMPTEURS REMPLACEMENTS ===
  /// Nombre de demandes de remplacement en attente nécessitant une action
  final ValueNotifier<int> replacementPendingCount = ValueNotifier(0);

  /// Nombre de mes demandes de remplacement en cours
  final ValueNotifier<int> replacementMyRequestsCount = ValueNotifier(0);

  /// Nombre de demandes de remplacement à valider (pour les chefs)
  final ValueNotifier<int> replacementToValidateCount = ValueNotifier(0);

  // === COMPTEURS ÉVÉNEMENTS D'ÉQUIPE ===
  /// Nombre d'événements en attente de réponse (invité, pas encore accepté/décliné)
  final ValueNotifier<int> teamEventPendingCount = ValueNotifier(0);

  /// True si au moins un événement attend une réponse
  final ValueNotifier<bool> hasTeamEventPending = ValueNotifier(false);

  // === COMPTEURS RECHERCHES D'AGENT (AgentQuery) ===
  /// Nombre de recherches en attente nécessitant une action (notifié, pas encore répondu)
  final ValueNotifier<int> agentQueryPendingCount = ValueNotifier(0);

  /// Nombre de mes recherches d'agent en cours (créées par moi, still pending)
  final ValueNotifier<int> agentQueryMyRequestsCount = ValueNotifier(0);

  /// True si au moins une recherche d'agent nécessite une action
  final ValueNotifier<bool> hasAgentQueryPending = ValueNotifier(false);

  // === COMPTEURS ÉCHANGES ===
  /// Nombre de demandes d'échange en attente nécessitant une action
  final ValueNotifier<int> exchangePendingCount = ValueNotifier(0);

  /// Nombre de mes demandes d'échange en cours
  final ValueNotifier<int> exchangeMyRequestsCount = ValueNotifier(0);

  /// Nombre de mes demandes d'échange avec propositions nécessitant sélection (badge violet)
  final ValueNotifier<int> exchangeNeedingSelectionCount = ValueNotifier(0);

  /// Nombre de demandes d'échange à valider (pour les chefs)
  final ValueNotifier<int> exchangeToValidateCount = ValueNotifier(0);

  // === PASTILLES AGRÉGÉES (pour onglets et drawer) ===
  /// True si au moins une demande de remplacement nécessite une action
  final ValueNotifier<bool> hasReplacementPending = ValueNotifier(false);

  /// True si au moins une demande de remplacement nécessite validation chef
  final ValueNotifier<bool> hasReplacementValidation = ValueNotifier(false);

  /// True si au moins une demande d'échange nécessite une action
  final ValueNotifier<bool> hasExchangePending = ValueNotifier(false);

  /// True si au moins une de mes demandes d'échange a des propositions à sélectionner
  final ValueNotifier<bool> hasExchangeNeedingSelection = ValueNotifier(false);

  /// True si au moins une demande d'échange nécessite validation chef
  final ValueNotifier<bool> hasExchangeValidation = ValueNotifier(false);

  // === SUBSCRIPTIONS ===
  StreamSubscription? _replacementSubscription;
  StreamSubscription? _manualProposalsSubscription;
  StreamSubscription? _agentQuerySubscription;
  StreamSubscription? _teamEventSubscription;
  StreamSubscription? _exchangeRequestsSubscription;
  StreamSubscription? _exchangeProposalsSubscription;
  StreamSubscription? _myExchangeRequestsSubscription;
  StreamSubscription? _validationSubscription;

  // === ÉTAT INTERNE ===
  String? _currentUserId;
  String? _currentStationId;
  User? _currentUser;
  bool _isInitialized = false;

  /// Initialise le service avec les informations de l'utilisateur courant.
  ///
  /// Doit être appelé après la connexion de l'utilisateur.
  void initialize(String userId, String stationId, User currentUser) {
    // Éviter les réinitialisations inutiles
    if (_isInitialized &&
        _currentUserId == userId &&
        _currentStationId == stationId) {
      debugPrint('🔔 [BadgeCountService] Already initialized for user $userId');
      return;
    }

    debugPrint('🔔 [BadgeCountService] Initializing for user $userId, station $stationId');

    // Nettoyer les anciennes subscriptions
    dispose();

    _currentUserId = userId;
    _currentStationId = stationId;
    _currentUser = currentUser;
    _isInitialized = true;

    // Démarrer l'écoute des streams
    _subscribeToReplacements();
    _subscribeToManualProposals();
    _subscribeToAgentQueries();
    _subscribeToTeamEvents();
    _subscribeToExchanges();
    _subscribeToValidations();
  }

  /// Réinitialise le service avec un nouvel utilisateur.
  void reinitialize(String userId, String stationId, User currentUser) {
    dispose();
    _isInitialized = false;
    initialize(userId, stationId, currentUser);
  }

  /// Retourne le chemin Firestore pour les demandes de remplacement automatiques.
  String _getReplacementRequestsPath() {
    return EnvironmentConfig.getCollectionPath('replacements/automatic/replacementRequests', _currentStationId);
  }

  /// Retourne le chemin Firestore pour les propositions de remplacement manuelles.
  String _getManualProposalsPath() {
    return EnvironmentConfig.getCollectionPath('replacements/manual/proposals', _currentStationId);
  }

  /// Retourne le chemin Firestore pour les demandes d'échange.
  String _getExchangeRequestsPath() {
    return EnvironmentConfig.getCollectionPath('replacements/exchange/shiftExchangeRequests', _currentStationId);
  }

  /// Retourne le chemin Firestore pour les propositions d'échange.
  String _getExchangeProposalsPath() {
    return EnvironmentConfig.getCollectionPath('replacements/exchange/shiftExchangeProposals', _currentStationId);
  }

  /// Retourne le chemin Firestore pour les événements d'équipe.
  String _getTeamEventsPath() {
    return EnvironmentConfig.getCollectionPath('teamEvents', _currentStationId);
  }

  /// Retourne le chemin Firestore pour les recherches automatiques d'agent.
  String _getAgentQueriesPath() {
    return EnvironmentConfig.getCollectionPath('replacements/queries/agentQueries', _currentStationId);
  }

  /// Retourne le chemin Firestore pour les acceptations de remplacement.
  String _getReplacementAcceptancesPath() {
    return EnvironmentConfig.getCollectionPath('replacements/automatic/replacementAcceptances', _currentStationId);
  }

  // ============================================================
  // REMPLACEMENTS
  // ============================================================

  void _subscribeToReplacements() {
    final path = _getReplacementRequestsPath();
    debugPrint('🔔 [BadgeCountService] Subscribing to replacements at: $path');

    _replacementSubscription = FirebaseFirestore.instance
        .collection(path)
        .where('status', isEqualTo: 'pending')
        .where('station', isEqualTo: _currentStationId)
        .snapshots()
        .listen(
          (snapshot) => _updateReplacementCounts(snapshot),
          onError: (error) => debugPrint('🔔 [BadgeCountService] Replacement stream error: $error'),
        );
  }

  void _updateReplacementCounts(QuerySnapshot snapshot) {
    if (_currentUserId == null || _currentUser == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int pending = 0;
    int myRequests = 0;
    int toValidate = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;

      // Parsing des champs
      final requesterId = data['requesterId'] as String?;
      final startTime = (data['startTime'] as Timestamp?)?.toDate();
      final status = data['status'] as String?;
      final team = data['team'] as String?;
      final notifiedUserIds = List<String>.from(data['notifiedUserIds'] ?? []);
      final declinedByUserIds = List<String>.from(data['declinedByUserIds'] ?? []);
      final pendingValidationUserIds = List<String>.from(data['pendingValidationUserIds'] ?? []);

      if (startTime == null) continue;

      // Filtre date : startTime >= aujourd'hui
      final startDate = DateTime(startTime.year, startTime.month, startTime.day);
      final isFuture = startDate.isAfter(today) || startDate.isAtSameMomentAs(today);
      if (!isFuture) continue;

      // === MES DEMANDES ===
      if (requesterId == _currentUserId && status == 'pending') {
        myRequests++;
      }

      // === EN ATTENTE (action requise) ===
      // Conditions : pas ma demande + notifié + pas refusé + pas accepté en attente validation
      if (requesterId != _currentUserId &&
          notifiedUserIds.contains(_currentUserId) &&
          !declinedByUserIds.contains(_currentUserId) &&
          !pendingValidationUserIds.contains(_currentUserId)) {
        pending++;
      }

      // === A VALIDER ===
      // Visible par : initiateur, remplaçant en attente, chefs de l'équipe
      // Badge bleu : seulement si chef de l'équipe concernée
      if (pendingValidationUserIds.isNotEmpty) {
        final isChief = (_currentUser!.status == 'chief' || _currentUser!.status == 'leader') &&
                        team == _currentUser!.team;
        if (isChief) {
          toValidate++;
        }
      }
    }

    // Stocker les valeurs automatiques
    _automaticPendingCount = pending;
    _automaticMyRequestsCount = myRequests;
    _automaticToValidateCount = toValidate;

    // Recalculer les totaux combinés (automatique + manuel)
    _updateCombinedReplacementCounts();

    debugPrint('🔔 [BadgeCountService] Automatic replacement counts: pending=$pending, myRequests=$myRequests, toValidate=$toValidate');
  }

  // ============================================================
  // PROPOSITIONS MANUELLES
  // ============================================================

  // Compteurs pour les propositions manuelles (additionnés aux compteurs principaux)
  int _manualPendingCount = 0;
  int _manualMyRequestsCount = 0;
  int _manualToValidateCount = 0;

  void _subscribeToManualProposals() {
    final path = _getManualProposalsPath();
    debugPrint('🔔 [BadgeCountService] Subscribing to manual proposals at: $path');

    _manualProposalsSubscription = FirebaseFirestore.instance
        .collection(path)
        .snapshots()
        .listen(
          (snapshot) => _updateManualProposalCounts(snapshot),
          onError: (error) => debugPrint('🔔 [BadgeCountService] Manual proposals stream error: $error'),
        );
  }

  void _updateManualProposalCounts(QuerySnapshot snapshot) {
    if (_currentUserId == null || _currentUser == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int pending = 0;
    int myRequests = 0;
    int toValidate = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;

      // Parsing des champs
      final replacedId = data['replacedId'] as String?;
      final replacerId = data['replacerId'] as String?;
      final status = data['status'] as String?;
      final startTime = (data['startTime'] as Timestamp?)?.toDate();

      if (startTime == null) continue;

      // Filtre date : startTime >= aujourd'hui
      final startDate = DateTime(startTime.year, startTime.month, startTime.day);
      final isFuture = startDate.isAfter(today) || startDate.isAtSameMomentAs(today);
      if (!isFuture) continue;

      // Exclure les demandes non-pending (accepted, declined, cancelled)
      if (status != 'pending') continue;

      // === MES DEMANDES (je suis le remplacé) ===
      if (replacedId == _currentUserId) {
        myRequests++;
      }

      // === EN ATTENTE (je suis le remplaçant désigné) ===
      if (replacerId == _currentUserId) {
        pending++;
        // Note: Les demandes manuelles n'ont PAS de validation chef,
        // donc on ne les compte PAS dans toValidate
      }
    }

    _manualPendingCount = pending;
    _manualMyRequestsCount = myRequests;
    _manualToValidateCount = toValidate;

    // Recalculer les totaux combinés
    _updateCombinedReplacementCounts();

    debugPrint('🔔 [BadgeCountService] Manual proposal counts: pending=$pending, myRequests=$myRequests, toValidate=$toValidate');
  }

  /// Met à jour les compteurs combinés (automatique + manuel)
  void _updateCombinedReplacementCounts() {
    // Les compteurs automatiques sont déjà dans les ValueNotifier, on ajoute les manuels
    // Note: On ne peut pas additionner directement car _updateReplacementCounts écrase les valeurs
    // On doit stocker les valeurs automatiques séparément

    final totalPending = _automaticPendingCount + _manualPendingCount;
    final totalMyRequests = _automaticMyRequestsCount + _manualMyRequestsCount;
    final totalToValidate = _automaticToValidateCount + _manualToValidateCount;

    replacementPendingCount.value = totalPending;
    replacementMyRequestsCount.value = totalMyRequests;
    replacementToValidateCount.value = totalToValidate;

    hasReplacementPending.value = totalPending > 0;
    hasReplacementValidation.value = totalToValidate > 0;

    debugPrint('🔔 [BadgeCountService] Combined replacement counts: pending=$totalPending, myRequests=$totalMyRequests, toValidate=$totalToValidate');
  }

  // Compteurs automatiques stockés séparément
  int _automaticPendingCount = 0;
  int _automaticMyRequestsCount = 0;
  int _automaticToValidateCount = 0;

  // ============================================================
  // RECHERCHES D'AGENT (AgentQuery)
  // ============================================================

  void _subscribeToAgentQueries() {
    final path = _getAgentQueriesPath();
    debugPrint('🔔 [BadgeCountService] Subscribing to agentQueries at: $path');

    _agentQuerySubscription = FirebaseFirestore.instance
        .collection(path)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(
          (snapshot) => _updateAgentQueryCounts(snapshot),
          onError: (error) => debugPrint('🔔 [BadgeCountService] AgentQuery stream error: $error'),
        );
  }

  void _updateAgentQueryCounts(QuerySnapshot snapshot) {
    if (_currentUserId == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int pending = 0;
    int myRequests = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;

      final createdById = data['createdById'] as String?;
      final startTime = (data['startTime'] as Timestamp?)?.toDate();
      final notifiedUserIds = List<String>.from(data['notifiedUserIds'] ?? []);
      final declinedByUserIds = List<String>.from(data['declinedByUserIds'] ?? []);

      if (startTime == null) continue;

      // Filtre date : startTime >= aujourd'hui
      final startDate = DateTime(startTime.year, startTime.month, startTime.day);
      final isFuture = startDate.isAfter(today) || startDate.isAtSameMomentAs(today);
      if (!isFuture) continue;

      // === MES DEMANDES (créées par moi) ===
      if (createdById == _currentUserId) {
        myRequests++;
      }

      // === EN ATTENTE (notifié, pas encore refusé) ===
      if (createdById != _currentUserId &&
          notifiedUserIds.contains(_currentUserId) &&
          !declinedByUserIds.contains(_currentUserId)) {
        pending++;
      }
    }

    agentQueryPendingCount.value = pending;
    agentQueryMyRequestsCount.value = myRequests;
    hasAgentQueryPending.value = pending > 0;

    debugPrint('🔔 [BadgeCountService] AgentQuery counts: pending=$pending, myRequests=$myRequests');
  }

  // ============================================================
  // ÉVÉNEMENTS D'ÉQUIPE
  // ============================================================

  void _subscribeToTeamEvents() {
    final path = _getTeamEventsPath();
    debugPrint('🔔 [BadgeCountService] Subscribing to teamEvents at: $path');

    _teamEventSubscription = FirebaseFirestore.instance
        .collection(path)
        .where('status', isEqualTo: 'upcoming')
        .snapshots()
        .listen(
          _updateTeamEventCounts,
          onError: (e) => debugPrint('🔔 [BadgeCountService] TeamEvent stream error: $e'),
        );
  }

  void _updateTeamEventCounts(QuerySnapshot snapshot) {
    if (_currentUserId == null) return;
    final now = DateTime.now();
    int pending = 0;

    for (final doc in snapshot.docs) {
      try {
        final data = doc.data() as Map<String, dynamic>;
        final endRaw = data['endTime'];
        final endTime = endRaw is Timestamp ? endRaw.toDate() : null;
        if (endTime == null || endTime.isBefore(now)) continue;

        final invitedUserIds = List<String>.from(data['invitedUserIds'] ?? []);
        final acceptedUserIds = List<String>.from(data['acceptedUserIds'] ?? []);
        final declinedUserIds = List<String>.from(data['declinedUserIds'] ?? []);
        final createdById = data['createdById'] as String?;

        if (createdById != _currentUserId &&
            invitedUserIds.contains(_currentUserId) &&
            !acceptedUserIds.contains(_currentUserId) &&
            !declinedUserIds.contains(_currentUserId)) {
          pending++;
        }
      } catch (e) {
        debugPrint('⚠️ [BadgeCountService] TeamEvent parse error on ${doc.id}: $e');
      }
    }

    teamEventPendingCount.value = pending;
    hasTeamEventPending.value = pending > 0;
    debugPrint('🔔 [BadgeCountService] TeamEvent counts: pending=$pending');
  }

  // ============================================================
  // ÉCHANGES
  // ============================================================

  void _subscribeToExchanges() {
    final requestsPath = _getExchangeRequestsPath();
    final proposalsPath = _getExchangeProposalsPath();

    debugPrint('🔔 [BadgeCountService] Subscribing to exchanges at: $requestsPath');

    // Stream pour les demandes d'échange "open" (En attente)
    _exchangeRequestsSubscription = FirebaseFirestore.instance
        .collection(requestsPath)
        .where('status', isEqualTo: 'open')
        .snapshots()
        .listen(
          (snapshot) => _updateExchangePendingCount(snapshot),
          onError: (error) => debugPrint('🔔 [BadgeCountService] Exchange requests stream error: $error'),
        );

    // Stream pour mes demandes d'échange (initiator = currentUser)
    _myExchangeRequestsSubscription = FirebaseFirestore.instance
        .collection(requestsPath)
        .where('initiatorId', isEqualTo: _currentUserId)
        .snapshots()
        .listen(
          (snapshot) => _updateMyExchangeRequestsCount(snapshot),
          onError: (error) => debugPrint('🔔 [BadgeCountService] My exchange requests stream error: $error'),
        );

    // Stream pour les propositions de l'utilisateur (pour exclure des demandes "En attente")
    _exchangeProposalsSubscription = FirebaseFirestore.instance
        .collection(proposalsPath)
        .where('proposerId', isEqualTo: _currentUserId)
        .snapshots()
        .listen(
          (snapshot) => _userProposalIds = snapshot.docs.map((d) {
            final data = d.data();
            return data['requestId'] as String?;
          }).whereType<String>().toSet(),
          onError: (error) => debugPrint('🔔 [BadgeCountService] User proposals stream error: $error'),
        );
  }

  Set<String> _userProposalIds = {};

  void _updateExchangePendingCount(QuerySnapshot snapshot) {
    if (_currentUserId == null || _currentUser == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int pending = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;

      final initiatorId = data['initiatorId'] as String?;
      final startTime = (data['initiatorStartTime'] as Timestamp?)?.toDate();
      final refusedByUserIds = List<String>.from(data['refusedByUserIds'] ?? []);
      final requiredKeySkills = List<String>.from(data['requiredKeySkills'] ?? []);
      final initiatorTeam = data['initiatorTeam'] as String?;

      if (startTime == null) continue;

      // Filtre date : startTime >= aujourd'hui
      final startDate = DateTime(startTime.year, startTime.month, startTime.day);
      final isFuture = startDate.isAfter(today) || startDate.isAtSameMomentAs(today);
      if (!isFuture) continue;

      // Exclure mes propres demandes
      if (initiatorId == _currentUserId) continue;

      // Exclure si j'ai déjà refusé
      if (refusedByUserIds.contains(_currentUserId)) continue;

      // Exclure si j'ai déjà proposé
      if (_userProposalIds.contains(doc.id)) continue;

      // Exclure les demandes de la même équipe que l'utilisateur courant
      // (Les échanges se font entre équipes différentes)
      if (initiatorTeam != null && initiatorTeam == _currentUser!.team) {
        debugPrint('🔔 [BadgeCountService] Exchange ${doc.id} excluded: same team ($initiatorTeam)');
        continue;
      }

      // Si initiatorTeam n'est pas défini, on ne peut pas filtrer par équipe
      // On exclut pour éviter les faux positifs (la demande sera filtrée correctement côté UI)
      if (initiatorTeam == null) {
        debugPrint('🔔 [BadgeCountService] Exchange ${doc.id} excluded: initiatorTeam is null');
        continue;
      }

      // Vérifier les keySkills : l'utilisateur doit posséder tous les requiredKeySkills
      // dans ses skills (pas ses keySkills)
      if (requiredKeySkills.isNotEmpty) {
        final userSkillsSet = Set<String>.from(_currentUser!.skills);
        final hasAllKeySkills = requiredKeySkills.every((skill) => userSkillsSet.contains(skill));
        if (!hasAllKeySkills) continue;
      }

      pending++;
    }

    exchangePendingCount.value = pending;
    hasExchangePending.value = pending > 0;

    debugPrint('🔔 [BadgeCountService] Exchange pending count updated: $pending');
  }

  void _updateMyExchangeRequestsCount(QuerySnapshot snapshot) {
    if (_currentUserId == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int myRequests = 0;
    int needingSelection = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;

      final status = data['status'] as String?;
      final startTime = (data['initiatorStartTime'] as Timestamp?)?.toDate();
      final proposalIds = List<String>.from(data['proposalIds'] ?? []);
      final selectedProposalId = data['selectedProposalId'] as String?;

      if (startTime == null) continue;

      // Filtre date : startTime >= aujourd'hui
      final startDate = DateTime(startTime.year, startTime.month, startTime.day);
      final isFuture = startDate.isAfter(today) || startDate.isAtSameMomentAs(today);
      if (!isFuture) continue;

      // Exclure les demandes acceptées ou annulées
      if (status == 'accepted' || status == 'cancelled') continue;

      myRequests++;

      // Badge violet : demandes avec propositions mais pas encore de sélection
      if (status == 'open' && proposalIds.isNotEmpty && selectedProposalId == null) {
        needingSelection++;
      }
    }

    exchangeMyRequestsCount.value = myRequests;
    exchangeNeedingSelectionCount.value = needingSelection;
    hasExchangeNeedingSelection.value = needingSelection > 0;

    debugPrint('🔔 [BadgeCountService] My exchange requests updated: myRequests=$myRequests, needingSelection=$needingSelection');
  }

  // ============================================================
  // VALIDATIONS (CHEFS)
  // ============================================================

  void _subscribeToValidations() {
    if (_currentUser == null) return;

    // Seulement pour les chefs et leaders
    if (_currentUser!.status != 'chief' && _currentUser!.status != 'leader') {
      debugPrint('🔔 [BadgeCountService] User is not chief/leader, skipping validations subscription');
      return;
    }

    final acceptancesPath = _getReplacementAcceptancesPath();
    debugPrint('🔔 [BadgeCountService] Subscribing to validations at: $acceptancesPath');

    _validationSubscription = FirebaseFirestore.instance
        .collection(acceptancesPath)
        .where('status', isEqualTo: 'pendingValidation')
        .where('chiefTeamId', isEqualTo: _currentUser!.team)
        .snapshots()
        .listen(
          (snapshot) {
            final count = snapshot.docs.length;
            // Note: Le count de validation remplacement est déjà inclus dans replacementToValidateCount
            // via _updateReplacementCounts. Ce stream sert de backup/vérification.
            debugPrint('🔔 [BadgeCountService] Replacement acceptances pending validation: $count');
          },
          onError: (error) => debugPrint('🔔 [BadgeCountService] Validations stream error: $error'),
        );

    // Pour les échanges, on doit vérifier les propositions en attente de validation
    _subscribeToExchangeValidations();
  }

  StreamSubscription? _exchangeValidationSubscription;

  void _subscribeToExchangeValidations() {
    if (_currentUser == null) return;
    if (_currentUser!.status != 'chief' && _currentUser!.status != 'leader') return;

    final proposalsPath = _getExchangeProposalsPath();

    _exchangeValidationSubscription = FirebaseFirestore.instance
        .collection(proposalsPath)
        .where('status', isEqualTo: 'selectedByInitiator')
        .snapshots()
        .listen(
          (snapshot) => _updateExchangeValidationCount(snapshot),
          onError: (error) => debugPrint('🔔 [BadgeCountService] Exchange validations stream error: $error'),
        );
  }

  Future<void> _updateExchangeValidationCount(QuerySnapshot snapshot) async {
    if (_currentUser == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int toValidate = 0;

    // Récupérer les IDs des demandes associées pour filtrer par date
    final requestIds = <String>{};
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final requestId = data['requestId'] as String?;
      if (requestId != null) {
        requestIds.add(requestId);
      }
    }

    // Récupérer les demandes pour obtenir les dates
    final requestsPath = _getExchangeRequestsPath();
    final requestDates = <String, DateTime>{};

    for (final requestId in requestIds) {
      try {
        final requestDoc = await FirebaseFirestore.instance
            .collection(requestsPath)
            .doc(requestId)
            .get();
        if (requestDoc.exists) {
          final requestData = requestDoc.data();
          if (requestData != null) {
            final startTime = (requestData['initiatorStartTime'] as Timestamp?)?.toDate();
            if (startTime != null) {
              requestDates[requestId] = startTime;
            }
          }
        }
      } catch (e) {
        debugPrint('🔔 [BadgeCountService] Error fetching request $requestId: $e');
      }
    }

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;

      final requestId = data['requestId'] as String?;
      final proposerTeamId = data['proposerTeamId'] as String?;
      final initiatorTeamId = data['initiatorTeamId'] as String?;
      final leaderValidations = data['leaderValidations'] as Map<String, dynamic>? ?? {};

      // Filtre date : vérifier si la demande associée est >= aujourd'hui
      if (requestId != null && requestDates.containsKey(requestId)) {
        final startTime = requestDates[requestId]!;
        final startDate = DateTime(startTime.year, startTime.month, startTime.day);
        final isFuture = startDate.isAfter(today) || startDate.isAtSameMomentAs(today);
        if (!isFuture) continue;
      }

      // Vérifier si le chef est concerné (équipe du proposeur ou de l'initiateur)
      final isMyTeam = proposerTeamId == _currentUser!.team || initiatorTeamId == _currentUser!.team;
      if (!isMyTeam) continue;

      // Vérifier si le chef a déjà validé
      final validationKey = '${_currentUser!.team}_$_currentUserId';
      if (leaderValidations.containsKey(validationKey)) continue;

      toValidate++;
    }

    exchangeToValidateCount.value = toValidate;
    hasExchangeValidation.value = toValidate > 0;

    debugPrint('🔔 [BadgeCountService] Exchange validations count updated: $toValidate');
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  /// Libère les ressources et annule les subscriptions.
  void dispose() {
    debugPrint('🔔 [BadgeCountService] Disposing...');

    _replacementSubscription?.cancel();
    _manualProposalsSubscription?.cancel();
    _agentQuerySubscription?.cancel();
    _teamEventSubscription?.cancel();
    _exchangeRequestsSubscription?.cancel();
    _exchangeProposalsSubscription?.cancel();
    _myExchangeRequestsSubscription?.cancel();
    _validationSubscription?.cancel();
    _exchangeValidationSubscription?.cancel();

    _replacementSubscription = null;
    _manualProposalsSubscription = null;
    _agentQuerySubscription = null;
    _teamEventSubscription = null;
    _exchangeRequestsSubscription = null;
    _exchangeProposalsSubscription = null;
    _myExchangeRequestsSubscription = null;
    _validationSubscription = null;
    _exchangeValidationSubscription = null;

    // Reset des compteurs
    replacementPendingCount.value = 0;
    replacementMyRequestsCount.value = 0;
    replacementToValidateCount.value = 0;
    agentQueryPendingCount.value = 0;
    agentQueryMyRequestsCount.value = 0;
    exchangePendingCount.value = 0;
    exchangeMyRequestsCount.value = 0;
    exchangeNeedingSelectionCount.value = 0;
    exchangeToValidateCount.value = 0;

    hasReplacementPending.value = false;
    hasReplacementValidation.value = false;
    hasAgentQueryPending.value = false;
    teamEventPendingCount.value = 0;
    hasTeamEventPending.value = false;
    hasExchangePending.value = false;
    hasExchangeNeedingSelection.value = false;
    hasExchangeValidation.value = false;

    _userProposalIds.clear();

    // Reset des compteurs internes
    _automaticPendingCount = 0;
    _automaticMyRequestsCount = 0;
    _automaticToValidateCount = 0;
    _manualPendingCount = 0;
    _manualMyRequestsCount = 0;
    _manualToValidateCount = 0;

    _isInitialized = false;
  }
}
