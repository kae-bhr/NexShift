import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/availability_model.dart';
import 'package:nexshift_app/core/data/models/on_call_level_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/repositories/on_call_level_repository.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/utils/constants.dart';

class AddAvailabilityPage extends StatefulWidget {
  const AddAvailabilityPage({super.key});

  @override
  State<AddAvailabilityPage> createState() => _AddAvailabilityPageState();
}

class _AddAvailabilityPageState extends State<AddAvailabilityPage> {
  DateTime? _selectedStart;
  DateTime? _selectedEnd;
  List<Planning> _availablePlannings = [];
  List<OnCallLevel> _availabilityLevels = [];
  OnCallLevel? _selectedLevel;
  bool _isLoading = false;

  // Intervalles où l'agent est en astreinte (pour contrainte horaire)
  List<({DateTime start, DateTime end})> _onCallIntervals = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = await UserStorageHelper.loadUser();
    if (user == null) return;

    final repo = LocalRepository();
    final levelRepo = OnCallLevelRepository();
    final now = DateTime.now();

    final results = await Future.wait([
      repo.getPlanningsByStationInRange(
        user.station,
        now.subtract(const Duration(hours: 24)),
        now.add(const Duration(days: 90)),
      ),
      levelRepo.getAll(user.station),
    ]);

    final plannings = results[0] as List<Planning>;
    final allLevels = results[1] as List<OnCallLevel>;

    // Calculer les intervalles d'astreinte de l'agent
    final intervals = plannings
        .where((p) => p.agentsId.contains(user.id) && p.endTime.isAfter(now))
        .map((p) => (start: p.startTime, end: p.endTime))
        .toList();

    final availabilityLevels =
        allLevels.where((l) => l.isAvailability).toList();

    if (!mounted) return;
    setState(() {
      _availablePlannings =
          plannings.where((p) => p.endTime.isAfter(now)).toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));
      _availabilityLevels = availabilityLevels;
      _onCallIntervals = intervals;
      // Auto-sélectionner si un seul niveau disponible
      if (availabilityLevels.length == 1) {
        _selectedLevel = availabilityLevels.first;
      }
    });
  }

  /// Vérifie si un DateTime chevauche un intervalle d'astreinte existant.
  bool _isInOnCall(DateTime dt) {
    for (final interval in _onCallIntervals) {
      if (!dt.isBefore(interval.start) && dt.isBefore(interval.end)) {
        return true;
      }
    }
    return false;
  }

  /// Retourne le prochain créneau hors-astreinte après [dt].
  DateTime _nextAvailableTime(DateTime dt) {
    var candidate = dt;
    for (final interval in _onCallIntervals
      ..sort((a, b) => a.start.compareTo(b.start))) {
      if (!candidate.isBefore(interval.start) &&
          candidate.isBefore(interval.end)) {
        candidate = interval.end;
      }
    }
    return candidate;
  }

  Future<void> _pickStartDateTime() async {
    final now = DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: _selectedStart ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _selectedStart != null
          ? TimeOfDay.fromDateTime(_selectedStart!)
          : TimeOfDay.now(),
    );

    if (time == null) return;

    var selectedDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (selectedDateTime.isBefore(now)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'L\'heure de début ne peut pas être antérieure à maintenant',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Contrainte horaire : ajuster si dans une astreinte
    if (_isInOnCall(selectedDateTime)) {
      final adjusted = _nextAvailableTime(selectedDateTime);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Créneau en astreinte. Début ajusté à ${_formatDateTime(adjusted)}',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      selectedDateTime = adjusted;
    }

    setState(() {
      _selectedStart = selectedDateTime;
      if (_selectedEnd != null && _selectedEnd!.isBefore(_selectedStart!)) {
        _selectedEnd = null;
      }
    });
  }

  Future<void> _pickEndDateTime() async {
    if (_selectedStart == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez d\'abord sélectionner une heure de début'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final date = await showDatePicker(
      context: context,
      initialDate:
          _selectedEnd ?? _selectedStart!.add(const Duration(hours: 1)),
      firstDate: _selectedStart!,
      lastDate: _selectedStart!.add(const Duration(days: 30)),
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _selectedEnd != null
          ? TimeOfDay.fromDateTime(_selectedEnd!)
          : TimeOfDay.fromDateTime(
              _selectedStart!.add(const Duration(hours: 1)),
            ),
    );

    if (time == null) return;

    var selectedDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (selectedDateTime.isBefore(_selectedStart!)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('L\'heure de fin doit être après l\'heure de début'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Contrainte horaire : si la fin tombe dans une astreinte, la tronquer au début de l'astreinte
    for (final interval in _onCallIntervals
      ..sort((a, b) => a.start.compareTo(b.start))) {
      if (_selectedStart!.isBefore(interval.start) &&
          selectedDateTime.isAfter(interval.start)) {
        selectedDateTime = interval.start;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Fin ajustée à ${_formatDateTime(selectedDateTime)} (début d\'astreinte)',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        break;
      }
    }

    setState(() {
      _selectedEnd = selectedDateTime;
    });
  }

  Future<void> _saveAvailability() async {
    if (_selectedStart == null || _selectedEnd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner les heures de début et de fin'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_availabilityLevels.isNotEmpty && _selectedLevel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un niveau de disponibilité'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = await UserStorageHelper.loadUser();
      if (user == null) {
        throw Exception('Utilisateur non connecté');
      }

      final repo = LocalRepository();

      // Vérifier les conflits avec les astreintes de l'utilisateur
      final plannings = await repo.getPlanningsByStationInRange(
        user.station,
        _selectedStart!,
        _selectedEnd!,
      );

      final conflictingPlannings = plannings.where((p) {
        if (!p.agentsId.contains(user.id)) return false;
        return p.endTime.isAfter(_selectedStart!) &&
            p.startTime.isBefore(_selectedEnd!);
      }).toList();

      if (conflictingPlannings.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Vous ne pouvez pas vous rendre disponible sur une période où vous êtes déjà d\'astreinte',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Détection automatique du planning chevauché
      Planning? detectedPlanning;
      for (final planning in _availablePlannings) {
        if (planning.endTime.isAfter(_selectedStart!) &&
            planning.startTime.isBefore(_selectedEnd!)) {
          detectedPlanning = planning;
          break;
        }
      }

      final availability = Availability.create(
        agentId: user.id,
        start: _selectedStart!,
        end: _selectedEnd!,
        planningId: detectedPlanning?.id,
        levelId: _selectedLevel?.id,
      );

      await repo.addAvailability(availability, stationId: user.station);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              detectedPlanning != null
                  ? 'Disponibilité ajoutée pour l\'équipe ${detectedPlanning.team}'
                  : 'Disponibilité ajoutée avec succès',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} "
        "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: Text(
          'Ajouter une disponibilité',
          style: TextStyle(color: Theme.of(context).primaryColor),
        ),
        bottomColor: KColors.appNameColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Indiquez vos plages de disponibilité',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Vous pouvez vous rendre disponible même en dehors des astreintes planifiées.',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),

                  // Début
                  Card(
                    elevation: 2,
                    child: InkWell(
                      onTap: _pickStartDateTime,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Début',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selectedStart != null
                                        ? _formatDateTime(_selectedStart!)
                                        : 'Sélectionner',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: _selectedStart != null
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.tertiary
                                          : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: Colors.grey[400]),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Fin
                  Card(
                    elevation: 2,
                    child: InkWell(
                      onTap: _pickEndDateTime,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Fin',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selectedEnd != null
                                        ? _formatDateTime(_selectedEnd!)
                                        : 'Sélectionner',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: _selectedEnd != null
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.tertiary
                                          : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: Colors.grey[400]),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Sélecteur de niveau de disponibilité
                  if (_availabilityLevels.isEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.shade200,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Aucun niveau de disponibilité configuré. Contactez un administrateur.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ] else ...[
                    Text(
                      'Niveau de disponibilité',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...(_availabilityLevels.map((level) {
                      final isSelected = _selectedLevel?.id == level.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () =>
                              setState(() => _selectedLevel = level),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            height: 48,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? level.color
                                    : Colors.grey.withValues(alpha: 0.3),
                                width: isSelected ? 2 : 1,
                              ),
                              color: isSelected
                                  ? level.color.withValues(alpha: 0.08)
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: level.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    level.name,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected ? level.color : null,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: level.color,
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    })),
                    const SizedBox(height: 16),
                  ],

                  // Info sur la détection automatique
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200, width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Le planning sera détecté automatiquement si votre disponibilité chevauche une astreinte existante.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Bouton d'enregistrement
                  FilledButton.icon(
                    onPressed: _availabilityLevels.isEmpty
                        ? null
                        : _saveAvailability,
                    icon: const Icon(Icons.check),
                    label: const Text('Enregistrer ma disponibilité'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
