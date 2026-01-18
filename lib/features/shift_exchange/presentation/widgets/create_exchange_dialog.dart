import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/services/shift_exchange_service.dart';

/// Dialog pour créer une demande d'échange d'astreinte
Future<bool?> showCreateExchangeDialog({
  required BuildContext context,
  required String userId,
  required String stationId,
  String? preselectedPlanningId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _CreateExchangeDialog(
      userId: userId,
      stationId: stationId,
      preselectedPlanningId: preselectedPlanningId,
    ),
  );
}

class _CreateExchangeDialog extends StatefulWidget {
  final String userId;
  final String stationId;
  final String? preselectedPlanningId;

  const _CreateExchangeDialog({
    required this.userId,
    required this.stationId,
    this.preselectedPlanningId,
  });

  @override
  State<_CreateExchangeDialog> createState() => _CreateExchangeDialogState();
}

class _CreateExchangeDialogState extends State<_CreateExchangeDialog> {
  final _exchangeService = ShiftExchangeService();
  final _planningRepository = PlanningRepository();

  List<Planning> _allUserPlannings = [];
  List<Planning> _filteredPlannings = [];
  Planning? _selectedPlanning;
  bool _isLoading = true;
  bool _isSubmitting = false;
  DateTime _selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadUserPlannings();
  }

  Future<void> _loadUserPlannings() async {
    try {
      print('[DEBUG Exchange] Loading plannings for user: ${widget.userId}, station: ${widget.stationId}');

      // Récupérer tous les plannings de la station
      final stationPlannings = await _planningRepository.getByStation(widget.stationId);
      print('[DEBUG Exchange] Total plannings in station: ${stationPlannings.length}');

      // Filtrer pour ne garder que ceux de l'utilisateur
      final userPlannings = stationPlannings
          .where((p) => p.agentsId.contains(widget.userId))
          .toList();
      print('[DEBUG Exchange] User plannings found: ${userPlannings.length}');

      for (var p in userPlannings) {
        print('[DEBUG Exchange]   - Planning ${p.id}: start=${p.startTime}, end=${p.endTime}, station=${p.station}');
      }

      // Filtrer pour ne garder que les plannings non terminés
      final now = DateTime.now();
      print('[DEBUG Exchange] Current time: $now');

      final availablePlannings = userPlannings
          .where((p) => p.endTime.isAfter(now))
          .toList();

      print('[DEBUG Exchange] Available plannings after filter: ${availablePlannings.length}');
      for (var p in availablePlannings) {
        print('[DEBUG Exchange]   - Available: ${p.id}, start=${p.startTime}, end=${p.endTime}');
      }

      // Trier par date
      availablePlannings.sort((a, b) => a.startTime.compareTo(b.startTime));

      if (mounted) {
        setState(() {
          _allUserPlannings = availablePlannings;
          _filterPlanningsByMonth();
          // Pré-sélectionner le planning si fourni
          if (widget.preselectedPlanningId != null && _filteredPlannings.isNotEmpty) {
            print('[DEBUG Exchange] Trying to preselect planning: ${widget.preselectedPlanningId}');
            try {
              _selectedPlanning = _filteredPlannings.firstWhere(
                (p) => p.id == widget.preselectedPlanningId,
              );
              print('[DEBUG Exchange] Preselected planning found: ${_selectedPlanning!.id}');
            } catch (_) {
              print('[DEBUG Exchange] Preselected planning NOT found in available list');
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[DEBUG Exchange] ERROR loading plannings: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors du chargement: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterPlanningsByMonth() {
    final startOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final endOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);

    _filteredPlannings = _allUserPlannings.where((p) {
      // Inclure si le planning chevauche le mois sélectionné
      return p.startTime.isBefore(endOfMonth) && p.endTime.isAfter(startOfMonth);
    }).toList();
  }

  String _formatMonthYear(DateTime date) {
    const months = [
      'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
      'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta, 1);
      _filterPlanningsByMonth();
      // Désélectionner si le planning n'est plus dans la liste filtrée
      if (_selectedPlanning != null && !_filteredPlannings.contains(_selectedPlanning)) {
        _selectedPlanning = null;
      }
    });
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _submitExchange() async {
    if (_selectedPlanning == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner une astreinte'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _exchangeService.createExchangeRequest(
        initiatorId: widget.userId,
        planningId: _selectedPlanning!.id,
        station: widget.stationId,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Créer une demande d\'échange'),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(),
                ),
              )
            : _allUserPlannings.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.event_busy,
                          size: 48,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Aucune astreinte future disponible',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sélecteur de mois
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left, size: 20),
                              onPressed: () => _changeMonth(-1),
                              tooltip: 'Mois précédent',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue[200]!),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.calendar_month, size: 16, color: Colors.blue[700]),
                                    const SizedBox(width: 6),
                                    Text(
                                      _formatMonthYear(_selectedMonth),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue[900],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_right, size: 20),
                              onPressed: () => _changeMonth(1),
                              tooltip: 'Mois suivant',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Sélectionnez l\'astreinte que vous souhaitez échanger :',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: _filteredPlannings.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(
                                  child: Text(
                                    'Aucune astreinte pour ce mois',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: _filteredPlannings.length,
                                itemBuilder: (context, index) {
                                  final planning = _filteredPlannings[index];
                                  final isSelected = _selectedPlanning?.id == planning.id;

                                  return Card(
                                    color: isSelected
                                        ? Colors.blue[50]
                                        : Colors.white,
                                    child: ListTile(
                                      onTap: () {
                                        setState(() {
                                          _selectedPlanning = planning;
                                        });
                                      },
                                      leading: Radio<String>(
                                        value: planning.id,
                                        groupValue: _selectedPlanning?.id,
                                        onChanged: (value) {
                                          setState(() {
                                            _selectedPlanning = planning;
                                          });
                                        },
                                      ),
                                      title: Text(
                                        'Équipe ${planning.team}',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text(
                                            '${_formatDateTime(planning.startTime)}',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          Text(
                                            '→ ${_formatDateTime(planning.endTime)}',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                      trailing: isSelected
                                          ? const Icon(Icons.check_circle, color: Colors.blue)
                                          : null,
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, size: 20, color: Colors.blue),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Les agents possédant vos compétences-clés pourront répondre à cette demande',
                                style: TextStyle(fontSize: 12, color: Colors.blue),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting || _selectedPlanning == null
              ? null
              : _submitExchange,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Créer la demande'),
        ),
      ],
    );
  }
}
