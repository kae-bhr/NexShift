import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_request_model.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/services/shift_exchange_service.dart';

/// Dialog pour proposer son astreinte en échange
Future<bool?> showProposeShiftDialog({
  required BuildContext context,
  required ShiftExchangeRequest request,
  required String userId,
  required String stationId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _ProposeShiftDialog(
      request: request,
      userId: userId,
      stationId: stationId,
    ),
  );
}

class _ProposeShiftDialog extends StatefulWidget {
  final ShiftExchangeRequest request;
  final String userId;
  final String stationId;

  const _ProposeShiftDialog({
    required this.request,
    required this.userId,
    required this.stationId,
  });

  @override
  State<_ProposeShiftDialog> createState() => _ProposeShiftDialogState();
}

class _ProposeShiftDialogState extends State<_ProposeShiftDialog> {
  final _exchangeService = ShiftExchangeService();
  final _planningRepository = PlanningRepository();

  List<Planning> _futureUserPlannings = [];
  Set<String> _selectedPlanningIds = {}; // MODIFIÉ: Set pour sélection multiple
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadUserPlannings();
  }

  Future<void> _loadUserPlannings() async {
    try {
      print('[DEBUG ProposeShift] Loading plannings for user: ${widget.userId}, station: ${widget.stationId}');

      // Récupérer tous les plannings de l'utilisateur pour cette station
      final allPlannings = await _planningRepository.getForUser(
        widget.userId,
        stationId: widget.stationId,
      );
      print('[DEBUG ProposeShift] Total user plannings: ${allPlannings.length}');

      // Filtrer pour ne garder que les plannings futurs de la bonne station
      // Note: On considère qu'un planning est "futur" si sa date de début n'est pas encore passée
      final now = DateTime.now();
      print('[DEBUG ProposeShift] Current time: $now');

      final futurePlannings = allPlannings
          .where((p) {
            // Vérifier que la date de début n'est pas encore passée (même jour = futur)
            final startDate = DateTime(p.startTime.year, p.startTime.month, p.startTime.day);
            final today = DateTime(now.year, now.month, now.day);
            final isFuture = startDate.isAfter(today) || startDate.isAtSameMomentAs(today);
            final isRightStation = p.station == widget.stationId;
            print('[DEBUG ProposeShift]   Planning ${p.id}: start=${p.startTime}, station=${p.station}, isFuture=$isFuture, isRightStation=$isRightStation');
            return isFuture && isRightStation;
          })
          .toList();

      print('[DEBUG ProposeShift] Future plannings after filter: ${futurePlannings.length}');

      // Trier par date
      futurePlannings.sort((a, b) => a.startTime.compareTo(b.startTime));

      if (mounted) {
        setState(() {
          _futureUserPlannings = futurePlannings;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[DEBUG ProposeShift] ERROR: $e');
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

  String _formatDateTime(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _submitProposal() async {
    if (_selectedPlanningIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner au moins une astreinte'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // MODIFIÉ: Envoyer la liste des plannings sélectionnés
      await _exchangeService.createProposal(
        requestId: widget.request.id,
        proposerId: widget.userId,
        planningIds: _selectedPlanningIds.toList(),
        stationId: widget.stationId,
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
      title: const Text('Proposer mon astreinte'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Afficher la demande initiale
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person, size: 16, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          widget.request.initiatorName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const Text(
                          ' propose',
                          style: TextStyle(color: Colors.blue),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatDateTime(widget.request.initiatorStartTime),
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '→ ${_formatDateTime(widget.request.initiatorEndTime)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'En échange, proposez une ou plusieurs de vos astreintes :',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_futureUserPlannings.isEmpty)
                const Padding(
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
              else
                ...List.generate(_futureUserPlannings.length, (index) {
                  final planning = _futureUserPlannings[index];
                  final isSelected = _selectedPlanningIds.contains(planning.id);

                  return Card(
                    color: isSelected ? Colors.green[50] : Colors.white,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedPlanningIds.remove(planning.id);
                          } else {
                            _selectedPlanningIds.add(planning.id);
                          }
                        });
                      },
                      title: Text(
                        'Équipe ${planning.team}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            _formatDateTime(planning.startTime),
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            '→ ${_formatDateTime(planning.endTime)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(Icons.circle_outlined, color: Colors.grey),
                    ),
                  );
                }),
              const SizedBox(height: 16),
              if (_selectedPlanningIds.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 20, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_selectedPlanningIds.length} astreinte(s) sélectionnée(s)',
                          style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'L\'initiateur devra sélectionner votre proposition avant validation par les chefs',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting || _selectedPlanningIds.isEmpty
              ? null
              : _submitProposal,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_selectedPlanningIds.length > 1
                  ? 'Proposer ${_selectedPlanningIds.length} astreintes'
                  : 'Proposer'),
        ),
      ],
    );
  }
}
