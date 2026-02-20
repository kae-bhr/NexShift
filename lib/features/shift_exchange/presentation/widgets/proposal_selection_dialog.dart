import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_proposal_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_request_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/services/shift_exchange_service.dart';

/// Calcule la durée en minutes
int _durationMinutes(DateTime start, DateTime end) =>
    end.difference(start).inMinutes;

/// Formate une différence de durée en format compact
String _formatDurationDiff(int diffMinutes) {
  if (diffMinutes == 0) return '';
  final sign = diffMinutes > 0 ? '+' : '-';
  final abs = diffMinutes.abs();
  if (abs >= 24 * 60) {
    final days = abs ~/ (24 * 60);
    final remainHours = (abs % (24 * 60)) ~/ 60;
    if (remainHours > 0) return '$sign${days}j${remainHours}h';
    return '$sign${days}j';
  } else {
    final hours = abs ~/ 60;
    final remainMin = abs % 60;
    if (hours == 0) return '$sign${remainMin}min';
    if (remainMin > 0)
      return '$sign${hours}h${remainMin.toString().padLeft(2, '0')}';
    return '$sign${hours}h';
  }
}

/// Formate une durée en format lisible
String _formatDuration(int minutes) {
  if (minutes >= 24 * 60) {
    final days = minutes ~/ (24 * 60);
    final remainHours = (minutes % (24 * 60)) ~/ 60;
    if (remainHours > 0) return '${days}j${remainHours}h';
    return '${days}j';
  } else {
    final hours = minutes ~/ 60;
    final remainMin = minutes % 60;
    if (hours == 0) return '${remainMin}min';
    if (remainMin > 0)
      return '${hours}h${remainMin.toString().padLeft(2, '0')}';
    return '${hours}h';
  }
}

/// Structure pour représenter une astreinte individuelle proposée
class _IndividualProposal {
  final String proposalId;
  final String proposerId;
  final String planningId;
  final Planning planning;
  final String proposerName;
  final String proposerTeamId;
  final ShiftExchangeProposalStatus status;
  final Map<String, LeaderValidation> leaderValidations;
  final List<String> rejectedPlanningIds;

  _IndividualProposal({
    required this.proposalId,
    required this.proposerId,
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
  bool _showDifferentDurations = false;

  int get _referenceDuration => _durationMinutes(
    widget.request.initiatorStartTime,
    widget.request.initiatorEndTime,
  );

  @override
  void initState() {
    super.initState();
    _loadIndividualProposals();
  }

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
                proposerId: proposal.proposerId,
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
      debugPrint('[ProposalSelection] ERROR: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<_IndividualProposal> get _filteredProposals {
    if (_showDifferentDurations) return _individualProposals;
    return _individualProposals.where((p) {
      final dur = _durationMinutes(p.planning.startTime, p.planning.endTime);
      return dur == _referenceDuration;
    }).toList();
  }

  int get _differentDurationCount {
    return _individualProposals.where((p) {
      final dur = _durationMinutes(p.planning.startTime, p.planning.endTime);
      return dur != _referenceDuration;
    }).length;
  }

  void _showRejectionReason(_IndividualProposal individual) {
    final rejections = individual.leaderValidations.entries
        .where((e) => e.value.approved == false)
        .toList();

    if (rejections.isEmpty) return;

    final rejection = rejections.first.value;
    final comment = rejection.comment ?? 'Aucun motif spécifié';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[400], size: 22),
            const SizedBox(width: 8),
            const Text('Proposition refusée', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Motif du refus :',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(comment, style: const TextStyle(fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
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

    setState(() => _isSubmitting = true);

    try {
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
              'Astreinte sélectionnée ! En attente de validation par les chefs d\'équipe.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final refDuration = _referenceDuration;
    final filteredProposals = _filteredProposals;
    final df = DateFormat('dd/MM HH:mm');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_individualProposals.length} astreinte${_individualProposals.length > 1 ? 's' : ''} proposée${_individualProposals.length > 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Carte de référence (mon astreinte)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: colorScheme.primary.withValues(
                            alpha: 0.1,
                          ),
                          child: Icon(
                            Icons.event,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mon astreinte',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${df.format(widget.request.initiatorStartTime)} → ${df.format(widget.request.initiatorEndTime)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _formatDuration(refDuration),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Contenu scrollable ──
            Flexible(
              child: _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sélectionnez l\'astreinte que vous souhaitez échanger :',
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Checkbox filtre durée
                          if (_differentDurationCount > 0)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _showDifferentDurations =
                                      !_showDifferentDurations;
                                  if (!_showDifferentDurations) {
                                    // Vérifier si la sélection est toujours visible
                                    final visibleIds = _filteredProposals
                                        .map(
                                          (p) =>
                                              '${p.proposalId}_${p.planningId}',
                                        )
                                        .toSet();
                                    final currentKey =
                                        _selectedProposalId != null &&
                                            _selectedPlanningId != null
                                        ? '${_selectedProposalId}_$_selectedPlanningId'
                                        : null;
                                    if (currentKey != null &&
                                        !visibleIds.contains(currentKey)) {
                                      _selectedProposalId = null;
                                      _selectedPlanningId = null;
                                    }
                                  }
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Checkbox(
                                        value: _showDifferentDurations,
                                        activeColor: colorScheme.primary,
                                        checkColor: colorScheme.onPrimary,
                                        side: BorderSide(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                        onChanged: (v) {
                                          setState(() {
                                            _showDifferentDurations =
                                                v ?? false;
                                          });
                                        },
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Afficher les durées différentes ($_differentDurationCount)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Liste des propositions
                          ...filteredProposals.map((individual) {
                            final isSelected =
                                _selectedProposalId == individual.proposalId &&
                                _selectedPlanningId == individual.planningId;
                            final isRejected = individual.rejectedPlanningIds
                                .contains(individual.planningId);
                            final planDuration = _durationMinutes(
                              individual.planning.startTime,
                              individual.planning.endTime,
                            );
                            final diffMinutes = planDuration - refDuration;
                            final isSameDuration = diffMinutes == 0;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Material(
                                color: isRejected
                                    ? Colors.grey[100]
                                    : isSelected
                                    ? colorScheme.primary.withValues(
                                        alpha: 0.08,
                                      )
                                    : colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: isRejected
                                      ? () => _showRejectionReason(individual)
                                      : () {
                                          setState(() {
                                            _selectedProposalId =
                                                individual.proposalId;
                                            _selectedPlanningId =
                                                individual.planningId;
                                          });
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        // Radio button
                                        if (!isRejected)
                                          Icon(
                                            isSelected
                                                ? Icons.radio_button_checked
                                                : Icons.radio_button_off,
                                            color: isSelected
                                                ? colorScheme.primary
                                                : Colors.grey[400],
                                            size: 22,
                                          )
                                        else
                                          Icon(
                                            Icons.block,
                                            color: Colors.grey[400],
                                            size: 22,
                                          ),
                                        const SizedBox(width: 10),

                                        // Contenu
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      'Équipe ${individual.proposerTeamId}',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 14,
                                                        color: isRejected
                                                            ? Colors.grey
                                                            : null,
                                                      ),
                                                    ),
                                                  ),
                                                  if (isRejected)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.red[50],
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        'Refusée',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color:
                                                              Colors.red[400],
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 1),
                                              Text(
                                                individual.proposerName.trim().isNotEmpty
                                                    ? individual.proposerName
                                                    : 'Agent ${individual.proposerId}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isRejected
                                                      ? Colors.grey
                                                      : colorScheme
                                                            .onSurfaceVariant,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${df.format(individual.planning.startTime)} → ${df.format(individual.planning.endTime)}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isRejected
                                                      ? Colors.grey
                                                      : colorScheme
                                                            .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Indicateur de durée
                                        if (!isRejected)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSameDuration
                                                  ? Colors.green.withValues(
                                                      alpha: 0.1,
                                                    )
                                                  : Colors.orange.withValues(
                                                      alpha: 0.1,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isSameDuration
                                                  ? '='
                                                  : _formatDurationDiff(
                                                      diffMinutes,
                                                    ),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: isSameDuration
                                                    ? Colors.green[700]
                                                    : Colors.orange[800],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),

                          const SizedBox(height: 12),

                          // Info box
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: Colors.orange[700],
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Une fois sélectionnée, les chefs d\'équipe devront valider l\'échange.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange[800],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
            ),

            // ── Actions ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          _isSubmitting ||
                              _selectedProposalId == null ||
                              _selectedPlanningId == null
                          ? null
                          : _submitSelection,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Confirmer'),
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
