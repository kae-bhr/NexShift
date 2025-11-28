import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:uuid/uuid.dart';

/// Dialog affichant une demande de remplacement
/// Permet à l'utilisateur de répondre (disponible / indisponible)
class ReplacementRequestDialog extends StatefulWidget {
  final String requestId;
  final String currentUserId;

  const ReplacementRequestDialog({
    super.key,
    required this.requestId,
    required this.currentUserId,
  });

  @override
  State<ReplacementRequestDialog> createState() =>
      _ReplacementRequestDialogState();
}

class _ReplacementRequestDialogState extends State<ReplacementRequestDialog> {
  final _notificationService = ReplacementNotificationService();
  final _userRepository = UserRepository();
  final _subshiftRepository = SubshiftRepository();
  final _planningRepository = PlanningRepository();
  bool _isLoading = true;
  bool _isResponding = false;
  ReplacementRequest? _request;
  String? _requesterName;
  String? _error;
  bool _canAccept = true;
  String? _cannotAcceptReason;

  // Time range selection for partial replacement
  DateTime? _selectedStartTime;
  DateTime? _selectedEndTime;

  @override
  void initState() {
    super.initState();
    _loadRequest();
  }

  Future<void> _loadRequest() async {
    try {
      // Charger la demande depuis Firestore
      final requestDoc = await _notificationService.firestore
          .collection('replacementRequests')
          .doc(widget.requestId)
          .get();

      if (!requestDoc.exists) {
        setState(() {
          _error = 'Demande introuvable';
          _isLoading = false;
        });
        return;
      }

      final request = ReplacementRequest.fromJson(requestDoc.data()!);

      // Vérifier que la demande est toujours en attente
      if (request.status != ReplacementRequestStatus.pending) {
        setState(() {
          _error = 'Cette demande a déjà été traitée';
          _isLoading = false;
        });
        return;
      }

      // Charger le nom du demandeur
      final requester = await _userRepository.getById(request.requesterId);
      final requesterName = requester != null
          ? '${requester.firstName} ${requester.lastName}'
          : 'Inconnu';

      // Vérifier si l'utilisateur peut accepter le remplacement
      bool canAccept = true;
      String? cannotAcceptReason;

      // 1. Vérifier que la date de début n'est pas dans le passé
      if (request.startTime.isBefore(DateTime.now())) {
        canAccept = false;
        cannotAcceptReason = 'Cette demande de remplacement a déjà commencé.';
      }
      // 2. Vérifier que l'utilisateur n'est pas le demandeur
      else if (widget.currentUserId == request.requesterId) {
        canAccept = false;
        cannotAcceptReason =
            'Vous ne pouvez pas accepter votre propre demande de remplacement.';
      }
      // 3. Vérifier la disponibilité sur la période
      else {
        try {
          // 2a. Vérifier si l'utilisateur est en astreinte durant cette période
          final allPlannings = await _planningRepository.getAll();
          final isOnDuty = allPlannings.any((planning) {
            // Vérifier si l'utilisateur est dans l'astreinte
            if (!planning.agentsId.contains(widget.currentUserId)) return false;

            // Vérifier si les périodes se chevauchent
            final overlapStart = planning.startTime.isBefore(request.endTime);
            final overlapEnd = planning.endTime.isAfter(request.startTime);
            return overlapStart && overlapEnd;
          });

          if (isOnDuty) {
            canAccept = false;
            cannotAcceptReason = 'Vous êtes en astreinte durant cette période.';
          }

          // 2b. Vérifier si l'utilisateur a déjà un remplacement qui chevauche cette période
          if (canAccept) {
            final existingSubshifts = await _subshiftRepository.getAll();
            final hasConflict = existingSubshifts.any((subshift) {
              // Vérifier si l'utilisateur est le remplaçant ou le remplacé
              final isInvolved =
                  subshift.replacerId == widget.currentUserId ||
                  subshift.replacedId == widget.currentUserId;
              if (!isInvolved) return false;

              // Vérifier si les périodes se chevauchent
              final overlapStart = subshift.start.isBefore(request.endTime);
              final overlapEnd = subshift.end.isAfter(request.startTime);
              return overlapStart && overlapEnd;
            });

            if (hasConflict) {
              canAccept = false;
              cannotAcceptReason =
                  'Vous avez déjà un remplacement programmé durant cette période.';
            }
          }
        } catch (e) {
          debugPrint('Error checking for availability: $e');
          // En cas d'erreur, on autorise quand même (pour ne pas bloquer complètement)
        }
      }

      setState(() {
        _request = request;
        _requesterName = requesterName;
        _canAccept = canAccept;
        _cannotAcceptReason = cannotAcceptReason;
        _isLoading = false;
        // Initialiser avec la plage complète par défaut
        _selectedStartTime = request.startTime;
        _selectedEndTime = request.endTime;
      });
    } catch (e) {
      setState(() {
        _error = 'Erreur lors du chargement: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _acceptRequest() async {
    if (_request == null) return;

    setState(() => _isResponding = true);

    try {
      // Re-vérifier que la demande est toujours pending (protection contre race condition)
      final freshRequestDoc = await _notificationService.firestore
          .collection('replacementRequests')
          .doc(widget.requestId)
          .get();

      if (!freshRequestDoc.exists) {
        setState(() {
          _error = 'Cette demande n\'existe plus';
          _isResponding = false;
        });
        return;
      }

      final freshStatus = freshRequestDoc.data()?['status'] as String?;
      if (freshStatus != 'pending') {
        setState(() {
          _error = 'Cette demande a déjà été acceptée par quelqu\'un d\'autre';
          _isResponding = false;
        });
        return;
      }

      // Re-vérifier la disponibilité de l'utilisateur (peut avoir changé depuis l'ouverture du dialog)
      final actualStartTime = _selectedStartTime ?? _request!.startTime;
      final actualEndTime = _selectedEndTime ?? _request!.endTime;

      // Vérifier les conflits avec les plannings
      final allPlannings = await _planningRepository.getAll();
      final isOnDuty = allPlannings.any((planning) {
        if (!planning.agentsId.contains(widget.currentUserId)) return false;
        final overlapStart = planning.startTime.isBefore(actualEndTime);
        final overlapEnd = planning.endTime.isAfter(actualStartTime);
        return overlapStart && overlapEnd;
      });

      if (isOnDuty) {
        setState(() {
          _error = 'Vous êtes en astreinte durant cette période.';
          _isResponding = false;
        });
        return;
      }

      // Vérifier les conflits avec les subshifts existants
      final existingSubshifts = await _subshiftRepository.getAll();
      final hasConflict = existingSubshifts.any((subshift) {
        final isInvolved =
            subshift.replacerId == widget.currentUserId ||
            subshift.replacedId == widget.currentUserId;
        if (!isInvolved) return false;
        final overlapStart = subshift.start.isBefore(actualEndTime);
        final overlapEnd = subshift.end.isAfter(actualStartTime);
        return overlapStart && overlapEnd;
      });

      if (hasConflict) {
        setState(() {
          _error = 'Vous avez déjà un remplacement programmé durant cette période.';
          _isResponding = false;
        });
        return;
      }

      // Pour les demandes de disponibilité, on marque simplement comme accepté
      if (_request!.requestType == RequestType.availability) {
        await _notificationService.acceptReplacementRequest(
          requestId: widget.requestId,
          replacerId: widget.currentUserId,
          acceptedStartTime: _selectedStartTime,
          acceptedEndTime: _selectedEndTime,
        );

        // Mettre à jour le statut de la demande
        await _notificationService.firestore
            .collection('replacementRequests')
            .doc(widget.requestId)
            .update({
              'status': ReplacementRequestStatus.accepted
                  .toString()
                  .split('.')
                  .last,
              'replacerId': widget.currentUserId,
              'acceptedAt': FieldValue.serverTimestamp(),
            });

        if (mounted) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Disponibilité confirmée'),
              backgroundColor: Colors.green,
            ),
          );
        }

        return;
      }
      // Pour les remplacements classiques, gérer avec subshift
      else {
        // Valider la plage horaire sélectionnée
        if (_selectedStartTime == null || _selectedEndTime == null) {
          setState(() {
            _error = 'Veuillez sélectionner une plage horaire';
            _isResponding = false;
          });
          return;
        }

        if (_selectedStartTime!.isAfter(_selectedEndTime!) ||
            _selectedStartTime!.isBefore(_request!.startTime) ||
            _selectedEndTime!.isAfter(_request!.endTime)) {
          setState(() {
            _error = 'Plage horaire invalide';
            _isResponding = false;
          });
          return;
        }

        // Créer le subshift avec la plage sélectionnée
        final subshift = Subshift(
          id: const Uuid().v4(),
          planningId: _request!.planningId,
          start: _selectedStartTime!,
          end: _selectedEndTime!,
          replacedId: _request!.requesterId,
          replacerId: widget.currentUserId,
        );

        await SubshiftRepository().save(subshift);

        // Accepter la demande (met à jour le statut et envoie les notifications)
        // Passer les heures sélectionnées pour gérer les remplacements partiels
        await _notificationService.acceptReplacementRequest(
          requestId: widget.requestId,
          replacerId: widget.currentUserId,
          acceptedStartTime: _selectedStartTime,
          acceptedEndTime: _selectedEndTime,
        );

        if (mounted) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Remplacement accepté'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Erreur lors de l\'acceptation: $e';
        _isResponding = false;
      });
    }
  }

  Future<void> _declineRequest() async {
    if (_request == null) return;

    try {
      setState(() => _isResponding = true);

      // Enregistrer le refus dans Firestore
      final docRef = await FirebaseFirestore.instance
          .collection('replacementRequestDeclines')
          .add({
        'requestId': _request!.id,
        'userId': widget.currentUserId,
        'declinedAt': Timestamp.now(),
      });

      debugPrint(
        '✅ Decline recorded for request ${_request!.id} by user ${widget.currentUserId} (docId: ${docRef.id})',
      );

      if (mounted) {
        Navigator.of(context).pop(false);
      }
    } catch (e) {
      debugPrint('❌ Error recording decline: $e');
      debugPrint('  Stack trace: ${StackTrace.current}');
      // Même en cas d'erreur, on ferme le dialog
      if (mounted) {
        Navigator.of(context).pop(false);
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _selectStartTime() async {
    if (_request == null) return;

    final date = await showDatePicker(
      context: context,
      initialDate: _selectedStartTime ?? _request!.startTime,
      firstDate: _request!.startTime,
      lastDate: _request!.endTime,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _selectedStartTime ?? _request!.startTime,
      ),
    );
    if (time == null || !mounted) return;

    final newStart = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    // Vérifier que la nouvelle heure de début est valide
    if (newStart.isBefore(_request!.startTime) ||
        newStart.isAfter(_request!.endTime)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Heure de début invalide')));
      return;
    }

    setState(() {
      _selectedStartTime = newStart;
      // Ajuster l'heure de fin si nécessaire
      if (_selectedEndTime != null && newStart.isAfter(_selectedEndTime!)) {
        _selectedEndTime = _request!.endTime;
      }
    });
  }

  Future<void> _selectEndTime() async {
    if (_request == null) return;

    final date = await showDatePicker(
      context: context,
      initialDate: _selectedEndTime ?? _request!.endTime,
      firstDate: _selectedStartTime ?? _request!.startTime,
      lastDate: _request!.endTime,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _selectedEndTime ?? _request!.endTime,
      ),
    );
    if (time == null || !mounted) return;

    final newEnd = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    // Vérifier que la nouvelle heure de fin est valide
    if (newEnd.isAfter(_request!.endTime) ||
        newEnd.isBefore(_request!.startTime)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Heure de fin invalide')));
      return;
    }

    setState(() {
      _selectedEndTime = newEnd;
      // Ajuster l'heure de début si nécessaire
      if (_selectedStartTime != null && newEnd.isBefore(_selectedStartTime!)) {
        _selectedStartTime = _request!.startTime;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAvailabilityRequest =
        _request?.requestType == RequestType.availability;

    return AlertDialog(
      title: Text(
        isAvailabilityRequest
            ? 'Demande de disponibilité'
            : 'Demande de remplacement',
      ),
      content: _isLoading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : _error != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ],
            )
          : _request == null
          ? const Text('Aucune information disponible')
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Demandeur
                Row(
                  children: [
                    const Icon(Icons.person, size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _requesterName ?? 'Inconnu',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isAvailabilityRequest
                      ? 'recherche un agent disponible'
                      : 'recherche un remplaçant',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),

                // Période
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16),
                          const SizedBox(width: 8),
                          const Text(
                            'Période:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('Du: '),
                          Text(
                            _formatDateTime(_request!.startTime),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text('Au: '),
                          Text(
                            _formatDateTime(_request!.endTime),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Sélection de la plage horaire (uniquement pour les remplacements)
                if (!isAvailabilityRequest) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule,
                              size: 16,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Votre disponibilité :',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Bouton pour modifier l'heure de début
                        InkWell(
                          onTap: _selectStartTime,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Text('Du: '),
                                    Text(
                                      _formatDateTime(
                                        _selectedStartTime ??
                                            _request!.startTime,
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: Colors.green.shade700,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Bouton pour modifier l'heure de fin
                        InkWell(
                          onTap: _selectEndTime,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Text('Au: '),
                                    Text(
                                      _formatDateTime(
                                        _selectedEndTime ?? _request!.endTime,
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: Colors.green.shade700,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tapez pour modifier les horaires',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Station et équipe
                if (_request!.station.isNotEmpty)
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _request!.station,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                if (_request!.team != null && _request!.team!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.group, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          'Équipe ${_request!.team}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),

                // Avertissement si l'utilisateur ne peut pas accepter
                if (!_canAccept && _cannotAcceptReason != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300),
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
                            _cannotAcceptReason!,
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
      actions: _error != null
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
            ]
          : _isResponding
          ? [
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              ),
            ]
          : [
              // Bouton Indisponible
              TextButton(
                onPressed: _declineRequest,
                child: const Text('Indisponible'),
              ),

              // Bouton Je suis disponible
              FilledButton(
                onPressed: _canAccept ? _acceptRequest : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _canAccept ? Colors.green : Colors.grey,
                ),
                child: const Text('Je suis disponible !'),
              ),
            ],
    );
  }
}

/// Fonction helper pour afficher le dialog
Future<bool?> showReplacementRequestDialog(
  BuildContext context, {
  required String requestId,
  required String currentUserId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ReplacementRequestDialog(
      requestId: requestId,
      currentUserId: currentUserId,
    ),
  );
}
