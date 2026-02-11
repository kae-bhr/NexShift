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
import 'package:nexshift_app/features/replacement/presentation/widgets/planning_tile.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';

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
  List<Map<String, DateTime>> activeRequestPeriods = []; // Périodes avec demandes actives
  String? replacedId;
  String? replacerId;
  DateTime? startDateTime;
  DateTime? endDateTime;
  String? error;
  bool isSOS = false; // Mode SOS (vagues simultanées)

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

  /// Determine if text should be dark or light based on background luminance.
  /// If backgroundColor is null, uses the theme cardColor (Card default bg).
  Color _adaptiveTextColor(BuildContext context, {Color? backgroundColor}) {
    final bg = backgroundColor ?? Theme.of(context).cardColor;
    final luminance = bg.computeLuminance();
    return luminance > 0.5 ? Colors.black87 : Colors.white;
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

  String _getManualReplacementProposalsPath(String stationId) {
    if (EnvironmentConfig.useStationSubcollections && stationId.isNotEmpty) {
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null && sdisId.isNotEmpty) {
        return 'sdis/$sdisId/stations/$stationId/replacements/manual/proposals';
      }
      return 'stations/$stationId/replacements/manual/proposals';
    }
    return 'manualReplacementProposals';
  }

  @override
  void initState() {
    super.initState();
    _loadUsers();
    // if currentUser is provided, pre-select replacedId
    if (widget.currentUser != null) {
      replacedId = widget.currentUser!.id;
    }
    // if parentSubshift is provided (we are replacing a replacer), prefill fields
    if (widget.parentSubshift != null) {
      final p = widget.parentSubshift!;
      // replacedId should be the original replaced agent (not the replacer)
      replacedId = p.replacedId;
      // prefill window with the parent subshift window
      startDateTime = p.start;
      endDateTime = p.end;
    }
  }

  Future<void> _loadUsers() async {
    // Charger les utilisateurs de la station du planning
    final users = await UserRepository().getByStation(widget.planning.station);
    final subshifts = await repo.getByPlanningId(widget.planning.id);
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
      final sdisId = SDISContext().currentSDISId;
      final periods = <Map<String, DateTime>>[];

      // 1. Charger les demandes automatiques
      final automaticPath = EnvironmentConfig.useStationSubcollections && stationId.isNotEmpty
          ? (sdisId != null && sdisId.isNotEmpty
              ? 'sdis/$sdisId/stations/$stationId/replacements/automatic/replacementRequests'
              : 'stations/$stationId/replacements/automatic/replacementRequests')
          : 'replacementRequests';

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
        if (requesterId == replacedId) {
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
        if (requestReplacedId == replacedId) {
          periods.add({'start': start, 'end': end});
        }
      }

      // 3. Charger les demandes d'échange
      final exchangePath = EnvironmentConfig.useStationSubcollections && stationId.isNotEmpty
          ? (sdisId != null && sdisId.isNotEmpty
              ? 'sdis/$sdisId/stations/$stationId/shiftExchangeRequests'
              : 'stations/$stationId/shiftExchangeRequests')
          : 'shiftExchangeRequests';

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
        if (initiatorId == replacedId) {
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
    } else if (replacedId != null &&
        replacerId != null &&
        replacedId == replacerId) {
      err = "Un agent ne peut pas se remplacer lui-même.";
    } else if (replacedId != null && _isFullyCoveredByActiveRequests(replacedId!)) {
      err = "Cette période est déjà totalement couverte par des demandes de remplacement en cours.";
    } else if (_hasConflict(
      replacedId,
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
    final planningStart = widget.planning.startTime;
    final planningEnd = widget.planning.endTime;

    // collect subshifts that target this replaced agent and intersect planning bounds
    final List<Subshift> covered = existingSubshifts
        .where(
          (s) =>
              s.replacedId == replacedId &&
              s.end.isAfter(planningStart) &&
              s.start.isBefore(planningEnd),
        )
        .toList();

    // Ajouter les périodes avec demandes de remplacement actives comme "couvertes"
    final List<Map<String, DateTime>> coveredPeriods = covered.map((s) => {
      'start': s.start,
      'end': s.end,
    }).toList();

    // Ajouter les périodes des demandes actives
    coveredPeriods.addAll(activeRequestPeriods);

    if (coveredPeriods.isEmpty) {
      return [
        {'start': planningStart, 'end': planningEnd},
      ];
    }

    // normalize to planning bounds and sort by start
    final normalized =
        coveredPeriods
            .map(
              (period) => {
                'start': period['start']!.isBefore(planningStart)
                    ? planningStart
                    : period['start']!,
                'end': period['end']!.isAfter(planningEnd) ? planningEnd : period['end']!,
              },
            )
            .toList()
          ..sort((a, b) => a['start']!.compareTo(b['start']!));

    // merge overlapping intervals
    final List<Map<String, DateTime>> merged = [];
    for (final seg in normalized) {
      if (merged.isEmpty) {
        merged.add({'start': seg['start']!, 'end': seg['end']!});
        continue;
      }
      final last = merged.last;
      if (seg['start']!.isBefore(last['end']!) ||
          seg['start']!.isAtSameMomentAs(last['end']!)) {
        // extend end if needed
        if (seg['end']!.isAfter(last['end']!)) last['end'] = seg['end']!;
      } else {
        merged.add({'start': seg['start']!, 'end': seg['end']!});
      }
    }

    // compute gaps between planningStart..planningEnd excluding merged covered intervals
    final List<Map<String, DateTime>> gaps = [];
    var cursor = planningStart;
    for (final m in merged) {
      if (m['start']!.isAfter(cursor)) {
        gaps.add({'start': cursor, 'end': m['start']!});
      }
      // move cursor after this covered block
      if (m['end']!.isAfter(cursor)) cursor = m['end']!;
    }
    if (cursor.isBefore(planningEnd)) {
      gaps.add({'start': cursor, 'end': planningEnd});
    }

    return gaps;
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

  void _showDateTimePickerDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Modifier les horaires'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Début'),
                subtitle: Text(
                  startDateTime != null
                      ? DateFormat('dd/MM/yyyy HH:mm').format(startDateTime!)
                      : 'Non défini',
                ),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final result = await _pickDateTime(
                    isStart: true,
                    initialDate: startDateTime ?? widget.planning.startTime,
                  );
                  if (result) {
                    setDialogState(() {});
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Fin'),
                subtitle: Text(
                  endDateTime != null
                      ? DateFormat('dd/MM/yyyy HH:mm').format(endDateTime!)
                      : 'Non défini',
                ),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final result = await _pickDateTime(
                    isStart: false,
                    initialDate: endDateTime ?? widget.planning.endTime,
                  );
                  if (result) {
                    setDialogState(() {});
                  }
                },
              ),
            ],
          ),
          actions: [
            if (startDateTime != null && endDateTime != null)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Valider'),
              )
            else
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
          ],
        ),
      ),
    );
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

    // For manual replacements, send a proposal to the replacer
    // instead of saving directly
    // Exception: when replacing a replacer's subshift (parentSubshift), save directly
    if (widget.parentSubshift == null) {
      await _sendManualReplacementProposal();
      return;
    }

    // If we are replacing a replacer's subshift (parentSubshift provided), we need to split/replace that parent
    if (widget.parentSubshift != null) {
      final p = widget.parentSubshift!;
      final DateTime newStart = startDateTime!;
      final DateTime newEnd = endDateTime!;

      // new replacement must be inside the parent range
      if (newStart.isBefore(p.start) || newEnd.isAfter(p.end)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "La plage doit être à l'intérieur du remplacement existant.",
            ),
          ),
        );
        return;
      }

      // We'll delete the parent and recreate up to three segments: before, new replacement, after
      // (avoid zero-length segments)
      final List<Subshift> toCreate = [];

      if (p.start.isBefore(newStart)) {
        final before = Subshift.create(
          replacedId: p.replacedId,
          replacerId: p.replacerId,
          start: p.start,
          end: newStart,
          planningId: p.planningId,
        );
        toCreate.add(before);
      }

      // new segment: keep replacedId as original (p.replacedId) and replacer as selected replacer
      final newSeg = Subshift.create(
        replacedId: p.replacedId,
        replacerId: replacerId!,
        start: newStart,
        end: newEnd,
        planningId: p.planningId,
      );
      toCreate.add(newSeg);

      if (newEnd.isBefore(p.end)) {
        final after = Subshift.create(
          replacedId: p.replacedId,
          replacerId: p.replacerId,
          start: newEnd,
          end: p.end,
          planningId: p.planningId,
        );
        toCreate.add(after);
      }

      // perform DB updates: remove parent and add new segments
      await repo.delete(p.id);
      for (final s in toCreate) {
        await repo.save(s);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Remplacement appliqué et sous-segments créés ✅"),
        ),
      );

      if (mounted) Navigator.pop(context, toCreate);
      return;
    }

    // Default behaviour: create a fresh subshift
    final subshift = Subshift.create(
      replacedId: replacedId!,
      replacerId: replacerId!,
      start: startDateTime!,
      end: endDateTime!,
      planningId: widget.planning.id,
    );

    await repo.save(subshift);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Remplacement ajouté avec succès ✅")),
    );

    if (mounted) Navigator.pop(context, subshift);
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

      // Get the replaced and replacer users
      final replacedUser = allUsers.firstWhere(
        (u) => u.id == replacedId,
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
      final proposalsPath = _getManualReplacementProposalsPath(widget.planning.station);
      print('[DEBUG Manual] Creating proposal at path: $proposalsPath');

      final proposalRef = FirebaseFirestore.instance
          .collection(proposalsPath)
          .doc();

      final proposalData = {
        'id': proposalRef.id,
        'proposerId': proposerUser.id,
        'proposerName': '${proposerUser.firstName} ${proposerUser.lastName}',
        'replacedId': replacedId,
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
      final notificationTriggersPath = _getNotificationTriggersPath(widget.planning.station);
      await FirebaseFirestore.instance.collection(notificationTriggersPath).add({
        'type': 'manual_replacement_proposal',
        'proposalId': proposalRef.id,
        'proposerId': proposerUser.id,
        'proposerName': '${proposerUser.firstName} ${proposerUser.lastName}',
        'replacedId': replacedId,
        'replacedName': '${replacedUser.firstName} ${replacedUser.lastName}',
        'replacerId': replacerId,
        'planningId': widget.planning.id,
        'startTime': Timestamp.fromDate(startDateTime!),
        'endTime': Timestamp.fromDate(endDateTime!),
        'targetUserIds': [replacerId],
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Proposition envoyée à ${replacerUser.displayName}",
            ),
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
    if (replacedId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Sélectionnez un agent à remplacer")));
      return;
    }

    // Trouver l'utilisateur remplacé pour récupérer sa station et son équipe
    final replacedUser = allUsers.firstWhere(
      (u) => u.id == replacedId,
      orElse: () => widget.currentUser ?? User.empty(),
    );

    if (replacedUser.id.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Agent à remplacer non trouvé")));
      return;
    }

    await ReplacementSearchService.searchForReplacer(
      context,
      requesterId: replacedId!, // Utiliser l'ID de l'agent sélectionné
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

    // Valider que replacedId est bien dans la liste des candidats
    // Si non, le remettre à null pour éviter l'erreur "value not in items"
    final validReplacedId = replacedId != null &&
            replacedCandidates.any((u) => u.id == replacedId)
        ? replacedId
        : null;

    // Build available replacers dropdown using service
    final availableReplacers =
        ReplacementSearchService.buildAvailableReplacersDropdown(
          allUsers,
          widget.planning,
        );

    // Valider que replacerId est bien dans la liste des remplaçants disponibles
    final validReplacerId = replacerId != null &&
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // CHAMP "REMPLACÉ" - Affiché dans tous les modes (manuel et automatique)
            // Dropdown cliquable si user privilégié, sinon lecture seule
            if (canSelectReplaced)
              DropdownButtonFormField<String>(
                value: validReplacedId,
                decoration: InputDecoration(
                  labelText: "Remplacé",
                  hintText: validReplacedId == null ? "Sélectionnez un agent" : null,
                ),
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
                  });
                  await _loadActiveRequests();
                  _validate();
                },
              )
            else if (widget.currentUser != null)
              // Show read-only field with current user's name
              TextFormField(
                initialValue:
                    widget.currentUser!.displayName,
                decoration: const InputDecoration(labelText: "Remplacé"),
                readOnly: true,
                enabled: false,
              ),
            const SizedBox(height: 12),

            // MODE MANUEL: afficher aussi le champ Remplaçant
            if (widget.isManualMode) ...[
              // Show replacer dropdown for all users (both privileged and regular)
              // Everyone can select the replacer
              DropdownButtonFormField<String>(
                value: validReplacerId,
                decoration: const InputDecoration(labelText: "Remplaçant"),
                items: availableReplacers,
                onChanged: (v) {
                  // ignore special non-selectable tokens
                  if (v == null ||
                      v == '__team_header__' ||
                      v == '__divider__')
                    return;
                  setState(() {
                    replacerId = v;
                  });
                  _validate();
                },
              ),
              const SizedBox(height: 16),
            ],

            // Card Astreinte avec les horaires
            PlanningTile(
              planning: widget.planning,
              startDateTime: startDateTime,
              endDateTime: endDateTime,
              errorMessage: error,
              onTap: () => _showDateTimePickerDialog(),
            ),
            const SizedBox(height: 16),

            // Mode SOS - uniquement en mode automatique
            if (!widget.isManualMode) ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSOS ? Colors.red : Colors.grey[300]!,
                    width: 2,
                  ),
                ),
                color: isSOS ? Colors.red[50] : Colors.white,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      isSOS = !isSOS;
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: isSOS ? Colors.red : Colors.white,
                            border: Border.all(
                              color: isSOS ? Colors.red : Colors.grey[400]!,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: isSOS
                              ? const Icon(
                                  Icons.check,
                                  size: 18,
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
                                    Icons.warning,
                                    size: 18,
                                    color: isSOS ? Colors.red : Colors.grey[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Mode SOS',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isSOS ? Colors.red[700] : Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Row(
                                            children: [
                                              Icon(Icons.local_hospital, color: Colors.red[700]),
                                              const SizedBox(width: 8),
                                              const Text('Mode SOS'),
                                            ],
                                          ),
                                          content: const Text(
                                            'Le mode SOS permet d\'envoyer TOUTES les vagues de notifications simultanément au lieu de les envoyer progressivement.\n\n'
                                            'Utilisez ce mode uniquement en cas d\'urgence pour maximiser les chances de trouver rapidement un remplaçant.\n\n'
                                            'Note : Le filtrage par compétences-clés reste actif.',
                                            style: TextStyle(fontSize: 14),
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
                                      Icons.help_outline,
                                      size: 18,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Envoyer toutes les vagues simultanément',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Bouton différent selon le mode
            ElevatedButton.icon(
              onPressed: isValid
                  ? (widget.isManualMode ? _save : _searchForReplacer)
                  : null,
              icon: Icon(widget.isManualMode ? Icons.check : Icons.search),
              label: Text(
                widget.isManualMode ? "Valider" : "Rechercher un remplaçant",
              ),
            ),

            // --- Display uncovered periods for the selected replaced agent ---
            // Affiché en mode automatique ET manuel
            const SizedBox(height: 16),
            if (replacedId != null) ...[
              Builder(
                builder: (context) {
                  final user = allUsers.firstWhere(
                    (u) => u.id == replacedId,
                    orElse: User.empty,
                  );
                  final gaps = _uncoveredPeriodsFor(replacedId!);
                  final cardColor = gaps.isEmpty ? Colors.green[50] : null;
                  final textColor = _adaptiveTextColor(
                    context,
                    backgroundColor: cardColor,
                  );
                  return Card(
                    color: cardColor,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Périodes non couvertes pour ${user.displayName} :",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (gaps.isEmpty)
                            Text(
                              "Aucune période non couverte.",
                              style: TextStyle(color: textColor),
                            )
                          else
                            ...gaps.map((g) {
                              final s = g['start']!;
                              final e = g['end']!;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.remove_circle_outline,
                                      size: 16,
                                      color: Colors.red,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        "${DateFormat('dd/MM/yyyy HH:mm').format(s)} — ${DateFormat('dd/MM/yyyy HH:mm').format(e)}",
                                        style: TextStyle(color: textColor),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],

            // --- Sections affichées seulement en mode manuel ---
            if (widget.isManualMode) ...[
              // --- Display unavailable periods for the selected replacer ---
              if (replacerId != null) ...[
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final user = allUsers.firstWhere(
                      (u) => u.id == replacerId,
                      orElse: User.empty,
                    );
                    final busy = _unavailablePeriodsFor(replacerId!);
                    final cardColor = busy.isEmpty ? Colors.green[50] : null;
                    final textColor = _adaptiveTextColor(
                      context,
                      backgroundColor: cardColor,
                    );
                    return Card(
                      color: cardColor,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Périodes où ${user.displayName} est indisponible :",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (busy.isEmpty)
                              Text(
                                "Aucune indisponibilité détectée.",
                                style: TextStyle(color: textColor),
                              )
                            else
                              ...busy.map((g) {
                                final s = g['start']!;
                                final e = g['end']!;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.block,
                                        size: 16,
                                        color: Colors.orange,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          "${DateFormat('dd/MM/yyyy HH:mm').format(s)} — ${DateFormat('dd/MM/yyyy HH:mm').format(e)}",
                                          style: TextStyle(color: textColor),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],

              // --- Skills impact due to the replacement ---
              // Afficher le delta de compétences seulement en mode manuel
              if (canSelectReplaced && (replacedId != null)) ...[
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final replacedUser = allUsers.firstWhere(
                      (u) => u.id == replacedId,
                      orElse: User.empty,
                    );
                    final replacerUser = replacerId != null
                        ? allUsers.firstWhere(
                            (u) => u.id == replacerId,
                            orElse: User.empty,
                          )
                        : User.empty();
                    final replacedSkills = Set<String>.from(
                      replacedUser.skills,
                    );
                    final replacerSkills = Set<String>.from(
                      replacerUser.skills,
                    );
                    final gained =
                        replacerSkills.difference(replacedSkills).toList()
                          ..sort();
                    final lost =
                        replacedSkills.difference(replacerSkills).toList()
                          ..sort();
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Impact sur les compétences :",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (gained.isEmpty && lost.isEmpty)
                              const Text(
                                "Aucun impact sur les compétences pour la période sélectionnée.",
                              ),
                            if (gained.isNotEmpty) ...[
                              const Text(
                                "Compétences gagnées :",
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ...gained.map(
                                (s) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2.0,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.add_circle,
                                        size: 16,
                                        color: Colors.green,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(s)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (lost.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Text(
                                "Compétences perdues :",
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ...lost.map(
                                (s) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2.0,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.remove_circle,
                                        size: 16,
                                        color: Colors.red,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(s)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (replacerId == null && lost.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Text(
                                "Remarque : aucun remplaçant sélectionné — ces compétences seraient perdues si elles ne sont pas  uvertes.",
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ], // Fin du bloc if (widget.isManualMode)
          ],
        ),
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
