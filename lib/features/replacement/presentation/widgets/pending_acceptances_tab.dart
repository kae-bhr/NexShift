import 'package:flutter/material.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/models/replacement_acceptance_model.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/replacement_acceptance_repository.dart';
import 'package:nexshift_app/core/repositories/station_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';
import 'package:intl/intl.dart';

/// Onglet affichant les acceptations de remplacement en attente de validation
/// Visible uniquement pour les chefs d'équipe et leaders
class PendingAcceptancesTab extends StatefulWidget {
  const PendingAcceptancesTab({super.key});

  @override
  State<PendingAcceptancesTab> createState() => _PendingAcceptancesTabState();
}

class _PendingAcceptancesTabState extends State<PendingAcceptancesTab> {
  final ReplacementAcceptanceRepository _acceptanceRepository =
      ReplacementAcceptanceRepository();
  final UserRepository _userRepository = UserRepository();
  final StationRepository _stationRepository = StationRepository();
  final ReplacementNotificationService _notificationService =
      ReplacementNotificationService();

  List<ReplacementAcceptance> _pendingAcceptances = [];
  bool _isLoading = true;
  Station? _currentStation;

  @override
  void initState() {
    super.initState();
    _loadPendingAcceptances();
  }

  Future<void> _loadPendingAcceptances() async {
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
      // Récupérer les données de la station pour les poids de compétences
      final station = await _stationRepository.getById(currentUser.station);

      // Récupérer les acceptations en attente pour l'équipe du chef
      final acceptances = await _acceptanceRepository.getPendingForTeam(
        currentUser.team,
        stationId: currentUser.station,
      );

      // Trier par date de création (plus anciennes en premier)
      acceptances.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      setState(() {
        _currentStation = station;
        _pendingAcceptances = acceptances;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur de chargement: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _validateAcceptance(ReplacementAcceptance acceptance) async {
    final currentUser = userNotifier.value;
    if (currentUser == null) return;

    try {
      // Utiliser le service pour valider (crée aussi le Subshift et gère les notifications)
      await _notificationService.validateAcceptance(
        acceptanceId: acceptance.id,
        validatedBy: currentUser.id,
        stationId: currentUser.station,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Acceptation validée avec succès'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Recharger la liste
      await _loadPendingAcceptances();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la validation: $e')),
        );
      }
    }
  }

  Future<void> _rejectAcceptance(ReplacementAcceptance acceptance) async {
    final currentUser = userNotifier.value;
    if (currentUser == null) return;

    // Afficher un dialog pour saisir le motif de refus
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _RejectionReasonDialog(),
    );

    if (reason == null || reason.trim().isEmpty) {
      // L'utilisateur a annulé ou n'a pas saisi de motif
      return;
    }

    try {
      await _acceptanceRepository.reject(
        acceptance.id,
        currentUser.id,
        reason,
        stationId: currentUser.station,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Acceptation rejetée'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      // Recharger la liste
      await _loadPendingAcceptances();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur lors du rejet: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = userNotifier.value;

    // Vérifier que l'utilisateur est chef ou leader
    if (currentUser == null ||
        (currentUser.status != 'chief' && currentUser.status != 'leader')) {
      return const Center(
        child: Text(
          'Cet onglet est réservé aux chefs d\'équipe et leaders',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pendingAcceptances.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Aucune acceptation en attente de validation',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPendingAcceptances,
      child: ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: _pendingAcceptances.length,
        itemBuilder: (context, index) {
          final acceptance = _pendingAcceptances[index];
          return _AcceptanceCard(
            acceptance: acceptance,
            onValidate: () => _validateAcceptance(acceptance),
            onReject: () => _rejectAcceptance(acceptance),
            userRepository: _userRepository,
            notificationService: _notificationService,
            station: _currentStation,
          );
        },
      ),
    );
  }
}

/// Card affichant une acceptation en attente
class _AcceptanceCard extends StatefulWidget {
  final ReplacementAcceptance acceptance;
  final VoidCallback onValidate;
  final VoidCallback onReject;
  final UserRepository userRepository;
  final ReplacementNotificationService notificationService;
  final Station? station;

  const _AcceptanceCard({
    required this.acceptance,
    required this.onValidate,
    required this.onReject,
    required this.userRepository,
    required this.notificationService,
    this.station,
  });

  @override
  State<_AcceptanceCard> createState() => _AcceptanceCardState();
}

class _AcceptanceCardState extends State<_AcceptanceCard> {
  User? _requester;
  User? _acceptor;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);

    try {
      debugPrint(
        '🔍 [ACCEPTANCE_CARD] Loading users for acceptance: ${widget.acceptance.id}, requestId: ${widget.acceptance.requestId}',
      );

      // Récupérer l'utilisateur courant pour construire le bon chemin
      final currentUser = userNotifier.value;
      if (currentUser == null) {
        debugPrint('❌ [ACCEPTANCE_CARD] No current user');
        return;
      }

      // Construire le chemin vers la demande de remplacement
      final requestsPath = EnvironmentConfig.getCollectionPath(
          'replacements/automatic/replacementRequests', currentUser.station);

      debugPrint(
        '🔍 [ACCEPTANCE_CARD] Looking for request at: $requestsPath/${widget.acceptance.requestId}',
      );

      // Récupérer la demande directement par son ID
      final requestDoc = await widget.notificationService.firestore
          .collection(requestsPath)
          .doc(widget.acceptance.requestId)
          .get();

      debugPrint('📝 [ACCEPTANCE_CARD] Request exists: ${requestDoc.exists}');

      if (requestDoc.exists) {
        final requestData = requestDoc.data();
        if (requestData != null) {
          final requesterId = requestData['requesterId'] as String;

          debugPrint(
            '👤 [ACCEPTANCE_CARD] Loading requester: $requesterId, acceptor: ${widget.acceptance.userId}',
          );

          final requester = await widget.userRepository.getById(requesterId);
          final acceptor = await widget.userRepository.getById(
            widget.acceptance.userId,
          );

          debugPrint(
            '✅ [ACCEPTANCE_CARD] Users loaded - Requester: ${requester?.firstName}, Acceptor: ${acceptor?.firstName}',
          );

          if (mounted) {
            setState(() {
              _requester = requester;
              _acceptor = acceptor;
            });
          }
        } else {
          debugPrint('❌ [ACCEPTANCE_CARD] Request data is null');
        }
      } else {
        debugPrint(
          '❌ [ACCEPTANCE_CARD] No request found at path: $requestsPath/${widget.acceptance.requestId}',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [ACCEPTANCE_CARD] Error loading users: $e');
      debugPrint('❌ [ACCEPTANCE_CARD] Stack trace: $stackTrace');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final dateFormatShort = DateFormat('dd/MM HH:mm');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête avec nom du remplaçant proposé <- remplacé (style PlanningCard)
            if (_requester != null && _acceptor != null)
              RichText(
                text: TextSpan(
                  style: DefaultTextStyle.of(
                    context,
                  ).style.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
                  children: [
                    TextSpan(
                      text: _acceptor!.displayName,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const TextSpan(text: " ← "),
                    TextSpan(
                      text: _requester!.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),

            // Horaire en format DD/MM HH:mm -> DD/MM HH:mm (style PlanningCard)
            Text(
              '${dateFormatShort.format(widget.acceptance.acceptedStartTime)} → ${dateFormatShort.format(widget.acceptance.acceptedEndTime)}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),

            if (_requester != null && _acceptor != null) ...[
              // Delta de compétences en deux colonnes
              _buildSkillsComparison(),
              const SizedBox(height: 12),
            ],

            // Demandé le
            Text(
              'Demandé le ${dateFormatShort.format(widget.acceptance.createdAt)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),

            const SizedBox(height: 16),

            // Boutons d'action
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: widget.onReject,
                  icon: const Icon(Icons.close, color: Colors.red),
                  label: const Text(
                    'Refuser',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: widget.onValidate,
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text('Valider'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillsComparison() {
    if (_requester == null || _acceptor == null) {
      return const SizedBox.shrink();
    }

    // Filtrer les compétences avec poids > 0 (basé sur la config de la station)
    final skillWeights = widget.station?.skillWeights ?? {};

    // Filtrer les compétences qui ont un poids de 0 dans la configuration
    final requesterSkillsFiltered = _requester!.skills.where((skill) {
      // Si la compétence n'est pas dans skillWeights, on considère qu'elle a un poids par défaut de 1.0
      final weight = skillWeights[skill] ?? 1.0;
      return weight > 0;
    }).toList();

    final acceptorSkillsFiltered = _acceptor!.skills.where((skill) {
      final weight = skillWeights[skill] ?? 1.0;
      return weight > 0;
    }).toList();

    final missingSkills = ReplacementAcceptance.getMissingSkills(
      requesterSkillsFiltered,
      acceptorSkillsFiltered,
    );
    final extraSkills = ReplacementAcceptance.getExtraSkills(
      requesterSkillsFiltered,
      acceptorSkillsFiltered,
    );

    // Si aucune différence, ne rien afficher
    if (missingSkills.isEmpty && extraSkills.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.green.shade200, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 16),
            const SizedBox(width: 6),
            Text(
              'Compétences identiques',
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    // Container stylisé pour le delta de compétences
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Colonne 1: Compétences manquantes
          if (missingSkills.isNotEmpty)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Compétences absentes',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: missingSkills.map((skill) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.red.shade300,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          skill,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          // Divider vertical entre les colonnes
          if (missingSkills.isNotEmpty && extraSkills.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                width: 1,
                height: 60,
                color: Colors.grey.shade300,
              ),
            ),

          // Colonne 2: Compétences supplémentaires
          if (extraSkills.isNotEmpty)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Compétences supplémentaires',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: extraSkills.map((skill) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.blue.shade300,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          skill,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Dialog pour saisir le motif de refus
class _RejectionReasonDialog extends StatefulWidget {
  @override
  State<_RejectionReasonDialog> createState() => _RejectionReasonDialogState();
}

class _RejectionReasonDialogState extends State<_RejectionReasonDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Motif de refus'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          decoration: const InputDecoration(
            hintText: 'Entrez le motif du refus...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Le motif est obligatoire';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_controller.text.trim());
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Refuser'),
        ),
      ],
    );
  }
}
