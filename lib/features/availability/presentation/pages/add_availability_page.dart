import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/availability_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
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
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPlannings();
  }

  Future<void> _loadPlannings() async {
    final repo = LocalRepository();
    final now = DateTime.now();
    // Charger les plannings futurs ou en cours
    final plannings = await repo.getAllPlanningsInRange(
      now.subtract(const Duration(hours: 24)),
      now.add(const Duration(days: 90)),
    );

    setState(() {
      _availablePlannings =
          plannings.where((p) => p.endTime.isAfter(now)).toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));
    });
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

    final selectedDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    // Vérifier que l'heure de début n'est pas dans le passé
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

    setState(() {
      _selectedStart = selectedDateTime;
      // Réinitialiser la fin si elle est avant le nouveau début
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

    final selectedDateTime = DateTime(
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

    setState(() => _isLoading = true);

    try {
      final user = await UserStorageHelper.loadUser();
      if (user == null) {
        throw Exception('Utilisateur non connecté');
      }

      final repo = LocalRepository();

      // Vérifier les conflits avec les astreintes de l'utilisateur
      final plannings = await repo.getAllPlanningsInRange(
        _selectedStart!,
        _selectedEnd!,
      );

      // Filtrer les plannings où l'utilisateur est en astreinte
      final conflictingPlannings = plannings.where((p) {
        // Vérifier si l'utilisateur est agent de ce planning
        if (!p.agentsId.contains(user.id)) return false;

        // Vérifier si les périodes se chevauchent
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
                  const SizedBox(height: 32),

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
                    onPressed: _saveAvailability,
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
