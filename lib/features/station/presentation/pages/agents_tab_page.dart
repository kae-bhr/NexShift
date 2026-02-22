import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/team_model.dart';
import 'package:nexshift_app/core/data/models/position_model.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/repositories/position_repository.dart';
import 'package:nexshift_app/core/repositories/user_stations_repository.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';
import 'package:nexshift_app/core/services/cloud_functions_service.dart';
import 'package:nexshift_app/core/services/agent_suspension_service.dart';
import 'package:nexshift_app/features/skills/presentation/pages/skills_page.dart';
import 'package:nexshift_app/features/settings/presentation/pages/similar_agents_page.dart';

/// Agents tab page - manages station personnel with drag & drop team assignment
/// EXACT copy from StationPage with all functionalities
class AgentsTabPage extends StatefulWidget {
  final List<User> allUsers;
  final List<Team> allTeams;
  final Map<String, List<User>> usersByTeam;
  final User? currentUser;
  final VoidCallback onDataChanged;
  final List<Position> allPositions;

  const AgentsTabPage({
    super.key,
    required this.allUsers,
    required this.allTeams,
    required this.usersByTeam,
    required this.currentUser,
    required this.onDataChanged,
    this.allPositions = const [],
  });

  @override
  State<AgentsTabPage> createState() => _AgentsTabPageState();
}

class _AgentsTabPageState extends State<AgentsTabPage> {
  late ScrollController _agentsScrollController;

  // Expanded state for each team in Agents tab
  final Map<String, bool> _expandedTeams = {};

  // Auto-scroll during drag
  Timer? _autoScrollTimer;
  double _autoScrollVelocity = 0.0;
  bool _isDragging = false;

  bool get _isLeader =>
      widget.currentUser?.status == 'leader' ||
      widget.currentUser?.admin == true;

  bool get _allExpanded =>
      widget.allTeams.every((t) => _expandedTeams[t.id] ?? true);

  void _toggleAllExpanded() {
    final expand = !_allExpanded;
    setState(() {
      for (final team in widget.allTeams) {
        _expandedTeams[team.id] = expand;
      }
    });
  }

  /// Renvoie la compétence la plus haute pour une catégorie donnée (SUAP/PPBE/INC/COD)
  String? _highestForCategory(List<String> skills, String category) {
    // Ordre de priorité spécifique par catégorie (du plus haut vers le plus bas)
    final List<String> ordered;
    switch (category) {
      case 'SUAP':
        ordered = [KSkills.suapCA, KSkills.suap, KSkills.suapA];
        break;
      case 'PPBE':
        ordered = [KSkills.ppbeCA, KSkills.ppbe, KSkills.ppbeA];
        break;
      case 'INC':
        ordered = [KSkills.incCA, KSkills.incCE, KSkills.inc, KSkills.incA];
        break;
      case 'COD':
        ordered = [KSkills.cod2PL, KSkills.cod2VL, KSkills.cod1, KSkills.cod0];
        break;
      default:
        ordered = [];
    }
    for (final s in ordered) {
      if (skills.contains(s)) return s;
    }
    return null;
  }

  Color _getTextColorForBackground(Color backgroundColor) {
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  @override
  void initState() {
    super.initState();
    _agentsScrollController = ScrollController();
  }

  @override
  void dispose() {
    _agentsScrollController.dispose();
    _stopAutoScroll();
    super.dispose();
  }

  // Auto-scroll methods for drag and drop
  void _startAutoScroll(double velocity) {
    if (_autoScrollTimer != null && _autoScrollVelocity == velocity) return;

    // Stop any existing timer and start a new one
    _stopAutoScroll();
    _autoScrollVelocity = velocity;

    // Start auto-scroll timer
    _autoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 16), // ~60 FPS
      (timer) {
        if (!_agentsScrollController.hasClients) {
          _stopAutoScroll();
          return;
        }

        final currentOffset = _agentsScrollController.offset;
        final maxScrollExtent =
            _agentsScrollController.position.maxScrollExtent;
        final minScrollExtent =
            _agentsScrollController.position.minScrollExtent;

        // Calculate new offset
        final newOffset = currentOffset + _autoScrollVelocity;

        // Stop if we've reached the limits
        if ((newOffset <= minScrollExtent && _autoScrollVelocity < 0) ||
            (newOffset >= maxScrollExtent && _autoScrollVelocity > 0)) {
          return; // Don't stop the timer, just don't scroll
        }

        // Scroll to new position
        final clamped = newOffset.clamp(minScrollExtent, maxScrollExtent);
        _agentsScrollController.jumpTo(clamped);
      },
    );
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollVelocity = 0.0;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _updateAutoScrollForY(details.globalPosition.dy);
  }

  void _updateAutoScrollForY(double yPosition) {
    // Get the screen height
    final screenHeight = MediaQuery.of(context).size.height;

    // Compute dynamic top threshold: margin for app structure
    const double topZoneHeight = 150.0;
    const double bottomZoneHeight = 150.0;
    const double maxScrollSpeed = 15.0;

    if (yPosition < topZoneHeight) {
      // Scroll up - distance from threshold determines speed
      final distanceFromTop = (topZoneHeight - yPosition).clamp(
        0.0,
        topZoneHeight,
      );
      final speed = -(distanceFromTop / topZoneHeight * maxScrollSpeed);
      _startAutoScroll(speed);
    } else if (yPosition > screenHeight - bottomZoneHeight) {
      // Scroll down - distance from bottom determines speed
      final distanceFromBottom = yPosition - (screenHeight - bottomZoneHeight);
      final speed = (distanceFromBottom / bottomZoneHeight * maxScrollSpeed)
          .clamp(0.0, maxScrollSpeed);
      _startAutoScroll(speed);
    } else {
      // Not in scroll zone
      _stopAutoScroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerMove: (event) {
        if (!_isDragging) return;
        _updateAutoScrollForY(event.position.dy);
      },
      onPointerUp: (_) {
        _isDragging = false;
        _stopAutoScroll();
      },
      child: _buildAgentsTab(),
    );
  }

  Widget _buildAgentsTab() {
    final usersWithoutTeam =
        widget.allUsers.where((u) {
          return !widget.allTeams.any((t) => t.id == u.team) && !u.isSuspended;
        }).toList()..sort((a, b) {
          final lastNameCompare = a.lastName.compareTo(b.lastName);
          if (lastNameCompare != 0) return lastNameCompare;
          return a.firstName.compareTo(b.firstName);
        });

    // Agents en suspension d'engagement (retirés de leur équipe, section dédiée)
    final suspendedFromDutyUsers =
        widget.allUsers
            .where(
              (u) =>
                  u.agentAvailabilityStatus ==
                  AgentAvailabilityStatus.suspendedFromDuty,
            )
            .toList()
          ..sort((a, b) {
            final c = a.lastName.compareTo(b.lastName);
            return c != 0 ? c : a.firstName.compareTo(b.firstName);
          });

    // Trier les équipes par ordre
    final sortedTeams = List<Team>.from(widget.allTeams)
      ..sort((a, b) => a.order.compareTo(b.order));

    return Scaffold(
      body: CustomScrollView(
        controller: _agentsScrollController,
        slivers: [
          // Collapse all / Expand all header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.allTeams.length} équipe${widget.allTeams.length > 1 ? 's' : ''} · ${widget.allUsers.length} agent${widget.allUsers.length > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[400]
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _toggleAllExpanded,
                    icon: Icon(
                      _allExpanded
                          ? Icons.unfold_less_rounded
                          : Icons.unfold_more_rounded,
                      size: 16,
                    ),
                    label: Text(
                      _allExpanded ? 'Tout réduire' : 'Tout déplier',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: KColors.appNameColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Teams with agents
          ...sortedTeams.map((team) {
            final teamUsers = (widget.usersByTeam[team.id] ?? [])
              ..sort((a, b) {
                final lastNameCompare = a.lastName.compareTo(b.lastName);
                if (lastNameCompare != 0) return lastNameCompare;
                return a.firstName.compareTo(b.firstName);
              });

            final isExpanded = _expandedTeams[team.id] ?? true;

            final isDark = Theme.of(context).brightness == Brightness.dark;
            final surfaceColor = isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white;
            final borderColor = team.color.withValues(alpha: 0.3);

            return SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Column(
                  children: [
                    // Team header
                    InkWell(
                      onTap: () {
                        setState(() {
                          _expandedTeams[team.id] = !isExpanded;
                        });
                      },
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: team.color.withValues(
                            alpha: isDark ? 0.15 : 0.08,
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: team.color,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  team.id,
                                  style: TextStyle(
                                    color: _getTextColorForBackground(
                                      team.color,
                                    ),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    team.name,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: team.color,
                                    ),
                                  ),
                                  Text(
                                    '${teamUsers.length} agent${teamUsers.length > 1 ? 's' : ''}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              isExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: team.color,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Divider
                    Divider(
                      height: 1,
                      color: team.color.withValues(alpha: 0.3),
                    ),

                    // Agents list (collapsible) with DragTarget for leaders
                    if (isExpanded)
                      if (_isLeader)
                        DragTarget<User>(
                          onAcceptWithDetails: (details) async {
                            await _moveUserToTeam(details.data, team.id);
                          },
                          builder: (context, candidateData, rejectedData) {
                            final isDraggingOver = candidateData.isNotEmpty;
                            final borderDecoration = BoxDecoration(
                              color: isDraggingOver
                                  ? team.color.withValues(alpha: 0.08)
                                  : null,
                              border: Border.all(
                                color: isDraggingOver
                                    ? team.color
                                    : team.color.withValues(alpha: 0.15),
                                width: isDraggingOver ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            );

                            if (teamUsers.isEmpty) {
                              // Provide a visible, tappable drop zone when empty
                              return Container(
                                alignment: Alignment.center,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                padding: const EdgeInsets.all(12),
                                height: 64,
                                decoration: borderDecoration,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.download,
                                      size: 18,
                                      color: team.color,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Déposer un agent ici',
                                      style: TextStyle(
                                        color: team.color,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return Container(
                              decoration: isDraggingOver
                                  ? BoxDecoration(
                                      color: team.color.withValues(alpha: 0.1),
                                      border: Border.all(
                                        color: team.color,
                                        width: 2,
                                      ),
                                    )
                                  : null,
                              child: Column(
                                children: teamUsers
                                    .map(
                                      (user) =>
                                          _buildDraggableAgentCard(user, team),
                                    )
                                    .toList(),
                              ),
                            );
                          },
                        )
                      else
                        ...teamUsers.map((user) => _buildAgentCard(user, team)),
                  ],
                ),
              ),
            );
          }).toList(),

          // Agents without team
          if (usersWithoutTeam.isNotEmpty)
            SliverToBoxAdapter(
              child: Builder(
                builder: (context) {
                  final isDark =
                      Theme.of(context).brightness == Brightness.dark;
                  return Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(
                              alpha: isDark ? 0.15 : 0.08,
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Agents sans équipe',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.orange.shade300
                                            : Colors.orange.shade800,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${usersWithoutTeam.length} agent${usersWithoutTeam.length > 1 ? 's' : ''}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(
                          height: 1,
                          color: Colors.orange.withValues(alpha: 0.3),
                        ),
                        // Agents without team - with DragTarget for leaders
                        if (_isLeader)
                          DragTarget<User>(
                            onAcceptWithDetails: (details) async {
                              await _moveUserToTeam(details.data, '');
                            },
                            builder: (context, candidateData, rejectedData) {
                              final isDraggingOver = candidateData.isNotEmpty;
                              return Container(
                                decoration: isDraggingOver
                                    ? BoxDecoration(
                                        color: Colors.orange.withValues(
                                          alpha: 0.1,
                                        ),
                                        border: Border.all(
                                          color: Colors.orange.shade700,
                                          width: 2,
                                        ),
                                      )
                                    : null,
                                child: Column(
                                  children: usersWithoutTeam
                                      .map(
                                        (user) => _buildDraggableAgentCard(
                                          user,
                                          null,
                                        ),
                                      )
                                      .toList(),
                                ),
                              );
                            },
                          )
                        else
                          ...usersWithoutTeam.map(
                            (user) => _buildAgentCard(user, null),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),

          // Section agents en suspension d'engagement (visible leaders/admins uniquement)
          if (_isLeader && suspendedFromDutyUsers.isNotEmpty)
            SliverToBoxAdapter(
              child: Builder(
                builder: (context) {
                  final isDark =
                      Theme.of(context).brightness == Brightness.dark;
                  return Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(
                              alpha: isDark ? 0.15 : 0.08,
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.pause_circle_outline_rounded,
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Suspension d\'engagement',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.grey.shade300
                                            : Colors.grey.shade700,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${suspendedFromDutyUsers.length} agent${suspendedFromDutyUsers.length > 1 ? 's' : ''}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(
                          height: 1,
                          color: Colors.grey.withValues(alpha: 0.3),
                        ),
                        ...suspendedFromDutyUsers.map(
                          (user) => _buildAgentCard(user, null),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          // Bottom spacing
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
      floatingActionButton: _isLeader
          ? FloatingActionButton.extended(
              onPressed: _showAddAgentDialog,
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Ajouter un agent'),
              backgroundColor: KColors.appNameColor,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  void _showAddAgentDialog() {
    final matriculeController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isLoading = false;

        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.person_add,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ajouter un agent',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Pré-enregistrement par matricule',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Matricule input
                    TextField(
                      controller: matriculeController,
                      decoration: InputDecoration(
                        labelText: 'Matricule',
                        hintText: 'Entrez le matricule de l\'agent',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.badge),
                      ),
                      keyboardType: TextInputType.text,
                      textCapitalization: TextCapitalization.characters,
                      enabled: !isLoading,
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),

                    // Info box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        border: Border.all(color: Colors.blue.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'L\'agent apparaîtra dans l\'effectif. '
                              'Il pourra créer son compte plus tard et sera automatiquement affilié.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (isLoading) ...[
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(),
                    ],
                    const SizedBox(height: 24),

                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isLoading
                                ? null
                                : () => Navigator.pop(dialogContext),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Annuler'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: isLoading
                                ? null
                                : () async {
                                    final matricule = matriculeController.text
                                        .trim();
                                    if (matricule.isEmpty) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Veuillez entrer un matricule',
                                          ),
                                        ),
                                      );
                                      return;
                                    }

                                    setState(() => isLoading = true);

                                    try {
                                      await CloudFunctionsService()
                                          .preRegisterAgent(
                                            stationId:
                                                widget.currentUser!.station,
                                            matricule: matricule,
                                          );

                                      if (dialogContext.mounted) {
                                        Navigator.pop(dialogContext);
                                      }

                                      if (mounted) {
                                        widget.onDataChanged();
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Agent $matricule pré-enregistré',
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      setState(() => isLoading = false);
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text('Erreur: $e'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    }
                                  },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Ajouter'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSuspensionBadge(User user, bool isDark) {
    final isSick =
        user.agentAvailabilityStatus == AgentAvailabilityStatus.sickLeave;
    final badgeColor = isSick ? Colors.red : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSick
                ? Icons.medical_services_outlined
                : Icons.pause_circle_outline_rounded,
            size: 10,
            color: isDark ? badgeColor.shade200 : badgeColor.shade700,
          ),
          const SizedBox(width: 3),
          Text(
            isSick ? 'Arrêt maladie' : 'Suspendu',
            style: TextStyle(
              fontSize: 10,
              color: isDark ? badgeColor.shade200 : badgeColor.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentCard(User user, Team? team) {
    final teamColor = team?.color ?? Colors.grey;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final position = user.positionId != null
        ? widget.allPositions.firstWhere(
            (p) => p.id == user.positionId,
            orElse: () => Position(id: '', name: '', stationId: '', order: 0),
          )
        : null;
    final hasPosition = position != null && position.id.isNotEmpty;
    final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];
    final isSuspended = user.isSuspended;

    return Opacity(
      opacity: isSuspended ? 0.55 : 1.0,
      child: InkWell(
        onTap: () async {
          // Navigate to SkillsPage for any user
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SkillsPage(userId: user.id),
            ),
          );
          // Reload data if skills were modified
          if (result == true && mounted) {
            widget.onDataChanged();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.grey.shade100,
              ),
            ),
          ),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 22,
                backgroundColor: teamColor.withValues(alpha: 0.18),
                child: Text(
                  user.initials,
                  style: TextStyle(
                    color: teamColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        fontStyle: user.isPreRegistered
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          user.status == KConstants.statusLeader
                              ? Icons.shield_moon_rounded
                              : user.status == KConstants.statusChief
                              ? Icons.verified_user_rounded
                              : Icons.person_rounded,
                          size: 13,
                          color: subtitleColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          user.status == KConstants.statusLeader
                              ? 'Chef de centre'
                              : user.status == KConstants.statusChief
                              ? 'Chef de garde'
                              : 'Agent',
                          style: TextStyle(fontSize: 12, color: subtitleColor),
                        ),
                        if (user.admin) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.settings_rounded,
                                  color: Colors.teal,
                                  size: 10,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'Admin',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDark
                                        ? Colors.teal.shade200
                                        : Colors.teal.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (user.isSuspended) ...[
                          const SizedBox(width: 6),
                          _buildSuspensionBadge(user, isDark),
                        ],
                      ],
                    ),
                    if (hasPosition) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (position.iconName != null) ...[
                            Icon(
                              KSkills.positionIcons[position.iconName],
                              size: 13,
                              color: subtitleColor,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            position.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: subtitleColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (user.skills.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          // Highest level for SUAP, PPBE, INC, COD (in that order)
                          ...['SUAP', 'PPBE', 'INC', 'COD']
                              .map(
                                (cat) => _highestForCategory(user.skills, cat),
                              )
                              .where((s) => s != null)
                              .cast<String>()
                              .map((skill) {
                                final levelColor = KSkills.skillColors[skill];
                                final color = levelColor != null
                                    ? KSkills.getColorForSkillLevel(
                                        levelColor,
                                        context,
                                      )
                                    : Theme.of(context).colorScheme.primary;
                                final isKeySkill = user.keySkills.contains(
                                  skill,
                                );
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isKeySkill)
                                        const Padding(
                                          padding: EdgeInsets.only(right: 2),
                                          child: Icon(
                                            Icons.star_rounded,
                                            size: 10,
                                            color: Colors.amber,
                                          ),
                                        ),
                                      Text(
                                        skill,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: color,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                          // Extra skills count
                          if (user.skills.length >
                              ['SUAP', 'PPBE', 'INC', 'COD']
                                  .map(
                                    (cat) =>
                                        _highestForCategory(user.skills, cat),
                                  )
                                  .where((s) => s != null)
                                  .length)
                            Text(
                              '+${user.skills.length - ['SUAP', 'PPBE', 'INC', 'COD'].map((cat) => _highestForCategory(user.skills, cat)).where((s) => s != null).length}',
                              style: TextStyle(
                                fontSize: 10,
                                color: subtitleColor,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Actions menu (only for leaders)
              if (_isLeader)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: subtitleColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'team',
                      child: Row(
                        children: [
                          Icon(Icons.group_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Changer d\'équipe'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'skills',
                      child: Row(
                        children: [
                          Icon(Icons.workspace_premium_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Compétences'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'similarities',
                      child: Row(
                        children: [
                          Icon(Icons.people_alt_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Similarités'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'role',
                      child: Row(
                        children: [
                          Icon(Icons.manage_accounts_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Changer le rôle'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'position',
                      child: Row(
                        children: [
                          Icon(Icons.work_outline_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Définir le poste'),
                        ],
                      ),
                    ),
                    if (widget.currentUser?.admin == true)
                      const PopupMenuItem(
                        value: 'test_notification',
                        child: Row(
                          children: [
                            Icon(
                              Icons.notifications_active_rounded,
                              size: 18,
                              color: Colors.blue,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Tester notification',
                              style: TextStyle(color: Colors.blue),
                            ),
                          ],
                        ),
                      ),
                    // Option de changement d'état (leader/admin uniquement)
                    const PopupMenuItem(
                      value: 'change_status',
                      child: Row(
                        children: [
                          Icon(Icons.pause_circle_outline_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Changer l\'état'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_remove_rounded,
                            size: 18,
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Retirer de l\'effectif',
                            style: TextStyle(color: Colors.orange.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) => _handleAgentAction(value, user),
                ),
            ],
          ),
        ),
      ), // InkWell
    ); // Opacity
  }

  Widget _buildDraggableAgentCard(User user, Team? team) {
    return LongPressDraggable<User>(
      data: user,
      delay: const Duration(milliseconds: 300),
      hapticFeedbackOnStart: true,
      onDragStarted: () {
        _isDragging = true;
      },
      onDragUpdate: (details) {
        _handleDragUpdate(details);
      },
      onDragEnd: (_) {
        _stopAutoScroll();
        _isDragging = false;
      },
      onDraggableCanceled: (_, __) {
        _stopAutoScroll();
        _isDragging = false;
      },
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
        child: Container(
          width: 300,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: team?.color ?? Colors.grey, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: (team?.color ?? Colors.grey).withValues(
                  alpha: 0.2,
                ),
                child: Text(
                  user.initials,
                  style: TextStyle(
                    color: team?.color ?? Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  user.displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    fontStyle: user.isPreRegistered
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildAgentCard(user, team),
      ),
      child: _buildAgentCard(user, team),
    );
  }

  Future<void> _moveUserToTeam(User user, String newTeamId) async {
    // No-op if dropping into the same team
    if (user.team == newTeamId) {
      return;
    }
    final userRepo = UserRepository();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Update user with new team
    final updatedUser = user.copyWith(team: newTeamId);

    await userRepo.upsert(updatedUser);

    // If it's the current user, update storage
    if (widget.currentUser?.id == user.id) {
      await UserStorageHelper.saveUser(updatedUser);
    }

    if (mounted) {
      widget.onDataChanged();

      final teamName = newTeamId.isEmpty
          ? 'Aucune équipe'
          : widget.allTeams.firstWhere((t) => t.id == newTeamId).name;

      // Show snackbar only when the team actually changes
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('${user.displayName} → $teamName')),
      );
    }
  }

  void _handleAgentAction(String action, User user) async {
    switch (action) {
      case 'team':
        _showChangeTeamDialog(user);
        break;
      case 'skills':
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => SkillsPage(userId: user.id)),
        );
        // Si des modifications ont été faites, recharger les données
        if (result == true && mounted) {
          widget.onDataChanged();
        }
        break;
      case 'similarities':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SimilarAgentsPage(targetUser: user),
          ),
        );
        break;
      case 'role':
        _showChangeRoleDialog(user);
        break;
      case 'position':
        _showChangePositionDialog(user);
        break;
      case 'test_notification':
        _sendTestNotification(user);
        break;
      case 'change_status':
        _showChangeStatusSheet(user);
        break;
      case 'delete':
        _showDeleteAgentDialog(user);
        break;
    }
  }

  void _showChangeStatusSheet(User user) {
    final currentStatus = user.agentAvailabilityStatus;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Poignée
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              'Changer l\'état de ${user.displayName}',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Divider(height: 1, color: Colors.grey[300]),
          // Option : Disponible
          _buildStatusOption(
            ctx: ctx,
            icon: Icons.check_circle_outline_rounded,
            iconColor: Colors.green.shade600,
            title: 'Disponible',
            subtitle: 'Retour en service actif',
            isSelected: currentStatus == AgentAvailabilityStatus.active,
            onTap: currentStatus == AgentAvailabilityStatus.active
                ? null
                : () {
                    Navigator.pop(ctx);
                    _reinstateAgent(user);
                  },
          ),
          Divider(height: 1, color: Colors.grey[300]),
          // Option : Arrêt maladie
          _buildStatusOption(
            ctx: ctx,
            icon: Icons.medical_services_outlined,
            iconColor: Colors.red.shade400,
            title: 'Arrêt maladie',
            subtitle: 'Retrait temporaire pour raison médicale',
            isSelected: currentStatus == AgentAvailabilityStatus.sickLeave,
            onTap: currentStatus == AgentAvailabilityStatus.sickLeave
                ? null
                : () {
                    Navigator.pop(ctx);
                    _showSuspendAgentDialog(
                      user,
                      AgentAvailabilityStatus.sickLeave,
                    );
                  },
          ),
          Divider(height: 1, color: Colors.grey[300]),
          // Option : Suspension d'engagement
          _buildStatusOption(
            ctx: ctx,
            icon: Icons.pause_circle_outline_rounded,
            iconColor: Colors.orange.shade700,
            title: 'Suspension d\'engagement',
            subtitle: 'Retrait de l\'effectif opérationnel',
            isSelected:
                currentStatus == AgentAvailabilityStatus.suspendedFromDuty,
            onTap: currentStatus == AgentAvailabilityStatus.suspendedFromDuty
                ? null
                : () {
                    Navigator.pop(ctx);
                    _showSuspendAgentDialog(
                      user,
                      AgentAvailabilityStatus.suspendedFromDuty,
                    );
                  },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStatusOption({
    required BuildContext ctx,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    final isDimmed = onTap == null;
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: isDimmed ? 0.45 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_rounded, color: iconColor, size: 20)
              else
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey[400],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSuspendAgentDialog(User user, String suspensionType) {
    final isSickLeave = suspensionType == AgentAvailabilityStatus.sickLeave;
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                isSickLeave
                    ? Icons.medical_services_outlined
                    : Icons.pause_circle_outline_rounded,
                color: isSickLeave
                    ? Colors.red.shade400
                    : Colors.orange.shade700,
              ),
              const SizedBox(width: 8),
              Text(isSickLeave ? 'Arrêt maladie' : 'Suspension d\'engagement'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${user.displayName} sera ${isSickLeave ? 'placé(e) en arrêt maladie' : 'suspendu(e) de l\'engagement'} à partir de la date choisie.',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                // Sélecteur de date
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 90),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Date de début : ${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange.shade700,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Effets immédiats',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• Retiré(e) de tous les plannings futurs\n'
                        '• Demandes de remplacement annulées\n'
                        '• Échanges de garde annulés\n'
                        '• Plus de notifications reçues\n'
                        '• Ne peut plus être remplaçant(e)${isSickLeave ? '' : '\n• Retiré(e) de son équipe'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: isSickLeave
                    ? Colors.red.shade400
                    : Colors.orange.shade700,
              ),
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await AgentSuspensionService().suspendAgent(
                    agent: user,
                    newStatus: suspensionType,
                    suspensionStartDate: selectedDate,
                  );
                  if (mounted) {
                    widget.onDataChanged();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${user.displayName} ${isSickLeave ? 'placé(e) en arrêt maladie' : 'suspendu(e)'}',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erreur : $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: Text(
                isSickLeave ? 'Confirmer l\'arrêt' : 'Confirmer la suspension',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reinstateAgent(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: Colors.green),
            SizedBox(width: 8),
            Text('Retour en service'),
          ],
        ),
        content: Text(
          'Remettre ${user.displayName} en service actif ?\n\n'
          'Note : les plannings supprimés lors de la suspension ne sont pas restaurés automatiquement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retour en service'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await AgentSuspensionService().reinstateAgent(agent: user);
      if (mounted) {
        widget.onDataChanged();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.displayName} est de retour en service'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showDeleteAgentDialog(User user) async {
    // Récupérer les informations de l'utilisateur
    final userStationsRepo = UserStationsRepository();
    final sdisId = SDISContext().currentSDISId;
    final currentStation = widget.currentUser?.station;

    if (currentStation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur : station actuelle introuvable')),
      );
      return;
    }

    final userStations = await userStationsRepo.getUserStations(
      user.id,
      sdisId: sdisId,
    );

    final allStations = userStations?.stations ?? [currentStation];

    // TOUJOURS retirer de la station (ne jamais supprimer le compte complètement)
    // La suppression du compte doit être faite par l'utilisateur lui-même
    _showRemoveFromStationDialog(user, allStations, currentStation);
  }

  /// Dialog pour supprimer l'agent de la station actuelle uniquement
  void _showRemoveFromStationDialog(
    User user,
    List<String> allStations,
    String currentStation,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final otherStationIds = allStations
        .where((s) => s != currentStation)
        .toList();

    // Résoudre les noms de stations
    final sdisId = SDISContext().currentSDISId;
    final cache = StationNameCache();
    String currentStationName = currentStation;
    final otherStationNames = <String>[];
    if (sdisId != null) {
      currentStationName = await cache.getStationName(sdisId, currentStation);
      for (final id in otherStationIds) {
        otherStationNames.add(await cache.getStationName(sdisId, id));
      }
    } else {
      otherStationNames.addAll(otherStationIds);
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Retirer l\'agent de cette caserne'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Retirer ${user.displayName} de la caserne de $currentStationName ?',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border.all(color: Colors.blue.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Suppression partielle',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Cette action va :\n'
                      '• Retirer l\'agent de la caserne de $currentStationName\n'
                      '• Conserver son profil dans les autres casernes\n'
                      '• Conserver son compte d\'accès',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () async {
              try {
                // Appeler la Cloud Function qui gère tout :
                // suppression profil station, claims, acceptedStations
                await CloudFunctionsService().removeUserFromStation(
                  stationId: currentStation,
                  userMatricule: user.id,
                );

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                if (mounted) {
                  widget.onDataChanged();
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        '${user.displayName} retiré(e) de la caserne $currentStationName',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                debugPrint('❌ Erreur lors du retrait: $e');
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text('Erreur: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Retirer de cette caserne'),
          ),
        ],
      ),
    );
  }

  void _showChangeRoleDialog(User user) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    Future<void> updateRole(String status, String label) async {
      final repo = UserRepository();

      // Protection : si on retire le statut leader, vérifier qu'il reste au moins un autre admin/leader
      if (user.status == KConstants.statusLeader &&
          status != KConstants.statusLeader) {
        final canRemove = await repo.canRemovePrivileges(user.station, user.id);
        if (!canRemove) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Impossible : il doit rester au moins un chef de centre ou admin dans la caserne.',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      final updated = user.copyWith(status: status);
      await repo.upsert(updated);
      if (widget.currentUser?.id == user.id) {
        await UserStorageHelper.saveUser(updated);
      }
      navigator.pop();
      if (mounted) {
        widget.onDataChanged();
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Rôle mis à jour: $label')),
        );
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.manage_accounts,
                      color: colorScheme.onPrimaryContainer,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Changer le rôle',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user.displayName,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Role options
              _buildRoleCard(
                icon: Icons.person_outline,
                iconColor: Colors.blue,
                title: 'Agent',
                description: 'Membre de l\'équipe opérationnelle',
                isSelected: user.status == KConstants.statusAgent,
                onTap: () => updateRole(KConstants.statusAgent, 'Agent'),
              ),
              const SizedBox(height: 12),
              _buildRoleCard(
                icon: Icons.verified_user,
                iconColor: Colors.orange,
                title: 'Chef de garde',
                description: 'Responsable de la garde',
                isSelected: user.status == KConstants.statusChief,
                onTap: () =>
                    updateRole(KConstants.statusChief, 'Chef de garde'),
              ),
              const SizedBox(height: 12),
              _buildRoleCard(
                icon: Icons.shield_moon_outlined,
                iconColor: Colors.purple,
                title: 'Chef de centre',
                description: 'Responsable du centre de secours',
                isSelected: user.status == KConstants.statusLeader,
                onTap: () =>
                    updateRole(KConstants.statusLeader, 'Chef de centre'),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, thickness: 1),
              const SizedBox(height: 16),
              StatefulBuilder(
                builder: (context, setState) {
                  bool isAdmin = user.admin;
                  return GestureDetector(
                    onTap: () async {
                      final repo = UserRepository();

                      // Protection : si on retire le rôle admin, vérifier qu'il reste au moins un autre admin/leader
                      if (user.admin) {
                        final canRemove = await repo.canRemovePrivileges(
                          user.station,
                          user.id,
                        );
                        if (!canRemove) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Impossible : il doit rester au moins un chef de centre ou admin dans la caserne.',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                      }

                      setState(() => isAdmin = !isAdmin);
                      final updated = user.copyWith(admin: !user.admin);
                      await repo.upsert(updated);
                      if (widget.currentUser?.id == user.id) {
                        await UserStorageHelper.saveUser(updated);
                      }
                      if (mounted) {
                        widget.onDataChanged();
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              !user.admin
                                  ? 'Rôle admin activé'
                                  : 'Rôle admin désactivé',
                            ),
                          ),
                        );
                        navigator.pop();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isAdmin ? Colors.teal : Colors.grey[300]!,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              color: Colors.teal,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.settings,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Admin',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Accès privilégié, bypass des restrictions',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isAdmin ? Colors.teal : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isAdmin
                                    ? Colors.teal
                                    : Colors.grey[400]!,
                                width: 2,
                              ),
                            ),
                            child: isAdmin
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 16,
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              // Cancel button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => navigator.pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Annuler'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePositionDialog(User user) async {
    if (!mounted) return;

    final positionRepo = PositionRepository();
    final userRepo = UserRepository();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    // Récupérer les positions disponibles pour la caserne
    final positions = await positionRepo
        .getPositionsByStation(widget.currentUser?.station ?? '')
        .first;

    if (!mounted) return;

    Future<void> updatePosition(String? positionId, String label) async {
      try {
        final updatedUser = user.copyWith(positionId: positionId);
        await userRepo.upsert(updatedUser);

        if (widget.currentUser?.id == user.id) {
          await UserStorageHelper.saveUser(updatedUser);
        }

        navigator.pop();
        if (mounted) {
          widget.onDataChanged();
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text('Poste mis à jour: $label')),
          );
        }
      } catch (e) {
        navigator.pop();
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.work_outline,
                      color: colorScheme.onPrimaryContainer,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Définir le poste',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user.displayName,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Position options
              if (positions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Aucun poste configuré.\nVeuillez créer des postes dans les paramètres.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                )
              else
                ...positions.map((position) {
                  final icon = position.iconName != null
                      ? KSkills.positionIcons[position.iconName]
                      : null;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildPositionCard(
                      icon: icon ?? Icons.work_outline,
                      iconColor: KColors.appNameColor,
                      title: position.name,
                      description: position.description ?? '',
                      isSelected: user.positionId == position.id,
                      onTap: () => updatePosition(position.id, position.name),
                    ),
                  );
                }),
              if (positions.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildPositionCard(
                  icon: Icons.clear,
                  iconColor: Colors.grey,
                  title: 'Aucun poste',
                  description: 'Retirer l\'assignation de poste',
                  isSelected: user.positionId == null,
                  onTap: () => updatePosition(null, 'Aucun'),
                ),
              ],
              const SizedBox(height: 24),
              // Cancel button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => navigator.pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Annuler'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPositionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isSelected
                          ? colorScheme.primary
                          : Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: colorScheme.primary, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isSelected
                          ? colorScheme.primary
                          : Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: colorScheme.primary, size: 24),
          ],
        ),
      ),
    );
  }

  void _showChangeTeamDialog(User user) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Changer d\'équipe'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Option "Aucune équipe"
              ListTile(
                leading: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                title: const Text('Aucune équipe'),
                trailing: user.team.isEmpty
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () async {
                  final updatedUser = user.copyWith(team: '');

                  final userRepo = UserRepository();
                  await userRepo.upsert(updatedUser);

                  navigator.pop();

                  if (mounted) {
                    widget.onDataChanged();

                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          '${user.displayName} n\'est plus dans aucune équipe',
                        ),
                      ),
                    );
                  }
                },
              ),
              const Divider(),
              // Liste des équipes
              ...widget.allTeams.map(
                (team) => ListTile(
                  leading: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: team.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(team.name),
                  trailing: user.team == team.id
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () async {
                    final updatedUser = user.copyWith(team: team.id);

                    final userRepo = UserRepository();
                    await userRepo.upsert(updatedUser);

                    navigator.pop();

                    if (mounted) {
                      widget.onDataChanged();

                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            '${user.displayName} affecté à ${team.name}',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Envoie une notification de test à un agent spécifique
  /// Accessible uniquement aux admins
  Future<void> _sendTestNotification(User targetUser) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final currentUser = widget.currentUser;

    if (currentUser == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Erreur: Utilisateur non connecté'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Vérifier que l'utilisateur est admin
    if (!currentUser.admin) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Seuls les administrateurs peuvent envoyer des notifications de test',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Afficher un dialog de confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notification de test'),
        content: Text(
          'Envoyer une notification de test à ${targetUser.displayName} ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Afficher un indicateur de chargement
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('Envoi de la notification de test...'),
            ],
          ),
          duration: Duration(seconds: 3),
        ),
      );

      // Créer un document dans la collection testNotifications
      // La Cloud Function sendTestNotification sera déclenchée automatiquement
      await FirebaseFirestore.instance.collection('testNotifications').add({
        'targetUserId': targetUser.id,
        'adminId': currentUser.id,
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });

      debugPrint(
        '✅ Test notification trigger created for user ${targetUser.id}',
      );

      // Afficher un message de succès
      scaffoldMessenger.clearSnackBars();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            '✅ Notification de test envoyée à ${targetUser.displayName}',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error sending test notification: $e');
      scaffoldMessenger.clearSnackBars();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('❌ Erreur lors de l\'envoi: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}
