import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_proposal_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_request_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/services/shift_exchange_service.dart';

/// Structure pour représenter une astreinte individuelle proposée
class _IndividualProposal {
  final String proposalId; // ID de la proposition parente
  final String planningId; // ID du planning spécifique
  final Planning planning; // Détails du planning
  final String proposerName; // Nom du proposeur
  final String proposerTeamId; // Équipe du proposeur
  final ShiftExchangeProposalStatus status; // Statut de la proposition
  final Map<String, LeaderValidation>
  leaderValidations; // Validations des chefs (pour motif de refus)
  final List<String> rejectedPlanningIds; // Liste des plannings refusés

  _IndividualProposal({
    required this.proposalId,
    required this.planningId,
    required this.planning,
    required this.proposerName,
    required this.proposerTeamId,
    required this.status,
    required this.leaderValidations,
    required this.rejectedPlanningIds,
  });
}

/// Dialog pour que l'agent A sélectionne UNE astreinte parmi toutes celles reçues
Future<bool?> showProposalSelectionDialog({
  required BuildContext context,
  required ShiftExchangeRequest request,
  required List<ShiftExchangeProposal> proposals,
  required String initiatorId,
  required String stationId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _ProposalSelectionDialog(
      request: request,
      proposals: proposals,
      initiatorId: initiatorId,
      stationId: stationId,
    ),
  );
}

class _ProposalSelectionDialog extends StatefulWidget {
  final ShiftExchangeRequest request;
  final List<ShiftExchangeProposal> proposals;
  final String initiatorId;
  final String stationId;

  const _ProposalSelectionDialog({
    required this.request,
    required this.proposals,
    required this.initiatorId,
    required this.stationId,
  });

  @override
  State<_ProposalSelectionDialog> createState() =>
      _ProposalSelectionDialogState();
}

class _ProposalSelectionDialogState extends State<_ProposalSelectionDialog> {
  final _exchangeService = ShiftExchangeService();
  final _planningRepository = PlanningRepository();

  String? _selectedProposalId;
  String? _selectedPlanningId;
  bool _isSubmitting = false;
  List<_IndividualProposal> _individualProposals = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadIndividualProposals();
  }

  /// Charge toutes les astreintes individuelles de toutes les propositions
  Future<void> _loadIndividualProposals() async {
    try {
      final List<_IndividualProposal> allIndividualProposals = [];

      for (final proposal in widget.proposals) {
        for (final planningId in proposal.proposedPlanningIds) {
          final planning = await _planningRepository.getById(
            planningId,
            stationId: widget.stationId,
          );

          if (planning != null) {
            allIndividualProposals.add(
              _IndividualProposal(
                proposalId: proposal.id,
                planningId: planningId,
                planning: planning,
                proposerName: proposal.proposerName,
                proposerTeamId: proposal.proposerTeamId ?? '?',
                status: proposal.status,
                leaderValidations: proposal.leaderValidations,
                rejectedPlanningIds: proposal.rejectedPlanningIds,
              ),
            );
          }
        }
      }

      // Trier par date de début
      allIndividualProposals.sort(
        (a, b) => a.planning.startTime.compareTo(b.planning.startTime),
      );

      if (mounted) {
        setState(() {
          _individualProposals = allIndividualProposals;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[DEBUG ProposalSelection] ERROR: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  /// Affiche le motif de refus d'une proposition
  void _showRejectionReason(_IndividualProposal individual) {
    // Trouver le refus dans les validations
    final rejections = individual.leaderValidations.entries
        .where((e) => e.value.approved == false)
        .toList();

    if (rejections.isEmpty) {
      return;
    }

    // Prendre le premier refus (normalement il n'y en a qu'un)
    final rejection = rejections.first.value;
    final comment = rejection.comment ?? 'Aucun motif spécifié';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Proposition refusée'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Motif du refus :',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(comment),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitSelection() async {
    if (_selectedProposalId == null || _selectedPlanningId == null) {
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
      // Sélectionner l'astreinte spécifique (planningId)
      await _exchangeService.selectProposal(
        requestId: widget.request.id,
        proposalId: _selectedProposalId!,
        planningId: _selectedPlanningId!,
        initiatorId: widget.initiatorId,
        stationId: widget.stationId,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✓ Astreinte sélectionnée ! En attente de validation par les chefs d\'équipe',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalCount = _individualProposals.length;

    return AlertDialog(
      title: Text('$totalCount astreinte(s) proposée(s)'),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sélectionnez l\'astreinte que vous souhaitez échanger :',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...List.generate(_individualProposals.length, (index) {
                      final individual = _individualProposals[index];
                      final isSelected =
                          _selectedProposalId == individual.proposalId &&
                          _selectedPlanningId == individual.planningId;
                      // IMPORTANT: Vérifier si CE planning spécifique est refusé (pas toute la proposition)
                      final isRejected = individual.rejectedPlanningIds
                          .contains(individual.planningId);

                      return Card(
                        color: isRejected
                            ? Colors.grey[200]
                            : isSelected
                            ? Colors.purple[50]
                            : Colors.white,
                        margin: const EdgeInsets.only(bottom: 12),
                        child: RadioListTile<String>(
                          value:
                              '${individual.proposalId}_${individual.planningId}',
                          groupValue:
                              _selectedProposalId != null &&
                                  _selectedPlanningId != null
                              ? '${_selectedProposalId}_$_selectedPlanningId'
                              : null,
                          onChanged: isRejected
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedProposalId = individual.proposalId;
                                    _selectedPlanningId = individual.planningId;
                                  });
                                },
                          title: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Équipe ${individual.proposerTeamId}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: isRejected
                                            ? Colors.grey
                                            : Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      individual.proposerName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                        color: isRejected
                                            ? Colors.grey
                                            : Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isRejected)
                                GestureDetector(
                                  onTap: () => _showRejectionReason(individual),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red[100],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.error_outline,
                                          size: 14,
                                          color: Colors.red,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Refusée',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: isRejected ? Colors.grey : Colors.blue,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Du ${_formatDateTime(individual.planning.startTime)}\nAu ${_formatDateTime(individual.planning.endTime)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isRejected
                                          ? Colors.grey
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: Colors.orange,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Une fois sélectionnée, les chefs d\'équipe devront valider l\'échange.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                              ),
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
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed:
              _isSubmitting ||
                  _selectedProposalId == null ||
                  _selectedPlanningId == null
              ? null
              : _submitSelection,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
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
              : const Text('Confirmer mon choix'),
        ),
      ],
    );
  }
}
