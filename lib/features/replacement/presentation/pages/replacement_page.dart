import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/features/replacement/services/replacement_search_service.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/presentation/widgets/planning_form_widgets.dart';
import 'package:nexshift_app/core/config/environment_config.dart';

class ReplacementPage extends StatefulWidget {
  final Planning planning;
  // optional: when provided the replaced agent is forced to this user
  final User? currentUser;
  // optional: when provided this indicates we are replacing a replacer's subshift
  final Subshift? parentSubshift;
  // Mode manuel = proposition directe à une personne
  // Mode automatique = recherche avec système de vagues
  final bool isManualMode;

  const ReplacementPage({
    super.key,
    required this.planning,
    this.currentUser,
    this.parentSubshift,
    this.isManualMode = false, // Par défaut: mode automatique
  });

  @override
  State<ReplacementPage> createState() => _ReplacementPageState();
}

class _ReplacementPageState extends State<ReplacementPage> {
  final repo = SubshiftRepository();
  List<User> allUsers = [];
  List<Subshift> existingSubshifts = [];
  List<Map<String, DateTime>> activeRequestPeriods =
      []; // Périodes avec demandes actives
  String? replacedId;

  /// When replacing a replacer (parentSubshift != null), this holds the original
  /// replaced agent's ID for data operations (validation, saving).
  /// For display, replacedId shows the actual person seeking absence (the replacer).
  String? _dataReplacedId;
  String? replacerId;
  DateTime? startDateTime;
  DateTime? endDateTime;
  String? error;
  bool isSOS = false; // Mode SOS (vagues simultanées)

  /// Returns the ID to use for data operations (uncovered periods, conflicts, saving)
  String? get dataReplacedId => _dataReplacedId ?? replacedId;

  bool get isValid {
    // Mode manuel: require both replaced and replacer
    if (widget.isManualMode) {
      return replacedId != null &&
          replacerId != null &&
          startDateTime != null &&
          endDateTime != null &&
          error == null;
    }
    // Mode automatique: require only dates (replaced = current user)
    return replacedId != null &&
        startDateTime != null &&
        endDateTime != null &&
        error == null;
  }

  /// Determine if the current user can select who to replace
  /// Only admins, leaders, and team chiefs (of the planning's team) can select
  bool get canSelectReplaced =>
      widget.currentUser != null &&
      (widget.currentUser!.admin ||
          widget.currentUser!.status == KConstants.statusLeader ||
          (widget.currentUser!.status == KConstants.statusChief &&
              widget.currentUser!.team == widget.planning.team));

  String _getNotificationTriggersPath(String stationId) {
    return EnvironmentConfig.getCollectionPath(
        'replacements/automatic/notificationTriggers', stationId);
  }

  String _getManualReplacementProposalsPath(String stationId) {
    return EnvironmentConfig.getCollectionPath(
        'replacements/manual/proposals', stationId);
  }

  @override
  void initState() {
    super.initState();
    _loadUsers();
    // if currentUser is provided, pre-select replacedId
    if (widget.currentUser != null) {
      replacedId = widget.currentUser!.id;
      // Synchroniser _dataReplacedId pour éviter tout décalage affichage/données
      _dataReplacedId = widget.currentUser!.id;
    }
    // if parentSubshift is provided (we are replacing a replacer), prefill fields
    if (widget.parentSubshift != null) {
      final p = widget.parentSubshift!;
      // Display: show the replacer (Agent A) as the person seeking absence
      replacedId = widget.currentUser?.id ?? p.replacerId;
      // Data: identique à l'affichage — chaque agent a ses propres entrées
      // dans planning.agents, donc on utilise le même ID partout
      _dataReplacedId = replacedId;
      // prefill window with the parent subshift window
      startDateTime = p.start;
      endDateTime = p.end;
    }
  }

  Future<void> _loadUsers() async {
    // Charger les utilisateurs de la station du planning
    final users = await UserRepository().getByStation(widget.planning.station);
    final subshifts = await repo.getByPlanningId(
      widget.planning.id,
      stationId: widget.planning.station,
    );
    await _loadActiveRequests();
    setState(() {
      allUsers = users;
      existingSubshifts = subshifts;
    });
  }

  /// Charge les périodes couvertes par des demandes de remplacement actives
  /// Inclut les demandes automatiques, manuelles et les échanges
  Future<void> _loadActiveRequests() async {
    try {
      if (widget.currentUser == null) return;

      final stationId = widget.currentUser!.station;
      final periods = <Map<String, DateTime>>[];

      // 1. Charger les demandes automatiques
      final automaticPath = EnvironmentConfig.getCollectionPath(
          'replacements/automatic/replacementRequests', stationId);

      final automaticSnapshot = await FirebaseFirestore.instance
          .collection(automaticPath)
          .where('planningId', isEqualTo: widget.planning.id)
          .where('status', whereIn: ['pending', 'accepted'])
          .get();

      for (final doc in automaticSnapshot.docs) {
        final data = doc.data();
        final start = (data['startTime'] as Timestamp).toDate();
        final end = (data['endTime'] as Timestamp).toDate();
        final requesterId = data['requesterId'] as String;

        // Ajouter la période seulement si c'est pour l'utilisateur sélectionné
        if (requesterId == dataReplacedId) {
          periods.add({'start': start, 'end': end});
        }
      }

      // 2. Charger les demandes manuelles
      final manualPath = _getManualReplacementProposalsPath(stationId);
      final manualSnapshot = await FirebaseFirestore.instance
          .collection(manualPath)
          .where('planningId', isEqualTo: widget.planning.id)
          .where('status', isEqualTo: 'pending')
          .get();

      for (final doc in manualSnapshot.docs) {
        final data = doc.data();
        final start = (data['startTime'] as Timestamp).toDate();
        final end = (data['endTime'] as Timestamp).toDate();
        final requestReplacedId = data['replacedId'] as String;

        // Ajouter la période seulement si c'est pour l'utilisateur sélectionné
        if (requestReplacedId == dataReplacedId) {
          periods.add({'start': start, 'end': end});
        }
      }

      // 3. Charger les demandes d'échange
      final exchangePath = EnvironmentConfig.getCollectionPath(
          'shiftExchangeRequests', stationId);

      final exchangeSnapshot = await FirebaseFirestore.instance
          .collection(exchangePath)
          .where('initiatorPlanningId', isEqualTo: widget.planning.id)
          .where('status', whereIn: ['open', 'proposalSelected'])
          .get();

      for (final doc in exchangeSnapshot.docs) {
        final data = doc.data();
        final start = (data['initiatorStartTime'] as Timestamp).toDate();
        final end = (data['initiatorEndTime'] as Timestamp).toDate();
        final initiatorId = data['initiatorId'] as String;

        // Ajouter la période seulement si c'est pour l'utilisateur sélectionné
        if (initiatorId == dataReplacedId) {
          periods.add({'start': start, 'end': end});
        }
      }

      setState(() {
        activeRequestPeriods = periods;
      });
    } catch (e) {
      debugPrint('Error loading active requests: $e');
    }
  }

  void _validate() {
    String? err;

    if (startDateTime == null || endDateTime == null) {
      err = "Veuillez sélectionner les horaires.";
    } else if (endDateTime!.isBefore(startDateTime!)) {
      err = "L'heure de fin ne peut pas être antérieure à l'heure de début.";
    } else if (startDateTime!.isBefore(widget.planning.startTime)) {
      err = "La date de début ne peut pas précéder celle de l'astreinte.";
    } else if (endDateTime!.isAfter(widget.planning.endTime)) {
      err = "La date de fin ne peut pas dépasser celle de l'astreinte.";
    } else if (dataReplacedId != null &&
        _isOutsideEffectivePresence(
          dataReplacedId!,
          startDateTime!,
          endDateTime!,
        )) {
      err = "L'agent n'est pas d'astreinte sur cette plage horaire.";
    } else if (dataReplacedId != null &&
        replacerId != null &&
        dataReplacedId == replacerId) {
      err = "Un agent ne peut pas se remplacer lui-même.";
    } else if (widget.isManualMode &&
        replacerId != null &&
        _isInPlanningDuringPeriod(replacerId!, startDateTime!, endDateTime!)) {
      err = "Le remplaçant est déjà d'astreinte sur cette plage horaire.";
    } else if (dataReplacedId != null &&
        _isFullyCoveredByActiveRequests(dataReplacedId!)) {
      err =
          "Cette période est déjà totalement couverte par des demandes de remplacement en cours.";
    } else if (_hasConflict(
      dataReplacedId,
      replacerId,
      startDateTime!,
      endDateTime!,
      ignoreSubshiftId: widget.parentSubshift?.id,
    )) {
      // Détermine la cause du conflit pour un message plus précis
      final conflictType = _getConflictType(
        replacedId,
        replacerId,
        startDateTime!,
        endDateTime!,
        ignoreSubshiftId: widget.parentSubshift?.id,
      );
      if (conflictType == 'replaced') {
        err =
            "Le remplacé est déjà remplacé par quelqu'un d'autre sur cette période.";
      } else if (conflictType == 'replacer') {
        err = "Le remplaçant est déjà engagé sur cette période.";
      } else {
        err =
            "Chevauchement détecté : le remplaçant ou le remplacé est déjà engagé sur cette période.";
      }
    }

    setState(() => error = err);
  }

  /// Vérifie si la période de l'astreinte est totalement couverte par des demandes actives
  bool _isFullyCoveredByActiveRequests(String userId) {
    final gaps = _uncoveredPeriodsFor(userId);
    return gaps.isEmpty;
  }

  /// Vérifie si la plage demandée sort de la présence effective de l'agent.
  /// La présence est définie par planning.agents (source unique de vérité).
  /// Inclut les entrées de base (replacedAgentId == null) ET les entrées
  /// de remplacement (où l'agent est remplaçant, replacedAgentId != null).
  bool _isOutsideEffectivePresence(
    String agentId,
    DateTime start,
    DateTime end,
  ) {
    final agentEntries = widget.planning.agents
        .where((a) => a.agentId == agentId)
        .toList();
    if (agentEntries.isEmpty) return true;
    // Vérifier que la plage demandée est contenue dans au moins une entrée
    for (final entry in agentEntries) {
      if (!start.isBefore(entry.start) && !end.isAfter(entry.end)) {
        return false;
      }
    }
    return true;
  }

  /// Vérifie si un agent est présent dans planning.agents avec chevauchement
  /// sur la période [start, end]. Utilisé pour refuser un remplaçant déjà
  /// d'astreinte sur la plage demandée (mode manuel).
  bool _isInPlanningDuringPeriod(String agentId, DateTime start, DateTime end) {
    return widget.planning.agents.any(
      (a) =>
          a.agentId == agentId && a.start.isBefore(end) && a.end.isAfter(start),
    );
  }

  bool _hasConflict(
    String? replacedId,
    String? replacerId,
    DateTime start,
    DateTime end, {
    String? ignoreSubshiftId,
  }) {
    bool overlap(
      DateTime aStart,
      DateTime aEnd,
      DateTime bStart,
      DateTime bEnd,
    ) {
      return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
    }

    for (final s in existingSubshifts) {
      if (ignoreSubshiftId != null && s.id == ignoreSubshiftId) continue;

      // Vérification 1: Le remplacé ne peut pas être remplacé plusieurs fois sur la même période
      if (s.replacedId == replacedId && overlap(start, end, s.start, s.end)) {
        return true;
      }

      // Vérification 2: Le remplaçant ne peut pas être engagé sur des périodes qui se chevauchent
      if (s.replacerId == replacerId && overlap(start, end, s.start, s.end)) {
        return true;
      }
    }
    return false;
  }

  String? _getConflictType(
    String? replacedId,
    String? replacerId,
    DateTime start,
    DateTime end, {
    String? ignoreSubshiftId,
  }) {
    bool overlap(
      DateTime aStart,
      DateTime aEnd,
      DateTime bStart,
      DateTime bEnd,
    ) {
      return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
    }

    for (final s in existingSubshifts) {
      if (ignoreSubshiftId != null && s.id == ignoreSubshiftId) continue;

      if (s.replacedId == replacedId && overlap(start, end, s.start, s.end)) {
        return 'replaced';
      }

      if (s.replacerId == replacerId && overlap(start, end, s.start, s.end)) {
        return 'replacer';
      }
    }
    return null;
  }

  // --- Compute uncovered periods for selected replaced agent ---
  List<Map<String, DateTime>> _uncoveredPeriodsFor(String replacedId) {
    // Déterminer la plage effective de l'agent (ses entrées dans planning.agents)
    final agentEntries = widget.planning.agents
        .where((a) => a.agentId == replacedId)
        .toList();

    if (agentEntries.isEmpty) return [];

    // Construire les plages de présence effective de l'agent
    final List<Map<String, DateTime>> presencePeriods = agentEntries
        .map((a) => {'start': a.start, 'end': a.end})
        .toList();

    // collect subshifts that target this agent and intersect ses plages
    final List<Map<String, DateTime>> coveredPeriods = existingSubshifts
        .where(
          (s) =>
              s.replacedId == replacedId &&
              agentEntries.any(
                (a) => s.start.isBefore(a.end) && s.end.isAfter(a.start),
              ),
        )
        .map((s) => {'start': s.start, 'end': s.end})
        .toList();

    // Ajouter les périodes des demandes actives
    coveredPeriods.addAll(activeRequestPeriods);

    // Pour chaque plage de présence, calculer les gaps non couverts
    final List<Map<String, DateTime>> allGaps = [];
    for (final presence in presencePeriods) {
      final pStart = presence['start']!;
      final pEnd = presence['end']!;

      // Filtrer et normaliser les périodes couvertes à cette plage de présence
      final relevantCovered =
          coveredPeriods
              .where(
                (c) => c['start']!.isBefore(pEnd) && c['end']!.isAfter(pStart),
              )
              .map(
                (c) => {
                  'start': c['start']!.isBefore(pStart) ? pStart : c['start']!,
                  'end': c['end']!.isAfter(pEnd) ? pEnd : c['end']!,
                },
              )
              .toList()
            ..sort((a, b) => a['start']!.compareTo(b['start']!));

      // Merge overlapping
      final List<Map<String, DateTime>> merged = [];
      for (final seg in relevantCovered) {
        if (merged.isEmpty) {
          merged.add({'start': seg['start']!, 'end': seg['end']!});
          continue;
        }
        final last = merged.last;
        if (!seg['start']!.isAfter(last['end']!)) {
          if (seg['end']!.isAfter(last['end']!)) last['end'] = seg['end']!;
        } else {
          merged.add({'start': seg['start']!, 'end': seg['end']!});
        }
      }

      // Compute gaps
      var cursor = pStart;
      for (final m in merged) {
        if (m['start']!.isAfter(cursor)) {
          allGaps.add({'start': cursor, 'end': m['start']!});
        }
        if (m['end']!.isAfter(cursor)) cursor = m['end']!;
      }
      if (cursor.isBefore(pEnd)) {
        allGaps.add({'start': cursor, 'end': pEnd});
      }
    }

    return allGaps;
  }

  // --- Compute periods where a replacer is not available (busy) ---
  List<Map<String, DateTime>> _unavailablePeriodsFor(String replacerId) {
    final planningStart = widget.planning.startTime;
    final planningEnd = widget.planning.endTime;

    final List<Subshift> busy = existingSubshifts
        .where(
          (s) =>
              s.replacerId == replacerId &&
              s.end.isAfter(planningStart) &&
              s.start.isBefore(planningEnd),
        )
        .toList();

    if (busy.isEmpty) return [];

    final normalized =
        busy
            .map(
              (s) => {
                'start': s.start.isBefore(planningStart)
                    ? planningStart
                    : s.start,
                'end': s.end.isAfter(planningEnd) ? planningEnd : s.end,
              },
            )
            .toList()
          ..sort((a, b) => a['start']!.compareTo(b['start']!));

    final List<Map<String, DateTime>> merged = [];
    for (final seg in normalized) {
      if (merged.isEmpty) {
        merged.add({'start': seg['start']!, 'end': seg['end']!});
        continue;
      }
      final last = merged.last;
      if (seg['start']!.isBefore(last['end']!) ||
          seg['start']!.isAtSameMomentAs(last['end']!)) {
        if (seg['end']!.isAfter(last['end']!)) last['end'] = seg['end']!;
      } else {
        merged.add({'start': seg['start']!, 'end': seg['end']!});
      }
    }

    return merged;
  }

  Future<bool> _pickDateTime({
    required bool isStart,
    required DateTime initialDate,
  }) async {
    final astreinteStart = widget.planning.startTime;
    final astreinteEnd = widget.planning.endTime;

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: astreinteStart.subtract(const Duration(days: 30)),
      lastDate: astreinteEnd.add(const Duration(days: 30)),
    );
    if (date == null) return false;

    if (!mounted) return false;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null) return false;

    final result = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      if (isStart) {
        startDateTime = result;
      } else {
        endDateTime = result;
      }
      _validate();
    });

    return true;
  }

  /// Returns the earliest start of the selected replaced agent's presence entries.
  /// Falls back to planning start if no agent selected or no entries found.
  DateTime _effectiveWindowStart() {
    if (dataReplacedId == null) return widget.planning.startTime;
    final entries = widget.planning.agents
        .where((a) => a.agentId == dataReplacedId)
        .toList();
    if (entries.isEmpty) return widget.planning.startTime;
    return entries.map((a) => a.start).reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// Returns the latest end of the selected replaced agent's presence entries.
  /// Falls back to planning end if no agent selected or no entries found.
  DateTime _effectiveWindowEnd() {
    if (dataReplacedId == null) return widget.planning.endTime;
    final entries = widget.planning.agents
        .where((a) => a.agentId == dataReplacedId)
        .toList();
    if (entries.isEmpty) return widget.planning.endTime;
    return entries.map((a) => a.end).reduce((a, b) => a.isAfter(b) ? a : b);
  }

  Future<void> _save() async {
    _validate();
    if (!isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Veuillez corriger les erreurs avant de valider."),
        ),
      );
      return;
    }

    // Toujours envoyer une proposition de remplacement manuel.
    // Le découpage des subshifts (parentSubshift) sera effectué
    // lors de la validation/acceptation de la proposition.
    await _sendManualReplacementProposal();
  }

  /// Send a manual replacement proposal to the replacer
  /// The replacer will receive a notification and can accept or decline
  Future<void> _sendManualReplacementProposal() async {
    try {
      // Determine who is the proposer (current user if provided, otherwise use replacedId as proposer)
      User proposerUser;
      if (widget.currentUser != null) {
        proposerUser = widget.currentUser!;
      } else {
        // Fallback: shouldn't happen but handle gracefully
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Utilisateur non trouvé")));
        return;
      }

      // Get the replaced and replacer users (use dataReplacedId for the data model)
      final replacedUser = allUsers.firstWhere(
        (u) => u.id == dataReplacedId,
        orElse: User.empty,
      );
      final replacerUser = allUsers.firstWhere(
        (u) => u.id == replacerId,
        orElse: User.empty,
      );

      if (replacedUser.id.isEmpty || replacerUser.id.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Utilisateur non trouvé")));
        return;
      }

      // Create a proposal document in Firestore with correct path
      final proposalsPath = _getManualReplacementProposalsPath(
        widget.planning.station,
      );
      print('[DEBUG Manual] Creating proposal at path: $proposalsPath');

      final proposalRef = FirebaseFirestore.instance
          .collection(proposalsPath)
          .doc();

      final proposalData = {
        'id': proposalRef.id,
        'proposerId': proposerUser.id,
        'proposerName': '${proposerUser.firstName} ${proposerUser.lastName}',
        'replacedId': dataReplacedId,
        'replacedName': '${replacedUser.firstName} ${replacedUser.lastName}',
        'replacerId': replacerId,
        'replacerName': '${replacerUser.firstName} ${replacerUser.lastName}',
        'planningId': widget.planning.id,
        'startTime': Timestamp.fromDate(startDateTime!),
        'endTime': Timestamp.fromDate(endDateTime!),
        'status': 'pending', // pending, accepted, declined
        'createdAt': FieldValue.serverTimestamp(),
        'station': widget.planning.station,
      };

      print('[DEBUG Manual] Proposal data: $proposalData');
      await proposalRef.set(proposalData);
      print('[DEBUG Manual] Proposal created with ID: ${proposalRef.id}');

      // Send notification to the replacer via notificationTriggers
      final notificationTriggersPath = _getNotificationTriggersPath(
        widget.planning.station,
      );
      await FirebaseFirestore.instance.collection(notificationTriggersPath).add(
        {
          'type': 'manual_replacement_proposal',
          'proposalId': proposalRef.id,
          'proposerId': proposerUser.id,
          'proposerName': '${proposerUser.firstName} ${proposerUser.lastName}',
          'replacedId': dataReplacedId,
          'replacedName': '${replacedUser.firstName} ${replacedUser.lastName}',
          'replacerId': replacerId,
          'planningId': widget.planning.id,
          'startTime': Timestamp.fromDate(startDateTime!),
          'endTime': Timestamp.fromDate(endDateTime!),
          'targetUserIds': [replacerId],
          'createdAt': FieldValue.serverTimestamp(),
          'processed': false,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Proposition envoyée à ${replacerUser.displayName}"),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('❌ Error sending manual replacement proposal: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Erreur lors de l'envoi de la proposition"),
          ),
        );
      }
    }
  }

  Future<void> _searchForReplacer() async {
    // Validate first
    _validate();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error!)));
      return;
    }

    // Vérifier que replacedId est défini
    if (dataReplacedId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sélectionnez un agent à remplacer")),
      );
      return;
    }

    // Trouver l'utilisateur remplacé pour récupérer sa station et son équipe
    final replacedUser = allUsers.firstWhere(
      (u) => u.id == dataReplacedId,
      orElse: () => widget.currentUser ?? User.empty(),
    );

    if (replacedUser.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Agent à remplacer non trouvé")),
      );
      return;
    }

    await ReplacementSearchService.searchForReplacer(
      context,
      requesterId:
          dataReplacedId!, // Utiliser l'ID de l'agent dans le modèle de données
      planningId: widget.planning.id,
      startDateTime: startDateTime,
      endDateTime: endDateTime,
      station: replacedUser.station,
      team: replacedUser.team,
      isSOS: isSOS,
      onValidate: _validate,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Build combined list for the "Remplacé" dropdown using service
    final replacedCandidates = ReplacementSearchService.getReplacedCandidates(
      allUsers,
      existingSubshifts,
      widget.planning,
    );

    final validReplacedId =
        replacedId != null && replacedCandidates.any((u) => u.id == replacedId)
        ? replacedId
        : null;

    final availableReplacers =
        ReplacementSearchService.buildAvailableReplacersDropdown(
          allUsers,
          widget.planning,
        );

    final validReplacerId =
        replacerId != null &&
            availableReplacers.any((item) => item.value == replacerId)
        ? replacerId
        : null;

    return Scaffold(
      appBar: CustomAppBar(
        title: widget.isManualMode
            ? "Remplacement manuel"
            : "Recherche de remplaçant",
        bottomColor: KColors.appNameColor,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: isValid
                ? (widget.isManualMode ? _save : _searchForReplacer)
                : null,
            icon: Icon(
              widget.isManualMode ? Icons.check_rounded : Icons.search_rounded,
              size: 20,
            ),
            label: Text(
              widget.isManualMode
                  ? "Proposer le remplacement"
                  : "Rechercher un remplaçant",
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: KColors.appNameColor,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Agent remplacé ──────────────────────────────────────────────
          _ReplacementSectionHeader(
            icon: Icons.person_off_rounded,
            label: 'Agent remplacé',
          ),
          const SizedBox(height: 8),
          if (canSelectReplaced)
            _ReplacementStyledDropdown<String>(
              value: validReplacedId,
              hint: 'Sélectionnez un agent',
              items: replacedCandidates
                  .map(
                    (u) => DropdownMenuItem(
                      value: u.id,
                      child: Text(u.displayName),
                    ),
                  )
                  .toList(),
              onChanged: (v) async {
                setState(() {
                  replacedId = v;
                  _dataReplacedId = v;
                });
                await _loadActiveRequests();
                _validate();
              },
            )
          else if (widget.currentUser != null)
            _ReplacementReadOnlyField(
              icon: Icons.person_rounded,
              value: widget.currentUser!.displayName,
            ),

          // ── Agent remplaçant (mode manuel) ──────────────────────────────
          if (widget.isManualMode) ...[
            const SizedBox(height: 20),
            _ReplacementSectionHeader(
              icon: Icons.person_add_rounded,
              label: 'Agent remplaçant',
            ),
            const SizedBox(height: 8),
            _ReplacementStyledDropdown<String>(
              value: validReplacerId,
              hint: 'Sélectionnez un remplaçant',
              items: availableReplacers,
              onChanged: (v) {
                if (v == null || v == '__team_header__' || v == '__divider__') {
                  return;
                }
                setState(() => replacerId = v);
                _validate();
              },
            ),
          ],

          const SizedBox(height: 20),

          // ── Détails de l'astreinte ──────────────────────────────────────
          _ReplacementSectionHeader(
            icon: Icons.event_rounded,
            label: "Astreinte",
          ),
          const SizedBox(height: 8),
          SharedPlanningDetailCard(planning: widget.planning),

          const SizedBox(height: 20),

          // ── Période de remplacement ─────────────────────────────────────
          _ReplacementSectionHeader(
            icon: Icons.schedule_rounded,
            label: "Période de remplacement",
          ),
          const SizedBox(height: 8),
          SharedReplacementPeriodCard(
            startDateTime: startDateTime,
            endDateTime: endDateTime,
            errorMessage: error,
            uncoveredPeriods: dataReplacedId != null
                ? _uncoveredPeriodsFor(dataReplacedId!)
                : const [],
            onPickStart: () => _pickDateTime(
              isStart: true,
              initialDate: startDateTime ?? _effectiveWindowStart(),
            ),
            onPickEnd: () => _pickDateTime(
              isStart: false,
              initialDate: endDateTime ?? _effectiveWindowEnd(),
            ),
          ),

          // ── Mode SOS (automatique uniquement) ───────────────────────────
          if (!widget.isManualMode) ...[
            const SizedBox(height: 20),
            _ReplacementSectionHeader(
              icon: Icons.warning_amber_rounded,
              label: 'Options',
            ),
            const SizedBox(height: 8),
            _SOSCard(
              isSOS: isSOS,
              onToggle: () => setState(() => isSOS = !isSOS),
            ),
          ],

          const SizedBox(height: 8),

          // ── Sections mode manuel ────────────────────────────────────────
          if (widget.isManualMode) ...[
            // Indisponibilités du remplaçant
            if (replacerId != null) ...[
              const SizedBox(height: 20),
              Builder(
                builder: (context) {
                  final user = allUsers.firstWhere(
                    (u) => u.id == replacerId,
                    orElse: User.empty,
                  );
                  final busy = _unavailablePeriodsFor(replacerId!);
                  return _UnavailabilityCard(
                    agentName: user.displayName,
                    busyPeriods: busy,
                  );
                },
              ),
            ],

            // Impact sur les compétences
            if (canSelectReplaced && dataReplacedId != null) ...[
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final replacedUser = allUsers.firstWhere(
                    (u) => u.id == dataReplacedId,
                    orElse: User.empty,
                  );
                  final replacerUser = replacerId != null
                      ? allUsers.firstWhere(
                          (u) => u.id == replacerId,
                          orElse: User.empty,
                        )
                      : User.empty();
                  final replacedSkills = Set<String>.from(replacedUser.skills);
                  final replacerSkills = Set<String>.from(replacerUser.skills);
                  final gained =
                      replacerSkills.difference(replacedSkills).toList()
                        ..sort();
                  final lost =
                      replacedSkills.difference(replacerSkills).toList()
                        ..sort();
                  return _SkillsImpactCard(
                    gained: gained,
                    lost: lost,
                    noReplacerSelected: replacerId == null,
                  );
                },
              ),
            ],
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Widgets locaux ────────────────────────────────────────────────────────────

class _ReplacementSectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ReplacementSectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(
          icon,
          size: 15,
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

class _ReplacementStyledDropdown<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _ReplacementStyledDropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.grey.shade300,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint),
          isExpanded: true,
          items: items,
          onChanged: onChanged,
          borderRadius: BorderRadius.circular(12),
          dropdownColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        ),
      ),
    );
  }
}

class _ReplacementReadOnlyField extends StatelessWidget {
  final IconData icon;
  final String value;

  const _ReplacementReadOnlyField({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SOSCard extends StatelessWidget {
  final bool isSOS;
  final VoidCallback onToggle;

  const _SOSCard({required this.isSOS, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sosColor = Colors.red.shade600;

    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSOS
              ? sosColor.withValues(alpha: isDark ? 0.18 : 0.08)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.grey.shade50),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSOS
                ? sosColor.withValues(alpha: 0.5)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.grey.shade300),
            width: isSOS ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Toggle indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isSOS ? sosColor : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSOS
                      ? sosColor
                      : (isDark ? Colors.grey.shade500 : Colors.grey.shade400),
                  width: 2,
                ),
              ),
              child: isSOS
                  ? const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        size: 16,
                        color: isSOS
                            ? sosColor
                            : (isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Mode SOS',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: isSOS
                              ? sosColor
                              : (isDark
                                    ? Colors.grey.shade300
                                    : Colors.grey.shade700),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Row(
                                children: [
                                  Icon(
                                    Icons.bolt_rounded,
                                    color: Colors.red.shade600,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('Mode SOS'),
                                ],
                              ),
                              content: const Text(
                                'Le mode SOS permet d\'envoyer TOUTES les vagues de notifications simultanément au lieu de les envoyer progressivement.\n\n'
                                'Utilisez ce mode uniquement en cas d\'urgence pour maximiser les chances de trouver rapidement un remplaçant.\n\n'
                                'Note : Le filtrage par compétences-clés reste actif.',
                                style: TextStyle(fontSize: 14, height: 1.5),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Compris'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Icon(
                          Icons.help_outline_rounded,
                          size: 16,
                          color: isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Envoyer toutes les vagues simultanément',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnavailabilityCard extends StatelessWidget {
  final String agentName;
  final List<Map<String, DateTime>> busyPeriods;

  const _UnavailabilityCard({
    required this.agentName,
    required this.busyPeriods,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final isFree = busyPeriods.isEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isFree
            ? Colors.green.withValues(alpha: isDark ? 0.12 : 0.06)
            : (isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.grey.shade50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFree
              ? Colors.green.withValues(alpha: 0.35)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.grey.shade200),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isFree
                    ? Icons.check_circle_outline_rounded
                    : Icons.block_rounded,
                size: 16,
                color: isFree
                    ? Colors.green.shade600
                    : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isFree
                      ? '$agentName est disponible sur toute l\'astreinte'
                      : 'Indisponibilités de $agentName',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isFree
                        ? Colors.green.shade600
                        : (isDark
                              ? Colors.grey.shade300
                              : Colors.grey.shade700),
                  ),
                ),
              ),
            ],
          ),
          if (!isFree) ...[
            const SizedBox(height: 10),
            ...busyPeriods.map((g) {
              final s = g['start']!;
              final e = g['end']!;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 16,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${fmt.format(s)} → ${fmt.format(e)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.grey.shade300
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _SkillsImpactCard extends StatelessWidget {
  final List<String> gained;
  final List<String> lost;
  final bool noReplacerSelected;

  const _SkillsImpactCard({
    required this.gained,
    required this.lost,
    required this.noReplacerSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImpact = gained.isNotEmpty || lost.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                size: 16,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                'Impact sur les compétences',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!hasImpact)
            Text(
              'Aucun impact détecté — les compétences sont identiques.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
              ),
            )
          else ...[
            if (gained.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: gained
                    .map((s) => _SkillChip(label: s, isGain: true))
                    .toList(),
              ),
              if (lost.isNotEmpty) const SizedBox(height: 8),
            ],
            if (lost.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: lost
                    .map((s) => _SkillChip(label: s, isGain: false))
                    .toList(),
              ),
            if (noReplacerSelected && lost.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Aucun remplaçant sélectionné — ces compétences seraient manquantes.',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SkillChip extends StatelessWidget {
  final String label;
  final bool isGain;

  const _SkillChip({required this.label, required this.isGain});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isGain ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isGain ? Icons.add_rounded : Icons.remove_rounded,
            size: 12,
            color: isDark ? color.shade300 : color.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? color.shade300 : color.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

class ReplacementPageSearch extends StatefulWidget {
  final List<String> requestedSkills;
  final Duration duration;
  final String team;

  const ReplacementPageSearch({
    Key? key,
    required this.requestedSkills,
    required this.duration,
    required this.team,
  }) : super(key: key);

  @override
  State<ReplacementPageSearch> createState() => _ReplacementPageSearchState();
}

class _ReplacementPageSearchState extends State<ReplacementPageSearch> {
  late List<String> selectedSkills;

  @override
  void initState() {
    super.initState();
    selectedSkills = List.from(widget.requestedSkills);
  }

  @override
  Widget build(BuildContext context) {
    // TODO: Remplacer par la vraie liste de compétences disponibles
    final allSkills = <String>{...widget.requestedSkills};
    return Scaffold(
      appBar: AppBar(title: const Text('Recherche de remplaçant')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compétences requises :',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: allSkills
                  .map(
                    (skill) => FilterChip(
                      label: Text(skill),
                      selected: selectedSkills.contains(skill),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            selectedSkills.add(skill);
                          } else {
                            selectedSkills.remove(skill);
                          }
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
            Text(
              'Durée de l’astreinte : ${widget.duration.inHours}h',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                // TODO: Lancer la recherche de remplaçant avec selectedSkills
              },
              child: const Text('Rechercher'),
            ),
          ],
        ),
      ),
    );
  }
}
