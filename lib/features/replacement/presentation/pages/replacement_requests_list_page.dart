import 'package:flutter/material.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';
import 'package:nexshift_app/core/services/wave_calculation_service.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/features/replacement/presentation/pages/replacement_request_dialog.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Page listant toutes les demandes de remplacement en cours
/// Accessible depuis le Drawer
class ReplacementRequestsListPage extends StatefulWidget {
  const ReplacementRequestsListPage({super.key});

  @override
  State<ReplacementRequestsListPage> createState() =>
      _ReplacementRequestsListPageState();
}

class _ReplacementRequestsListPageState
    extends State<ReplacementRequestsListPage> {
  final _notificationService = ReplacementNotificationService();
  final _userRepository = UserRepository();
  String? _currentUserId;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final user = await UserStorageHelper.loadUser();
    if (mounted) {
      setState(() {
        _currentUserId = user?.id;
      });
    }
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  String _formatMonthYear(DateTime date) {
    const months = [
      'Janvier',
      'Février',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Août',
      'Septembre',
      'Octobre',
      'Novembre',
      'Décembre',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  Future<void> _selectMonthYear() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('fr', 'FR'),
      helpText: 'Sélectionner un mois',
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUserId == null) {
      return Scaffold(
        appBar: CustomAppBar(
          title: 'Demandes de remplacement',
          bottomColor: KColors.appNameColor,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Demandes de remplacement',
        bottomColor: KColors.appNameColor,
      ),
      body: Column(
        children: [
          // Sélecteur de mois/année
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() {
                      _selectedDate = DateTime(
                        _selectedDate.year,
                        _selectedDate.month - 1,
                        1,
                      );
                    });
                  },
                  tooltip: 'Mois précédent',
                ),
                Expanded(
                  child: InkWell(
                    onTap: _selectMonthYear,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.calendar_month,
                            size: 20,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatMonthYear(_selectedDate),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() {
                      _selectedDate = DateTime(
                        _selectedDate.year,
                        _selectedDate.month + 1,
                        1,
                      );
                    });
                  },
                  tooltip: 'Mois suivant',
                ),
              ],
            ),
          ),
          // Liste des demandes
          Expanded(
            child: StreamBuilder<List<ReplacementRequest>>(
              stream: _notificationService.firestore
                  .collection('replacementRequests')
                  .where('status', whereIn: ['pending', 'accepted'])
                  .snapshots()
                  .asyncMap((snapshot) async {
                    final startOfMonth = DateTime(
                      _selectedDate.year,
                      _selectedDate.month,
                      1,
                    );
                    final endOfMonth = DateTime(
                      _selectedDate.year,
                      _selectedDate.month + 1,
                      1,
                    );

                    final allRequests = snapshot.docs
                        .map((doc) => ReplacementRequest.fromJson(doc.data()))
                        .where((request) {
                          // Filtrer par mois sélectionné
                          return request.startTime.isAfter(
                                startOfMonth.subtract(const Duration(days: 1)),
                              ) &&
                              request.startTime.isBefore(endOfMonth);
                        })
                        .toList();

                    // Filtrer les demandes selon les droits de l'utilisateur
                    final visibleRequests = <ReplacementRequest>[];

                    for (final request in allRequests) {
                      // Acceptées : visibles par tous
                      if (request.status == ReplacementRequestStatus.accepted) {
                        visibleRequests.add(request);
                        continue;
                      }

                      // En attente : vérifier les droits
                      final canView = await _canViewRequest(request);
                      if (canView) {
                        visibleRequests.add(request);
                      }
                    }

                    // Trier par date de début (ordre chronologique)
                    visibleRequests.sort(
                      (a, b) => a.startTime.compareTo(b.startTime),
                    );

                    return visibleRequests;
                  }),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Erreur: ${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final requests = snapshot.data ?? [];

                if (requests.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 64,
                            color: Colors.green.shade300,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Aucune demande de remplacement en cours',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Les demandes en attente apparaîtront ici',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final request = requests[index];
                    return _buildRequestCard(request);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRequest(ReplacementRequest request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer la demande ?"),
        content: const Text(
          "Cette action est irréversible. Voulez-vous vraiment supprimer cette demande de remplacement ?",
        ),
        actions: [
          TextButton(
            child: const Text("Annuler"),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Supprimer"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _notificationService.cancelReplacementRequest(request.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Demande supprimée'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildRequestCard(ReplacementRequest request) {
    return FutureBuilder<Map<String, dynamic>>(
      future:
          Future.wait([
            _getRequesterName(request.requesterId),
            UserStorageHelper.loadUser().then((user) => user),
            _canAcceptRequest(request),
          ]).then(
            (results) => {
              'requesterName': results[0] as String,
              'currentUser': results[1],
              'canAccept': results[2] as bool,
            },
          ),
      builder: (context, snapshot) {
        final requesterName =
            snapshot.data?['requesterName'] as String? ?? 'Chargement...';
        final currentUser = snapshot.data?['currentUser'] as User?;
        final canAccept = snapshot.data?['canAccept'] as bool? ?? false;
        final canDelete =
            currentUser != null &&
            (currentUser.admin || currentUser.status == 'leader');

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: InkWell(
            onTap: request.status == ReplacementRequestStatus.pending
                ? () => _handleRequestTap(request)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // En-tête avec nom et badge
                  Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Colors.blue,
                        radius: 20,
                        child: Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              requesterName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Badges de statut et vague
                            Row(
                              children: [
                                // Badge de statut
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        request.status ==
                                            ReplacementRequestStatus.accepted
                                        ? Colors.green.shade100
                                        : Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        request.status ==
                                                ReplacementRequestStatus
                                                    .accepted
                                            ? Icons.check_circle
                                            : Icons.access_time,
                                        size: 14,
                                        color:
                                            request.status ==
                                                ReplacementRequestStatus
                                                    .accepted
                                            ? Colors.green.shade700
                                            : Colors.orange.shade700,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        request.status ==
                                                ReplacementRequestStatus
                                                    .accepted
                                            ? 'Accepté'
                                            : 'En attente',
                                        style: TextStyle(
                                          color:
                                              request.status ==
                                                  ReplacementRequestStatus
                                                      .accepted
                                              ? Colors.green.shade700
                                              : Colors.orange.shade700,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Indicateur de vague/personnes notifiées (si en attente)
                                if (request.status ==
                                    ReplacementRequestStatus.pending) ...[
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () =>
                                        request.requestType ==
                                            RequestType.availability
                                        ? _showNotifiedUsersDialog(request)
                                        : _showWaveDetailsDialog(request),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            request.requestType ==
                                                RequestType.availability
                                            ? Colors.purple.shade100
                                            : Colors.blue.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color:
                                              request.requestType ==
                                                  RequestType.availability
                                              ? Colors.purple.shade300
                                              : Colors.blue.shade300,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            request.requestType ==
                                                    RequestType.availability
                                                ? Icons.people_outline
                                                : Icons.waves,
                                            size: 14,
                                            color:
                                                request.requestType ==
                                                    RequestType.availability
                                                ? Colors.purple.shade700
                                                : Colors.blue.shade700,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            request.requestType ==
                                                    RequestType.availability
                                                ? '${request.notifiedUserIds.length} notifiés'
                                                : 'Vague ${request.currentWave}',
                                            style: TextStyle(
                                              color:
                                                  request.requestType ==
                                                      RequestType.availability
                                                  ? Colors.purple.shade700
                                                  : Colors.blue.shade700,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(width: 2),
                                          Icon(
                                            Icons.info_outline,
                                            size: 14,
                                            color:
                                                request.requestType ==
                                                    RequestType.availability
                                                ? Colors.purple.shade700
                                                : Colors.blue.shade700,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Bouton de suppression (uniquement pour leaders/admins)
                      if (canDelete) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                            size: 20,
                          ),
                          onPressed: () => _deleteRequest(request),
                          tooltip: 'Supprimer la demande',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Période
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Du ${_formatDateTime(request.startTime)}',
                              style: const TextStyle(fontSize: 14),
                            ),
                            Text(
                              'Au ${_formatDateTime(request.endTime)}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Station et équipe
                  if (request.station.isNotEmpty || request.team != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (request.station.isNotEmpty) ...[
                          Icon(
                            Icons.location_on,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            request.station,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                        if (request.station.isNotEmpty && request.team != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '•',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                        if (request.team != null) ...[
                          Icon(
                            Icons.group,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Équipe ${request.team}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],

                  // Affichage du remplaçant trouvé (si accepté)
                  if (request.status == ReplacementRequestStatus.accepted &&
                      request.replacerId != null) ...[
                    const SizedBox(height: 12),
                    FutureBuilder<User?>(
                      future: _userRepository.getById(request.replacerId!),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const SizedBox.shrink();
                        }
                        final replacer = snapshot.data!;
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                request.requestType == RequestType.availability
                                ? Colors.blue.shade50
                                : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  request.requestType ==
                                      RequestType.availability
                                  ? Colors.blue.shade200
                                  : Colors.green.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                request.requestType == RequestType.availability
                                    ? Icons.person_search
                                    : Icons.person_pin,
                                color:
                                    request.requestType ==
                                        RequestType.availability
                                    ? Colors.blue.shade700
                                    : Colors.green.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      request.requestType ==
                                              RequestType.availability
                                          ? 'Agent disponible :'
                                          : 'Remplaçant :',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            request.requestType ==
                                                RequestType.availability
                                            ? Colors.blue.shade700
                                            : Colors.green.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${replacer.firstName} ${replacer.lastName}',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],

                  const SizedBox(height: 12),
                  // Bouton d'action
                  SizedBox(
                    width: double.infinity,
                    child: request.status == ReplacementRequestStatus.accepted
                        ? FilledButton.icon(
                            onPressed: null,
                            icon: const Icon(Icons.check_circle, size: 18),
                            label: Text(
                              request.requestType == RequestType.availability
                                  ? 'Agent trouvé'
                                  : 'Remplacement accepté',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.grey,
                              disabledBackgroundColor: Colors.grey.shade300,
                            ),
                          )
                        : FilledButton.icon(
                            onPressed: canAccept
                                ? () => _handleRequestTap(request)
                                : null,
                            icon: Icon(
                              canAccept ? Icons.check : Icons.visibility,
                              size: 18,
                            ),
                            label: Text(
                              canAccept
                                  ? 'Je suis disponible !'
                                  : 'Voir la demande',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: canAccept
                                  ? Colors.green
                                  : Colors.grey,
                              disabledBackgroundColor: Colors.grey.shade300,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<String> _getRequesterName(String userId) async {
    try {
      final user = await _userRepository.getById(userId);
      return user != null ? '${user.firstName} ${user.lastName}' : 'Inconnu';
    } catch (e) {
      return 'Inconnu';
    }
  }

  /// Vérifie si l'utilisateur courant peut voir cette demande
  Future<bool> _canViewRequest(ReplacementRequest request) async {
    if (_currentUserId == null) return false;

    try {
      // 1. L'auteur de la demande peut toujours voir
      if (request.requesterId == _currentUserId) return true;

      // 2. Récupérer le planning pour connaître le chef de garde
      final planningDoc = await _notificationService.firestore
          .collection('plannings')
          .doc(request.planningId)
          .get();

      if (planningDoc.exists) {
        final planningData = planningDoc.data();
        final planningTeam = planningData?['team'] as String?;
        final planningStation = planningData?['station'] as String?;

        if (planningTeam != null && planningStation != null) {
          // Vérifier si l'utilisateur est chef de garde de cette équipe ou admin de la station
          final currentUser = await UserStorageHelper.loadUser();
          if ((currentUser != null &&
                  currentUser.station == planningStation &&
                  currentUser.team == planningTeam &&
                  currentUser.status == 'chief') ||
              (currentUser != null &&
                  currentUser.station == planningStation &&
                  (currentUser.admin || currentUser.status == 'leader'))) {
            return true;
          }
        }
      }

      // 3. Les utilisateurs de la vague en cours ou d'une vague passée peuvent voir
      final notifiedUserIds = request.notifiedUserIds;
      if (notifiedUserIds.contains(_currentUserId)) {
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Error checking view permission: $e');
      return false;
    }
  }

  /// Vérifie si l'utilisateur courant peut accepter cette demande
  Future<bool> _canAcceptRequest(ReplacementRequest request) async {
    if (_currentUserId == null) return false;
    if (request.status != ReplacementRequestStatus.pending) return false;

    try {
      // Seuls les utilisateurs de la vague en cours ou d'une vague passée peuvent accepter
      final notifiedUserIds = request.notifiedUserIds;
      return notifiedUserIds.contains(_currentUserId);
    } catch (e) {
      debugPrint('Error checking accept permission: $e');
      return false;
    }
  }

  Future<void> _handleRequestTap(ReplacementRequest request) async {
    if (_currentUserId == null) return;

    // Ouvrir le dialog de demande de remplacement
    final result = await showReplacementRequestDialog(
      context,
      requestId: request.id,
      currentUserId: _currentUserId!,
    );

    // Rafraîchir si nécessaire
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remplacement accepté'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Affiche le dialog avec les détails des vagues de notification
  Future<void> _showWaveDetailsDialog(ReplacementRequest request) async {
    try {
      // Récupérer le demandeur pour connaître ses compétences
      final requester = await _userRepository.getById(request.requesterId);
      if (requester == null) return;

      // Récupérer tous les utilisateurs de la station
      final allUsers = await _userRepository.getAll();
      final stationUsers = allUsers
          .where(
            (u) => u.station == request.station && u.id != request.requesterId,
          )
          .toList();

      // Récupérer le planning pour exclure les agents en astreinte et connaître l'équipe
      final planningDoc = await _notificationService.firestore
          .collection('plannings')
          .doc(request.planningId)
          .get();

      final agentsInPlanning = <String>[];
      String planningTeam = request.team ?? '';
      if (planningDoc.exists) {
        final data = planningDoc.data();
        agentsInPlanning.addAll(List<String>.from(data?['agentsId'] ?? []));
        planningTeam = data?['team'] as String? ?? request.team ?? '';
      }

      // Utiliser le WaveCalculationService pour calculer les vagues
      final waveCalculationService = WaveCalculationService();

      // Calculer les poids de rareté des compétences
      final skillRarityWeights = waveCalculationService
          .calculateSkillRarityWeights(
            teamMembers: allUsers,
            requesterSkills: requester.skills,
          );

      // Calculer la vague de chaque candidat avec le nouveau système
      final candidatesWithWave = stationUsers.map((user) {
        final wave = waveCalculationService.calculateWave(
          requester: requester,
          candidate: user,
          planningTeam: planningTeam,
          agentsInPlanning: agentsInPlanning,
          skillRarityWeights: skillRarityWeights,
        );
        return {'user': user, 'wave': wave};
      }).toList();

      // Grouper par vague
      final Map<int, List<User>> waveGroups = {};
      for (final item in candidatesWithWave) {
        final wave = item['wave'] as int;
        final user = item['user'] as User;
        waveGroups.putIfAbsent(wave, () => []).add(user);
      }

      // Trier chaque vague par nom
      waveGroups.forEach((wave, users) {
        users.sort((a, b) {
          final cmp = a.lastName.toLowerCase().compareTo(
            b.lastName.toLowerCase(),
          );
          return cmp != 0
              ? cmp
              : a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
        });
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => _WaveDetailsDialog(
          request: request,
          waveGroups: waveGroups,
          notifiedUserIds: request.notifiedUserIds,
        ),
      );
    } catch (e) {
      debugPrint('Error showing wave details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Affiche la liste des utilisateurs notifiés pour une demande de disponibilité
  Future<void> _showNotifiedUsersDialog(ReplacementRequest request) async {
    try {
      // Récupérer les utilisateurs notifiés
      final notifiedUsers = <User>[];
      for (final userId in request.notifiedUserIds) {
        final user = await _userRepository.getById(userId);
        if (user != null) {
          notifiedUsers.add(user);
        }
      }

      // Trier par nom
      notifiedUsers.sort((a, b) {
        final cmp = a.lastName.toLowerCase().compareTo(
          b.lastName.toLowerCase(),
        );
        return cmp != 0
            ? cmp
            : a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.people_outline, color: Colors.purple.shade700),
              const SizedBox(width: 8),
              const Expanded(child: Text('Agents notifiés')),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: notifiedUsers.isEmpty
                ? const Center(
                    child: Text(
                      'Aucun agent n\'a été notifié',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: notifiedUsers.length,
                    itemBuilder: (context, index) {
                      final user = notifiedUsers[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.purple.shade100,
                            child: Text(
                              user.firstName[0].toUpperCase(),
                              style: TextStyle(
                                color: Colors.purple.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            '${user.firstName} ${user.lastName}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Row(
                            children: [
                              Icon(
                                Icons.group,
                                size: 14,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Équipe ${user.team}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                          dense: true,
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Error showing notified users: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

/// Widget pour afficher les détails des vagues de notification
class _WaveDetailsDialog extends StatefulWidget {
  final ReplacementRequest request;
  final Map<int, List<User>> waveGroups;
  final List<String> notifiedUserIds;

  const _WaveDetailsDialog({
    required this.request,
    required this.waveGroups,
    required this.notifiedUserIds,
  });

  @override
  State<_WaveDetailsDialog> createState() => _WaveDetailsDialogState();
}

class _WaveDetailsDialogState extends State<_WaveDetailsDialog> {
  final Set<int> _expandedWaves = {};

  String _getWaveLabel(int wave) {
    switch (wave) {
      case 0:
        return "Agents en astreinte (jamais notifiés)";
      case 1:
        return "Vague 1 : Équipe (hors astreinte)";
      case 2:
        return "Vague 2 : Compétences identiques";
      case 3:
        return "Vague 3 : Compétences très proches (80%+)";
      case 4:
        return "Vague 4 : Compétences proches (60%+)";
      case 5:
        return "Vague 5 : Autres agents";
      default:
        return "Vague $wave";
    }
  }

  String _getWaveTimingInfo(int wave) {
    final currentWave = widget.request.currentWave;
    final lastWaveSentAt = widget.request.lastWaveSentAt;

    if (wave < currentWave) {
      // Vague déjà envoyée
      return "Déjà notifiés";
    } else if (wave == currentWave) {
      // Vague en cours
      if (lastWaveSentAt != null) {
        final elapsed = DateTime.now().difference(lastWaveSentAt);
        if (elapsed.inMinutes < 60) {
          return "Envoyé il y a ${elapsed.inMinutes} min";
        } else if (elapsed.inHours < 24) {
          return "Envoyé il y a ${elapsed.inHours}h";
        } else {
          return "Envoyé il y a ${elapsed.inDays}j";
        }
      }
      return "En cours d'envoi";
    } else {
      // Vague future
      if (lastWaveSentAt != null) {
        // Calculer le temps restant (délai par défaut: 30 min)
        const delayMinutes = 30;
        final nextWaveTime = lastWaveSentAt.add(
          const Duration(minutes: delayMinutes),
        );
        final remaining = nextWaveTime.difference(DateTime.now());

        if (remaining.isNegative) {
          return "En attente d'envoi";
        } else if (remaining.inMinutes < 60) {
          return "Dans ${remaining.inMinutes} min";
        } else if (remaining.inHours < 24) {
          return "Dans ${remaining.inHours}h";
        } else {
          return "Dans ${remaining.inDays}j";
        }
      }
      return "Non encore envoyé";
    }
  }

  Color _getWaveColor(int wave) {
    final currentWave = widget.request.currentWave;
    if (wave < currentWave) {
      return Colors.grey;
    } else if (wave == currentWave) {
      return Colors.green;
    } else {
      return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedWaves = widget.waveGroups.keys.toList()..sort();

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.waves, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          const Expanded(child: Text('Détails des vagues')),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: sortedWaves.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final wave = sortedWaves[index];
            final users = widget.waveGroups[wave]!;
            final isExpanded = _expandedWaves.contains(wave);
            final waveColor = _getWaveColor(wave);
            final timingInfo = _getWaveTimingInfo(wave);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedWaves.remove(wave);
                      } else {
                        _expandedWaves.add(wave);
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          color: waveColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getWaveLabel(wave),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: waveColor,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                timingInfo,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic,
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
                            color: waveColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${users.length} agent${users.length > 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: waveColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isExpanded)
                  Container(
                    color: Colors.grey.shade50,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    child: Column(
                      children: users.map((user) {
                        final isNotified = widget.notifiedUserIds.contains(
                          user.id,
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                isNotified ? Icons.check_circle : Icons.person,
                                size: 16,
                                color: isNotified
                                    ? Colors.green
                                    : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${user.firstName} ${user.lastName}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isNotified
                                        ? Colors.black
                                        : Colors.grey.shade700,
                                    fontWeight: isNotified
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isNotified)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Notifié',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
