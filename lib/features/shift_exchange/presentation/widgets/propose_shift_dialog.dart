import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_request_model.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/services/shift_exchange_service.dart';

/// Calcule la durée d'un planning en minutes
int _durationMinutes(DateTime start, DateTime end) =>
    end.difference(start).inMinutes;

/// Formate une différence de durée en format compact (+1j, -4h, etc.)
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
    if (remainMin > 0) return '$sign${hours}h${remainMin.toString().padLeft(2, '0')}';
    return '$sign${hours}h';
  }
}

/// Formate une durée en format lisible (ex: "11h", "1j", "1j12h")
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
    if (remainMin > 0) return '${hours}h${remainMin.toString().padLeft(2, '0')}';
    return '${hours}h';
  }
}

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
  final Set<String> _selectedPlanningIds = {};
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _showDifferentDurations = false;

  /// Durée de référence (astreinte de l'initiateur) en minutes
  int get _referenceDuration => _durationMinutes(
        widget.request.initiatorStartTime,
        widget.request.initiatorEndTime,
      );

  @override
  void initState() {
    super.initState();
    _loadUserPlannings();
  }

  Future<void> _loadUserPlannings() async {
    try {
      final allPlannings = await _planningRepository.getForUser(
        widget.userId,
        stationId: widget.stationId,
      );

      final now = DateTime.now();
      final futurePlannings = allPlannings
          .where((p) {
            final startDate = DateTime(
              p.startTime.year,
              p.startTime.month,
              p.startTime.day,
            );
            final today = DateTime(now.year, now.month, now.day);
            return (startDate.isAfter(today) ||
                    startDate.isAtSameMomentAs(today)) &&
                p.station == widget.stationId;
          })
          .toList();

      futurePlannings.sort((a, b) => a.startTime.compareTo(b.startTime));

      if (mounted) {
        setState(() {
          _futureUserPlannings = futurePlannings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors du chargement: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Retourne la liste filtrée selon le toggle de durée
  List<Planning> get _filteredPlannings {
    if (_showDifferentDurations) return _futureUserPlannings;
    return _futureUserPlannings.where((p) {
      final dur = _durationMinutes(p.startTime, p.endTime);
      return dur == _referenceDuration;
    }).toList();
  }

  int get _differentDurationCount {
    return _futureUserPlannings.where((p) {
      final dur = _durationMinutes(p.startTime, p.endTime);
      return dur != _referenceDuration;
    }).length;
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

    setState(() => _isSubmitting = true);

    try {
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
    final filteredPlannings = _filteredPlannings;
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
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Proposer mon astreinte',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  // Carte initiateur
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
                          backgroundColor:
                              colorScheme.primary.withValues(alpha: 0.1),
                          child: Icon(
                            Icons.swap_horiz,
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
                                '${widget.request.initiatorName.trim().isNotEmpty ? widget.request.initiatorName : 'Agent ${widget.request.initiatorId}'} propose',
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
                        // Badge durée
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'En échange, proposez une ou plusieurs de vos astreintes :',
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
                            _showDifferentDurations = !_showDifferentDurations;
                            if (!_showDifferentDurations) {
                              final visibleIds =
                                  _filteredPlannings.map((p) => p.id).toSet();
                              _selectedPlanningIds
                                  .retainWhere((id) => visibleIds.contains(id));
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
                                  side: BorderSide(color: colorScheme.onSurfaceVariant),
                                  onChanged: (v) {
                                    setState(() {
                                      _showDifferentDurations = v ?? false;
                                      if (!_showDifferentDurations) {
                                        final visibleIds = _filteredPlannings
                                            .map((p) => p.id)
                                            .toSet();
                                        _selectedPlanningIds.retainWhere(
                                          (id) => visibleIds.contains(id),
                                        );
                                      }
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

                    // Liste des plannings
                    if (_isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (filteredPlannings.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            Icon(Icons.event_busy,
                                size: 40, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              _futureUserPlannings.isEmpty
                                  ? 'Aucune astreinte future disponible'
                                  : 'Aucune astreinte de même durée',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...filteredPlannings.map((planning) {
                        final isSelected =
                            _selectedPlanningIds.contains(planning.id);
                        final planDuration = _durationMinutes(
                          planning.startTime,
                          planning.endTime,
                        );
                        final diffMinutes = planDuration - refDuration;
                        final isSameDuration = diffMinutes == 0;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Material(
                            color: isSelected
                                ? colorScheme.primary.withValues(alpha: 0.08)
                                : colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedPlanningIds.remove(planning.id);
                                  } else {
                                    _selectedPlanningIds.add(planning.id);
                                  }
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Équipe ${planning.team}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${df.format(planning.startTime)} → ${df.format(planning.endTime)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Indicateur de durée
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSameDuration
                                            ? Colors.green
                                                .withValues(alpha: 0.1)
                                            : Colors.orange
                                                .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isSameDuration
                                            ? '='
                                            : _formatDurationDiff(diffMinutes),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isSameDuration
                                              ? Colors.green[700]
                                              : Colors.orange[800],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Icône check
                                    Icon(
                                      isSelected
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      color: isSelected
                                          ? colorScheme.primary
                                          : Colors.grey[400],
                                      size: 22,
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
                          Icon(Icons.info_outline,
                              size: 18, color: Colors.orange[700]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'L\'initiateur devra sélectionner votre proposition avant validation par les chefs.',
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
                      onPressed: _isSubmitting || _selectedPlanningIds.isEmpty
                          ? null
                          : _submitProposal,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _selectedPlanningIds.length > 1
                                  ? 'Proposer (${_selectedPlanningIds.length})'
                                  : 'Proposer',
                            ),
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
