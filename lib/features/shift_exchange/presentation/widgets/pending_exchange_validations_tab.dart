import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_proposal_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_request_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/services/shift_exchange_service.dart';
import 'package:nexshift_app/core/repositories/shift_exchange_repository.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';

/// Onglet affichant les propositions d'échange en attente de validation
/// Visible uniquement pour les chefs d'équipe et leaders
class PendingExchangeValidationsTab extends StatefulWidget {
  const PendingExchangeValidationsTab({super.key});

  @override
  State<PendingExchangeValidationsTab> createState() =>
      _PendingExchangeValidationsTabState();
}

class _PendingExchangeValidationsTabState
    extends State<PendingExchangeValidationsTab> {
  final _exchangeService = ShiftExchangeService();
  final _exchangeRepository = ShiftExchangeRepository();
  final _planningRepository = PlanningRepository();

  List<Map<String, dynamic>> _pendingProposalsWithRequests = [];
  Map<String, List<Planning>> _proposalPlannings = {}; // proposalId → plannings
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPendingProposals();
  }

  Future<void> _loadPendingProposals() async {
    final currentUser = userNotifier.value;
    if (currentUser == null) return;

    // Vérifier que l'utilisateur est chef ou leader
    if (currentUser.status != 'chief' && currentUser.status != 'leader') {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Récupérer les propositions en attente pour l'équipe du chef
      final proposals = await _exchangeService.getPendingProposalsForLeader(
        teamId: currentUser.team,
        stationId: currentUser.station,
      );

      // Pour chaque proposition, récupérer la demande associée et les plannings
      final proposalsWithRequests = <Map<String, dynamic>>[];
      final planningsMap = <String, List<Planning>>{};

      for (final proposal in proposals) {
        final request = await _exchangeRepository.getRequestById(
          proposal.requestId,
          stationId: currentUser.station,
        );
        if (request != null) {
          proposalsWithRequests.add({
            'proposal': proposal,
            'request': request,
          });

          // Charger les plannings de la proposition
          final List<Planning> plannings = [];
          for (final planningId in proposal.proposedPlanningIds) {
            final planning = await _planningRepository.getById(
              planningId,
              stationId: currentUser.station,
            );
            if (planning != null) {
              plannings.add(planning);
            }
          }
          planningsMap[proposal.id] = plannings;
        }
      }

      // Trier par date de création (plus anciennes en premier)
      proposalsWithRequests.sort((a, b) {
        final propA = a['proposal'] as ShiftExchangeProposal;
        final propB = b['proposal'] as ShiftExchangeProposal;
        return propA.createdAt.compareTo(propB.createdAt);
      });

      setState(() {
        _pendingProposalsWithRequests = proposalsWithRequests;
        _proposalPlannings = planningsMap;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur de chargement: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _validateProposal(ShiftExchangeProposal proposal) async {
    final currentUser = userNotifier.value;
    if (currentUser == null) return;

    try {
      await _exchangeService.validateProposal(
        proposalId: proposal.id,
        leaderId: currentUser.id,
        teamId: currentUser.team,
        stationId: currentUser.station,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Proposition validée'),
            backgroundColor: Colors.green,
          ),
        );
        _loadPendingProposals(); // Recharger la liste
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectProposal(ShiftExchangeProposal proposal) async {
    final currentUser = userNotifier.value;
    if (currentUser == null) return;

    // Demander le motif de refus
    final TextEditingController commentController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Refuser la proposition'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Veuillez indiquer le motif du refus (obligatoire) :',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: commentController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Motif du refus...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final comment = commentController.text.trim();
      if (comment.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Le motif de refus est obligatoire'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      try {
        await _exchangeService.rejectProposal(
          proposalId: proposal.id,
          leaderId: currentUser.id,
          teamId: currentUser.team,
          comment: comment,
          stationId: currentUser.station,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Proposition refusée'),
              backgroundColor: Colors.orange,
            ),
          );
          _loadPendingProposals(); // Recharger la liste
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pendingProposalsWithRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Aucune validation en attente',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingProposalsWithRequests.length,
      itemBuilder: (context, index) {
        final data = _pendingProposalsWithRequests[index];
        final proposal = data['proposal'] as ShiftExchangeProposal;
        final request = data['request'] as ShiftExchangeRequest;

        return _buildProposalCard(proposal, request);
      },
    );
  }

  Widget _buildProposalCard(
    ShiftExchangeProposal proposal,
    ShiftExchangeRequest request,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Titre
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'EN ATTENTE DE VALIDATION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Section 1: Demande initiale
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
                        '${request.initiatorName} propose',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDateTime(request.initiatorStartTime),
                    style: const TextStyle(fontSize: 13),
                  ),
                  Text(
                    '→ ${_formatDateTime(request.initiatorEndTime)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.swap_horiz, color: Colors.grey),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 12),

            // Section 2: Proposition(s)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person, size: 16, color: Colors.green),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${proposal.proposerName} propose en échange',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                      if (proposal.isProposerChief)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Chef',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...(_proposalPlannings[proposal.id] ?? []).map((planning) =>
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time, size: 14, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            '${_formatDateTime(planning.startTime)} → ${_formatDateTime(planning.endTime)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // États de validation par équipe
            const SizedBox(height: 12),
            const Text(
              'État de validation par équipe :',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            ...proposal.teamValidationStates.entries.map((entry) {
              final teamId = entry.key;
              final state = entry.value;

              Color stateColor;
              IconData stateIcon;
              String stateText;

              switch (state) {
                case TeamValidationState.pending:
                  stateColor = Colors.orange;
                  stateIcon = Icons.hourglass_empty;
                  stateText = 'En attente';
                  break;
                case TeamValidationState.validatedTemporarily:
                  stateColor = Colors.green;
                  stateIcon = Icons.check_circle;
                  stateText = 'Validé (au moins 1 chef)';
                  break;
                case TeamValidationState.autoValidated:
                  stateColor = Colors.purple;
                  stateIcon = Icons.verified;
                  stateText = 'Auto-validé (proposeur chef)';
                  break;
                case TeamValidationState.rejected:
                  stateColor = Colors.red;
                  stateIcon = Icons.cancel;
                  stateText = 'Refusé';
                  break;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: stateColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: stateColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(stateIcon, size: 16, color: stateColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Équipe $teamId',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: stateColor,
                            ),
                          ),
                          Text(
                            stateText,
                            style: TextStyle(
                              fontSize: 11,
                              color: stateColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 16),

            // Boutons d'action
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rejectProposal(proposal),
                    icon: const Icon(Icons.close),
                    label: const Text('Refuser'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _validateProposal(proposal),
                    icon: const Icon(Icons.check),
                    label: const Text('Valider'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Validation multi-chefs :',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '• Une équipe est validée dès qu\'UN chef accepte\n'
                          '• Un refus annule toute validation antérieure\n'
                          '• L\'échange est finalisé quand les 2 équipes sont validées',
                          style: TextStyle(fontSize: 10, color: Colors.blue[800]),
                        ),
                      ],
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
