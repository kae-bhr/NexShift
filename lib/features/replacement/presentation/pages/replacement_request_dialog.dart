import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';

/// Dialog affichant une demande de remplacement
/// Permet à l'utilisateur de répondre (disponible / indisponible)
class ReplacementRequestDialog extends StatefulWidget {
  final String requestId;
  final String currentUserId;
  final String stationId;

  const ReplacementRequestDialog({
    super.key,
    required this.requestId,
    required this.currentUserId,
    required this.stationId,
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

  // Helper methods pour les chemins de collections
  String _getReplacementRequestsPath() {
    if (EnvironmentConfig.useStationSubcollections && widget.stationId.isNotEmpty) {
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null && sdisId.isNotEmpty) {
        return 'sdis/$sdisId/stations/${widget.stationId}/replacements/automatic/replacementRequests';
      }
      return 'stations/${widget.stationId}/replacements/automatic/replacementRequests';
    }
    return 'replacementRequests';
  }

  String _getReplacementRequestDeclinesPath() {
    if (EnvironmentConfig.useStationSubcollections && widget.stationId.isNotEmpty) {
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null && sdisId.isNotEmpty) {
        return 'sdis/$sdisId/stations/${widget.stationId}/replacements/automatic/replacementRequestDeclines';
      }
      return 'stations/${widget.stationId}/replacements/automatic/replacementRequestDeclines';
    }
    return 'replacementRequestDeclines';
  }

  @override
  void initState() {
    super.initState();
    _loadRequest();
  }

  Future<void> _loadRequest() async {
    try {
      // Charger la demande depuis Firestore
      final requestDoc = await _notificationService.firestore
          .collection(_getReplacementRequestsPath())
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
          ? requester.displayName
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
      // 3. Vérifier que l'utilisateur n'a pas déjà refusé cette demande
      else {
        final declinesPath = _getReplacementRequestDeclinesPath();
        final declineSnapshot = await _notificationService.firestore
            .collection(declinesPath)
            .where('requestId', isEqualTo: widget.requestId)
            .where('userId', isEqualTo: widget.currentUserId)
            .limit(1)
            .get();

        if (declineSnapshot.docs.isNotEmpty) {
          canAccept = false;
          cannotAcceptReason = 'Vous avez déjà refusé cette demande de remplacement.';
        }
      }
      // 4. Vérifier que l'utilisateur n'a pas déjà une acceptation en attente
      if (canAccept) {
        final acceptancesPath = EnvironmentConfig.useStationSubcollections && widget.stationId.isNotEmpty
            ? (SDISContext().currentSDISId != null && SDISContext().currentSDISId!.isNotEmpty
                ? 'sdis/${SDISContext().currentSDISId}/stations/${widget.stationId}/manualReplacementAcceptances'
                : 'stations/${widget.stationId}/manualReplacementAcceptances')
            : 'manualReplacementAcceptances';

        final acceptanceSnapshot = await _notificationService.firestore
            .collection(acceptancesPath)
            .where('requestId', isEqualTo: widget.requestId)
            .where('userId', isEqualTo: widget.currentUserId)
            .where('status', isEqualTo: 'pending')
            .limit(1)
            .get();

        if (acceptanceSnapshot.docs.isNotEmpty) {
          canAccept = false;
          cannotAcceptReason = 'Votre acceptation de cette demande est en attente de validation par le chef d\'équipe.';
        }
      }
      // 3. Vérifier la disponibilité sur la période
      else {
        try {
          // 2a. Vérifier si l'utilisateur est en astreinte durant cette période
          final allPlannings = await _planningRepository.getByStation(widget.stationId);
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
            final existingSubshifts = await _subshiftRepository.getAll(stationId: widget.stationId);
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
          .collection(_getReplacementRequestsPath())
          .doc(widget.requestId)
          .get();

      if (!freshRequestDoc.exists) {
        setState(() {
          _error = 'Cette demande n\'existe plus';
          _isResponding = false;
        });
        return;
      }

      final freshRequestData = freshRequestDoc.data()!;
      final freshStatus = freshRequestData['status'] as String?;
      if (freshStatus != 'pending') {
        setState(() {
          _error = 'Cette demande a déjà été acceptée par quelqu\'un d\'autre';
          _isResponding = false;
        });
        return;
      }

      // 🔒 SÉCURITÉ CRITIQUE : Vérifier que l'utilisateur est bien notifié
      final notifiedUserIds = List<String>.from(
        freshRequestData['notifiedUserIds'] ?? [],
      );
      if (!notifiedUserIds.contains(widget.currentUserId)) {
        setState(() {
          _error = 'ERREUR: Vous n\'êtes pas autorisé à accepter cette demande.\nVous n\'avez pas encore été notifié.';
          _isResponding = false;
        });
        debugPrint('❌ SECURITY VIOLATION: User ${widget.currentUserId} attempted to accept request ${widget.requestId} without being notified!');
        return;
      }

      // Re-vérifier la disponibilité de l'utilisateur (peut avoir changé depuis l'ouverture du dialog)
      final actualStartTime = _selectedStartTime ?? _request!.startTime;
      final actualEndTime = _selectedEndTime ?? _request!.endTime;

      // Vérifier les conflits avec les plannings
      final allPlannings = await _planningRepository.getByStation(widget.stationId);
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
      final existingSubshifts = await _subshiftRepository.getAll(stationId: widget.stationId);
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
          stationId: widget.stationId,
          acceptedStartTime: _selectedStartTime,
          acceptedEndTime: _selectedEndTime,
        );

        // Mettre à jour le statut de la demande
        await _notificationService.firestore
            .collection(_getReplacementRequestsPath())
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

        // Phase 4: Appeler acceptReplacementRequest qui gère la validation conditionnelle
        // Le service déterminera si un Subshift doit être créé immédiatement
        // ou si une acceptation en attente de validation doit être créée
        await _notificationService.acceptReplacementRequest(
          requestId: widget.requestId,
          replacerId: widget.currentUserId,
          stationId: widget.stationId,
          acceptedStartTime: _selectedStartTime,
          acceptedEndTime: _selectedEndTime,
        );

        // Vérifier si la demande a été acceptée ou est en attente de validation
        final updatedRequestDoc = await _notificationService.firestore
            .collection(_getReplacementRequestsPath())
            .doc(widget.requestId)
            .get();

        final updatedStatus = updatedRequestDoc.data()?['status'] as String?;

        if (mounted) {
          Navigator.of(context).pop(true);

          // Phase 4: Afficher le message approprié selon le statut
          if (updatedStatus == 'accepted') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Remplacement accepté'),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            // La demande reste en "pending" car une validation est requise
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  '⏳ Acceptation en attente de validation par votre chef d\'équipe',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
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
          .collection(_getReplacementRequestDeclinesPath())
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

  /// Marque la demande comme "vue" sans y répondre
  /// Phase 2 - État "Vu"
  Future<void> _markAsSeen() async {
    if (_request == null) return;

    try {
      setState(() => _isResponding = true);

      // Ajouter l'userId à seenByUserIds dans Firestore
      await FirebaseFirestore.instance
          .collection(_getReplacementRequestsPath())
          .doc(widget.requestId)
          .update({
        'seenByUserIds': FieldValue.arrayUnion([widget.currentUserId]),
      });

      debugPrint(
        '👁️ Request ${_request!.id} marked as seen by user ${widget.currentUserId}',
      );

      if (mounted) {
        Navigator.of(context).pop(null); // null indique "Vu" sans réponse
      }
    } catch (e) {
      debugPrint('❌ Error marking request as seen: $e');
      // En cas d'erreur, on ferme quand même le dialog
      if (mounted) {
        Navigator.of(context).pop(null);
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

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // AppBar avec BackButton
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    // Marquer comme "Vu" automatiquement au retour
                    _markAsSeen();
                  },
                  tooltip: 'Retour',
                ),
                Expanded(
                  child: Text(
                    isAvailabilityRequest
                        ? 'Demande de disponibilité'
                        : 'Demande de remplacement',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 48), // Équilibre visuel
              ],
            ),
          ),
          // Contenu scrollable
          Flexible(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: _buildDialogContent(context, isAvailabilityRequest),
              ),
            ),
          ),
          // Boutons d'action en bas
          if (!_isLoading && _error == null && _request != null)
            _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildDialogContent(
    BuildContext context,
    bool isAvailabilityRequest,
  ) {
    if (_isLoading) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.red.shade700),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ),
        ],
      );
    }

    if (_request == null) {
      return const Text('Aucune information disponible');
    }

    return Column(
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
        // Le reste du contenu (périodes, etc.) suit ici
        _buildContentDetails(context, isAvailabilityRequest),
      ],
    );
  }

  Widget _buildContentDetails(
    BuildContext context,
    bool isAvailabilityRequest,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            );
  }

  /// Construit les boutons d'action en pleine largeur
  Widget _buildActionButtons(BuildContext context) {
    if (_isResponding) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey.shade900
            : Colors.grey.shade50,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade800
                : Colors.grey.shade200,
          ),
        ),
      ),
      child: Row(
        children: [
          // Bouton "Je ne suis pas disponible" - Style outlined rouge discret
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _declineRequest,
              icon: const Icon(Icons.close, size: 20),
              label: const Text('Non disponible'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade300),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Bouton "Je suis disponible" - Style filled avec couleur primaire
          Expanded(
            child: FilledButton.icon(
              onPressed: _canAccept ? _acceptRequest : null,
              icon: const Icon(Icons.check, size: 20),
              label: const Text('Disponible'),
              style: FilledButton.styleFrom(
                backgroundColor: _canAccept
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade300,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fonction helper pour afficher le dialog
Future<bool?> showReplacementRequestDialog(
  BuildContext context, {
  required String requestId,
  required String currentUserId,
  required String stationId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ReplacementRequestDialog(
      requestId: requestId,
      currentUserId: currentUserId,
      stationId: stationId,
    ),
  );
}
