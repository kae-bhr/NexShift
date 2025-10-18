import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/features/replacement/services/replacement_search_service.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/planning_tile.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';

class ReplacementPage extends StatefulWidget {
  final Planning planning;
  // optional: when provided the replaced agent is forced to this user
  final User? currentUser;
  // optional: when provided this indicates we are replacing a replacer's subshift
  final Subshift? parentSubshift;

  const ReplacementPage({
    super.key,
    required this.planning,
    this.currentUser,
    this.parentSubshift,
  });

  @override
  State<ReplacementPage> createState() => _ReplacementPageState();
}

class _ReplacementPageState extends State<ReplacementPage> {
  final repo = SubshiftRepository();
  List<User> allUsers = [];
  List<Subshift> existingSubshifts = [];
  String? replacedId;
  String? replacerId;
  DateTime? startDateTime;
  DateTime? endDateTime;
  String? error;

  bool get isValid =>
      replacedId != null &&
      replacerId != null &&
      startDateTime != null &&
      endDateTime != null &&
      error == null;

  /// Determine if text should be dark or light based on background luminance.
  /// If backgroundColor is null, uses the theme cardColor (Card default bg).
  Color _adaptiveTextColor(BuildContext context, {Color? backgroundColor}) {
    final bg = backgroundColor ?? Theme.of(context).cardColor;
    final luminance = bg.computeLuminance();
    return luminance > 0.5 ? Colors.black87 : Colors.white;
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
    final users = await LocalRepository().getAllUsers();
    final subshifts = await repo.getByPlanningId(widget.planning.id);
    setState(() {
      allUsers = users;
      existingSubshifts = subshifts;
    });
  }

  void _validate() {
    String? err;

    if (startDateTime == null || endDateTime == null) {
      err = "Veuillez sélectionner les horaires.";
    } else if (endDateTime!.isBefore(startDateTime!)) {
      err = "L'heure de fin ne peut pas être antérieure à l'heure de début.";
    } else if (startDateTime!.isBefore(widget.planning.startTime)) {
      err = "La date de début ne peut pas précéder celle de l’astreinte.";
    } else if (endDateTime!.isAfter(widget.planning.endTime)) {
      err = "La date de fin ne peut pas dépasser celle de l’astreinte.";
    } else if (replacedId != null &&
        replacerId != null &&
        replacedId == replacerId) {
      err = "Un agent ne peut pas se remplacer lui-même.";
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

    if (covered.isEmpty) {
      return [
        {'start': planningStart, 'end': planningEnd},
      ];
    }

    // normalize to planning bounds and sort by start
    final normalized =
        covered
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

  Future<void> _searchForReplacer() async {
    // Validate first
    _validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error!)),
      );
      return;
    }

    // Get the current user (replaced agent)
    final currentUser = widget.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Utilisateur non trouvé")),
      );
      return;
    }

    await ReplacementSearchService.searchForReplacer(
      context,
      requesterId: currentUser.id,
      planningId: widget.planning.id,
      startDateTime: startDateTime,
      endDateTime: endDateTime,
      station: currentUser.station,
      team: currentUser.team,
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

    // Build available replacers dropdown using service
    final availableReplacers =
        ReplacementSearchService.buildAvailableReplacersDropdown(
          allUsers,
          widget.planning,
        );

    return Scaffold(
      appBar: CustomAppBar(
        title: widget.currentUser == null
            ? "Remplacement manuel"
            : "Recherche de remplaçant",
        bottomColor: KColors.appNameColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // If a currentUser was provided, the replaced agent is forced and not selectable
            if (widget.currentUser == null)
              DropdownButtonFormField<String>(
                value: replacedId,
                decoration: const InputDecoration(labelText: "Remplacé"),
                items: replacedCandidates
                    .map(
                      (u) => DropdownMenuItem(
                        value: u.id,
                        child: Text("${u.lastName} ${u.firstName}"),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    replacedId = v;
                  });
                  _validate();
                },
              ),
            const SizedBox(height: 12),
            // If currentUser is provided, we hide the replacer selector and switch to search mode
            if (widget.currentUser == null)
              DropdownButtonFormField<String>(
                value: replacerId,
                decoration: const InputDecoration(labelText: "Remplaçant"),
                items: availableReplacers,
                onChanged: (v) {
                  // ignore special non-selectable tokens
                  if (v == null ||
                      v == '__team_header__' ||
                      v == '__ppbeider__')
                    return;
                  setState(() {
                    replacerId = v;
                  });
                  _validate();
                },
              ),
            const SizedBox(height: 16),
            PlanningTile(
              planning: widget.planning,
              startDateTime: startDateTime,
              endDateTime: endDateTime,
              errorMessage: error,
              onTap: () => _showDateTimePickerDialog(),
            ),
            const SizedBox(height: 16),
            if (widget.currentUser == null)
              ElevatedButton.icon(
                onPressed: isValid ? _save : null,
                icon: const Icon(Icons.check),
                label: const Text("Valider"),
              )
            else
              ElevatedButton.icon(
                onPressed: () => _searchForReplacer(),
                icon: const Icon(Icons.search),
                label: const Text("Rechercher un remplaçant"),
              ),

            // --- Display uncovered periods for the selected replaced agent ---
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
                            "Périodes non couvertes pour ${user.firstName} ${user.lastName} :",
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
                            "Périodes où ${user.firstName} ${user.lastName} est indisponible :",
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
            if ((widget.currentUser == null) && (replacedId != null)) ...[
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
                  final replacedSkills = Set<String>.from(replacedUser.skills);
                  final replacerSkills = Set<String>.from(replacerUser.skills);
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
                            style: const TextStyle(fontWeight: FontWeight.bold),
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
