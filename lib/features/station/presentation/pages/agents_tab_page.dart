import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/team_model.dart';
import 'package:nexshift_app/core/data/models/position_model.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/repositories/position_repository.dart';
import 'package:nexshift_app/core/repositories/user_stations_repository.dart';
import 'package:nexshift_app/core/services/debug_logger.dart';
import 'package:nexshift_app/core/services/firebase_auth_service.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
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
        ordered = [KSkills.cod2, KSkills.cod1, KSkills.cod0];
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
          return !widget.allTeams.any((t) => t.id == u.team);
        }).toList()..sort((a, b) {
          final lastNameCompare = a.lastName.compareTo(b.lastName);
          if (lastNameCompare != 0) return lastNameCompare;
          return a.firstName.compareTo(b.firstName);
        });

    // Trier les équipes par ordre
    final sortedTeams = List<Team>.from(widget.allTeams)
      ..sort((a, b) => a.order.compareTo(b.order));

    return Scaffold(
      body: CustomScrollView(
        controller: _agentsScrollController,
        slivers: [
          // Teams with agents
          ...sortedTeams.map((team) {
            final teamUsers = (widget.usersByTeam[team.id] ?? [])
              ..sort((a, b) {
                final lastNameCompare = a.lastName.compareTo(b.lastName);
                if (lastNameCompare != 0) return lastNameCompare;
                return a.firstName.compareTo(b.firstName);
              });

            final isExpanded = _expandedTeams[team.id] ?? true;

            return SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: team.color.withOpacity(0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
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
                          color: team.color.withOpacity(0.1),
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
                                      color: Colors.grey[600],
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
                    Divider(height: 1, color: team.color.withOpacity(0.3)),

                    // Agents list (collapsible) with DragTarget for leaders
                    if (isExpanded)
                      if (_isLeader)
                        DragTarget<User>(
                          onAccept: (user) async {
                            // Update user's team
                            await _moveUserToTeam(user, team.id);
                          },
                          builder: (context, candidateData, rejectedData) {
                            final isDraggingOver = candidateData.isNotEmpty;
                            final borderDecoration = BoxDecoration(
                              color: isDraggingOver
                                  ? team.color.withOpacity(0.08)
                                  : null,
                              border: Border.all(
                                color: isDraggingOver
                                    ? team.color
                                    : team.color.withOpacity(0.15),
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
                                      color: team.color.withOpacity(0.1),
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
                        ...teamUsers
                            .map((user) => _buildAgentCard(user, team))
                            .toList(),
                  ],
                ),
              ),
            );
          }).toList(),

          // Agents without team
          if (usersWithoutTeam.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(10),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber,
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Agents sans équipe',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${usersWithoutTeam.length} agent${usersWithoutTeam.length > 1 ? 's' : ''}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: Colors.grey.shade300),
                    // Agents without team - with DragTarget for leaders
                    if (_isLeader)
                      DragTarget<User>(
                        onAccept: (user) async {
                          // Remove user from team
                          await _moveUserToTeam(user, '');
                        },
                        builder: (context, candidateData, rejectedData) {
                          final isDraggingOver = candidateData.isNotEmpty;
                          return Container(
                            decoration: isDraggingOver
                                ? BoxDecoration(
                                    color: Colors.orange.shade50,
                                    border: Border.all(
                                      color: Colors.orange.shade700,
                                      width: 2,
                                    ),
                                  )
                                : null,
                            child: Column(
                              children: usersWithoutTeam
                                  .map(
                                    (user) =>
                                        _buildDraggableAgentCard(user, null),
                                  )
                                  .toList(),
                            ),
                          );
                        },
                      )
                    else
                      ...usersWithoutTeam
                          .map((user) => _buildAgentCard(user, null))
                          .toList(),
                  ],
                ),
              ),
            ),

          // Bottom spacing
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
      floatingActionButton: _isLeader
          ? FloatingActionButton.extended(
              onPressed: _showAgentTypeSelectionDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Ajouter un agent'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            )
          : null,
    );
  }

  Widget _buildAgentCard(User user, Team? team) {
    final teamColor = team?.color ?? Colors.grey;
    final position = user.positionId != null
        ? widget.allPositions.firstWhere(
            (p) => p.id == user.positionId,
            orElse: () => Position(id: '', name: '', stationId: '', order: 0),
          )
        : null;
    final hasPosition = position != null && position.id.isNotEmpty;

    return InkWell(
      onTap: () async {
        // Navigate to SkillsPage for any user
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => SkillsPage(userId: user.id)),
        );
        // Reload data if skills were modified
        if (result == true && mounted) {
          widget.onDataChanged();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: teamColor.withOpacity(0.2),
              child: Text(
                (user.firstName.isNotEmpty ? user.firstName[0] : '') +
                    (user.lastName.isNotEmpty ? user.lastName[0] : ''),
                style: TextStyle(
                  color: teamColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
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
                    '${user.firstName} ${user.lastName}',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        user.status == KConstants.statusLeader
                            ? Icons.shield_moon
                            : user.status == KConstants.statusChief
                            ? Icons.verified_user
                            : Icons.person,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        user.status == KConstants.statusLeader
                            ? 'Chef de centre'
                            : user.status == KConstants.statusChief
                            ? 'Chef de garde'
                            : 'Agent',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      if (user.admin) ...[
                        const SizedBox(width: 4),
                        Text(
                          '•',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.settings,
                          color: Colors.teal,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Admin',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.teal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          position.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (user.skills.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        // Highest level for SUAP, PPBE, INC, COD (in that order)
                        ...['SUAP', 'PPBE', 'INC', 'COD']
                            .map((cat) => _highestForCategory(user.skills, cat))
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
                              final isKeySkill = user.keySkills.contains(skill);
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isKeySkill)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 2),
                                        child: Icon(
                                          Icons.star,
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
                            })
                            .toList(),
                      ],
                    ),
                    // Skills count if more than displayed (SUAP, PPBE, INC, COD)
                    if (user.skills.length >
                        ['SUAP', 'PPBE', 'INC', 'COD']
                            .map((cat) => _highestForCategory(user.skills, cat))
                            .where((s) => s != null)
                            .length)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '+${user.skills.length - ['SUAP', 'PPBE', 'INC', 'COD'].map((cat) => _highestForCategory(user.skills, cat)).where((s) => s != null).length}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),

            // Actions menu (only for leaders)
            if (_isLeader)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: teamColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('Modifier'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'team',
                    child: Row(
                      children: [
                        Icon(Icons.group, size: 18),
                        SizedBox(width: 8),
                        Text('Changer d\'équipe'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'skills',
                    child: Row(
                      children: [
                        Icon(Icons.workspace_premium, size: 18),
                        SizedBox(width: 8),
                        Text('Compétences'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'similarities',
                    child: Row(
                      children: [
                        Icon(Icons.people_alt, size: 18),
                        SizedBox(width: 8),
                        Text('Similarités'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'role',
                    child: Row(
                      children: [
                        Icon(Icons.manage_accounts, size: 18),
                        SizedBox(width: 8),
                        Text('Changer le rôle'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'position',
                    child: Row(
                      children: [
                        Icon(Icons.work_outline, size: 18),
                        SizedBox(width: 8),
                        Text('Définir le poste'),
                      ],
                    ),
                  ),
                  // Option de test de notification (uniquement pour les admins)
                  if (widget.currentUser?.admin == true)
                    const PopupMenuItem(
                      value: 'test_notification',
                      child: Row(
                        children: [
                          Icon(
                            Icons.notifications_active,
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
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete,
                          size: 18,
                          color: Colors.red.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Supprimer',
                          style: TextStyle(color: Colors.red.shade700),
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
    );
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
        child: Container(
          width: 300,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: team?.color ?? Colors.grey, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: (team?.color ?? Colors.grey).withOpacity(0.2),
                child: Text(
                  (user.firstName.isNotEmpty ? user.firstName[0] : '') +
                      (user.lastName.isNotEmpty ? user.lastName[0] : ''),
                  style: TextStyle(
                    color: team?.color ?? Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${user.firstName} ${user.lastName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
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
        SnackBar(
          content: Text('${user.firstName} ${user.lastName} → $teamName'),
        ),
      );
    }
  }

  void _handleAgentAction(String action, User user) async {
    switch (action) {
      case 'edit':
        _showEditAgentDialog(user);
        break;
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
      case 'delete':
        _showDeleteAgentDialog(user);
        break;
    }
  }

  /// Shows dialog to select between adding a new agent or an existing agent
  void _showAgentTypeSelectionDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Ajouter un agent',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Option 1: Add new agent
            Card(
              elevation: 2,
              child: InkWell(
                onTap: () {
                  Navigator.pop(dialogContext);
                  _showCreateCompleteUserDialog();
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.person_add_alt_1,
                          size: 32,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ajouter un nouvel agent',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Créer un nouveau compte utilisateur',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Option 2: Add existing agent
            Card(
              elevation: 2,
              child: InkWell(
                onTap: () {
                  Navigator.pop(dialogContext);
                  _showAddExistingAgentDialog();
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.people_alt,
                          size: 32,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ajouter un agent existant',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Affecter un agent à cette caserne',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }

  /// Shows dialog to add an existing agent to the current station
  void _showAddExistingAgentDialog() {
    final matriculeController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ajouter un agent existant'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Saisissez le matricule d\'un agent déjà enregistré dans le SDIS pour l\'affecter à cette caserne.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: matriculeController,
                decoration: const InputDecoration(
                  labelText: 'Matricule de l\'agent',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
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
            onPressed: () async {
              final matricule = matriculeController.text.trim();

              // Validation
              if (matricule.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Veuillez saisir un matricule')),
                );
                return;
              }

              // Vérifier si l'agent existe déjà dans la station actuelle
              if (widget.allUsers.any((u) => u.id == matricule)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Cet agent est déjà affecté à cette caserne'),
                  ),
                );
                return;
              }

              final currentStation = widget.currentUser?.station;
              if (currentStation == null) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Erreur: station non définie'),
                    ),
                  );
                }
                return;
              }

              try {
                final userRepo = UserRepository();
                final userStationsRepo = UserStationsRepository();
                final sdisId = SDISContext().currentSDISId;

                // 1. Récupérer l'utilisateur existant (chercher dans toutes les stations)
                final existingUser = await userRepo.getById(matricule);

                if (existingUser == null) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Aucun agent trouvé avec ce matricule'),
                      ),
                    );
                  }
                  return;
                }

                DebugLogger().log('✅ Found existing user: ${existingUser.id}');

                // 2. Ajouter la station actuelle à la liste des stations de l'utilisateur
                await userStationsRepo.addStationToUser(
                  matricule,
                  currentStation,
                  sdisId: sdisId,
                );
                DebugLogger().log(
                  '✅ Added station $currentStation to user_stations',
                );

                // 3. Créer une nouvelle instance de l'utilisateur pour la station actuelle
                // Reprendre firstName, lastName, id, skills de l'utilisateur existant
                // Valeurs par défaut: status=agent, team=vide, positionId=vide, admin=false
                final newUserInstance = User(
                  id: existingUser.id,
                  firstName: existingUser.firstName,
                  lastName: existingUser.lastName,
                  station: currentStation,
                  status: KConstants.statusAgent,
                  team: '', // Vide par défaut
                  admin: false, // Non-admin par défaut
                  positionId: null, // Pas de poste par défaut
                  skills: existingUser.skills, // Copier les compétences
                );

                await userRepo.upsert(newUserInstance);
                DebugLogger().log(
                  '✅ Created user instance for station $currentStation',
                );

                // 4. Créer une notification pour informer l'utilisateur
                try {
                  final notificationPath = EnvironmentConfig.userNotificationsCollectionPath;
                  await FirebaseFirestore.instance
                      .collection(notificationPath)
                      .add({
                    'userId': existingUser.id,
                    'type': 'station_added',
                    'title': 'Nouvelle affectation',
                    'message':
                        'Vous avez été affecté(e) à la caserne $currentStation par ${widget.currentUser?.firstName} ${widget.currentUser?.lastName}',
                    'stationId': currentStation,
                    'timestamp': FieldValue.serverTimestamp(),
                    'read': false,
                  });
                  DebugLogger().log('✅ Notification created for user at $notificationPath');
                } catch (e) {
                  DebugLogger().logError(
                    '⚠️ Could not create notification: $e',
                  );
                }

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                if (mounted) {
                  widget.onDataChanged();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Agent ${existingUser.firstName} ${existingUser.lastName} affecté à la caserne',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                }
                DebugLogger().logError('❌ Error adding existing agent: $e');
              }
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  void _showCreateCompleteUserDialog() {
    final matriculeController = TextEditingController();
    final passwordController = TextEditingController();
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final adminPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Créer un nouveau compte'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: matriculeController,
                decoration: const InputDecoration(
                  labelText: 'Matricule du nouvel agent',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: 'Mot de passe du nouvel agent',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: firstNameController,
                decoration: const InputDecoration(
                  labelText: 'Prénom',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lastNameController,
                decoration: const InputDecoration(
                  labelText: 'Nom',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                'Pour créer ce compte, veuillez confirmer votre mot de passe administrateur :',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: adminPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Votre mot de passe',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.admin_panel_settings),
                ),
                obscureText: true,
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
            onPressed: () async {
              final matricule = matriculeController.text.trim();
              final password = passwordController.text.trim();
              final firstName = firstNameController.text.trim();
              final lastName = lastNameController.text.trim();
              final adminPassword = adminPasswordController.text.trim();

              // Validation
              if (matricule.isEmpty ||
                  password.isEmpty ||
                  firstName.isEmpty ||
                  lastName.isEmpty ||
                  adminPassword.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Veuillez remplir tous les champs'),
                  ),
                );
                return;
              }

              if (password.length < 6) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Le mot de passe doit contenir au moins 6 caractères',
                    ),
                  ),
                );
                return;
              }

              // Vérifier si le matricule existe déjà
              if (widget.allUsers.any((u) => u.id == matricule)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Ce matricule existe déjà')),
                );
                return;
              }

              if (widget.currentUser == null) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Erreur: utilisateur non connecté'),
                  ),
                );
                return;
              }

              final authService = FirebaseAuthService();

              try {
                // Créer le compte Firebase Auth en préservant la session admin
                await authService.createUserAsAdmin(
                  adminMatricule: widget.currentUser!.id,
                  adminPassword: adminPassword,
                  newUserMatricule: matricule,
                  newUserPassword: password,
                  sdisId: SDISContext().currentSDISId,
                );
                DebugLogger().log('✅ Firebase Auth user created: $matricule');

                // Créer le profil utilisateur dans Firestore
                // Hériter de la station de l'utilisateur créateur
                await authService.createUserProfile(
                  matricule: matricule,
                  firstName: firstName,
                  lastName: lastName,
                  station: widget.currentUser?.station,
                  sdisId: SDISContext().currentSDISId,
                );
                DebugLogger().log(
                  '✅ Firebase user profile created: $matricule',
                );

                Navigator.pop(dialogContext);
                if (mounted) {
                  widget.onDataChanged();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Agent $matricule créé avec succès'),
                    ),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(
                  dialogContext,
                ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                DebugLogger().logError('❌ Error creating user: $e');
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  void _showEditAgentDialog(User user) {
    final firstNameController = TextEditingController(text: user.firstName);
    final lastNameController = TextEditingController(text: user.lastName);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Modifier l\'agent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstNameController,
              decoration: const InputDecoration(
                labelText: 'Prénom',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: lastNameController,
              decoration: const InputDecoration(
                labelText: 'Nom',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              final firstName = firstNameController.text.trim();
              final lastName = lastNameController.text.trim();

              final updatedUser = user.copyWith(
                firstName: firstName,
                lastName: lastName,
              );

              final userRepo = UserRepository();
              await userRepo.upsert(updatedUser);

              // Mettre à jour userNotifier si c'est l'utilisateur connecté
              if (widget.currentUser?.id == user.id) {
                await UserStorageHelper.saveUser(updatedUser);
              }

              navigator.pop();

              if (mounted) {
                widget.onDataChanged();

                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Agent modifié avec succès')),
                );
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAgentDialog(User user) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Vérifier si l'agent est présent dans d'autres stations
    final userStationsRepo = UserStationsRepository();
    final sdisId = SDISContext().currentSDISId;
    final userStations = await userStationsRepo.getUserStations(user.id, sdisId: sdisId);

    final isMultiStation = userStations != null && userStations.stations.length > 1;
    final currentStation = widget.currentUser?.station;

    if (isMultiStation && currentStation != null) {
      // Cas multi-affectation: suppression partielle
      _showRemoveFromStationDialog(user, userStations.stations, currentStation);
    } else {
      // Cas simple: suppression définitive
      _showCompleteDeleteDialog(user);
    }
  }

  /// Dialog pour supprimer l'agent de la station actuelle uniquement
  void _showRemoveFromStationDialog(User user, List<String> allStations, String currentStation) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final otherStations = allStations.where((s) => s != currentStation).toList();

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
                'Retirer ${user.firstName} ${user.lastName} de la caserne $currentStation ?',
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
                      'Cet agent est également affecté à :\n'
                      '${otherStations.map((s) => '• $s').join('\n')}\n\n'
                      'Cette action va :\n'
                      '• Retirer l\'agent de la caserne $currentStation\n'
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
                final userRepo = UserRepository();
                final userStationsRepo = UserStationsRepository();
                final sdisId = SDISContext().currentSDISId;

                // 1. Supprimer l'utilisateur de la station courante
                await userRepo.deleteFromStation(user.id, currentStation);
                debugPrint('✅ Utilisateur retiré de la station $currentStation');

                // 2. Retirer la station de user_stations
                await userStationsRepo.removeStationFromUser(
                  user.id,
                  currentStation,
                  sdisId: sdisId,
                );
                debugPrint('✅ Station retirée de user_stations');

                // 3. Créer une notification pour informer l'utilisateur
                try {
                  final notificationPath = EnvironmentConfig.userNotificationsCollectionPath;
                  await FirebaseFirestore.instance
                      .collection(notificationPath)
                      .add({
                    'userId': user.id,
                    'type': 'station_removed',
                    'title': 'Retrait d\'affectation',
                    'message':
                        'Vous avez été retiré(e) de la caserne $currentStation par ${widget.currentUser?.firstName} ${widget.currentUser?.lastName}',
                    'stationId': currentStation,
                    'timestamp': FieldValue.serverTimestamp(),
                    'read': false,
                  });
                  debugPrint('✅ Notification created for user at $notificationPath');
                } catch (e) {
                  debugPrint('⚠️ Could not create notification: $e');
                }

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                if (mounted) {
                  widget.onDataChanged();
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        '${user.firstName} ${user.lastName} retiré(e) de la caserne $currentStation',
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

  /// Dialog pour supprimer définitivement l'agent
  void _showCompleteDeleteDialog(User user) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final userPasswordController = TextEditingController();
    final adminPasswordController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Supprimer l\'agent'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Êtes-vous sûr de vouloir supprimer ${user.firstName} ${user.lastName} ?',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning,
                            color: Colors.red.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Suppression complète',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Cette action est IRRÉVERSIBLE et supprimera :\n\n'
                        '• Le profil Firestore (données, équipes, etc.)\n'
                        '• Le compte Firebase Authentication\n'
                        '• L\'accès à l\'application\n\n'
                        'Matricule: ${user.id}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: userPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe de l\'utilisateur',
                    hintText: 'Mot de passe de ${user.id}',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.person),
                  ),
                  obscureText: true,
                  enabled: !isLoading,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: adminPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Votre mot de passe (admin)',
                    hintText: 'Pour vous reconnecter après',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.lock),
                  ),
                  obscureText: true,
                  enabled: !isLoading,
                ),
                if (isLoading) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => navigator.pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: isLoading
                  ? null
                  : () async {
                      final userPassword = userPasswordController.text;
                      final adminPassword = adminPasswordController.text;

                      if (userPassword.isEmpty || adminPassword.isEmpty) {
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(
                            content: Text('Les deux mots de passe sont requis'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }

                      setState(() => isLoading = true);

                      try {
                        final authService = FirebaseAuthService();
                        final userRepo = UserRepository();
                        final userStationsRepo = UserStationsRepository();
                        final currentUserId = widget.currentUser?.id;
                        final sdisId = SDISContext().currentSDISId;

                        if (currentUserId == null) {
                          throw Exception(
                            'Impossible d\'identifier l\'admin actuel',
                          );
                        }

                        debugPrint(
                          '🔥 Début de la suppression de l\'utilisateur: ${user.id}',
                        );

                        // 1. Supprimer le document Firestore
                        debugPrint('🗑️ Suppression du document Firestore...');
                        await userRepo.delete(user.id);
                        debugPrint('✅ Document Firestore supprimé');

                        // 2. Supprimer de user_stations
                        try {
                          await userStationsRepo.removeStationFromUser(
                            user.id,
                            user.station,
                            sdisId: sdisId,
                          );
                          debugPrint('✅ Retiré de user_stations');
                        } catch (e) {
                          debugPrint('⚠️ Erreur user_stations (non bloquant): $e');
                        }

                        // 3. Supprimer le compte Firebase Authentication
                        debugPrint(
                          '🗑️ Suppression du compte Authentication...',
                        );
                        await authService.deleteUserByCredentials(
                          matricule: user.id,
                          password: userPassword,
                          adminMatricule: currentUserId,
                          adminPassword: adminPassword,
                        );
                        debugPrint('✅ Compte Authentication supprimé');

                        navigator.pop();

                        if (mounted) {
                          widget.onDataChanged();

                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                '${user.firstName} ${user.lastName} supprimé(e) complètement (Firestore + Authentication)',
                              ),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      } catch (e) {
                        setState(() => isLoading = false);
                        debugPrint('❌ Erreur lors de la suppression: $e');

                        String errorMessage = 'Erreur lors de la suppression';

                        if (e.toString().contains('wrong-password')) {
                          errorMessage = 'Mot de passe incorrect';
                        } else if (e.toString().contains('user-not-found')) {
                          errorMessage =
                              'Compte Authentication introuvable (peut-être déjà supprimé)';
                        } else if (e.toString().contains('too-many-requests')) {
                          errorMessage =
                              'Trop de tentatives. Réessayez plus tard';
                        } else {
                          errorMessage = e.toString();
                        }

                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(errorMessage),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 5),
                          ),
                        );
                      }
                    },
              child: const Text('Supprimer définitivement'),
            ),
          ],
        ),
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
      if (user.status == KConstants.statusLeader && status != KConstants.statusLeader) {
        final canRemove = await repo.canRemovePrivileges(user.station, user.id);
        if (!canRemove) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Impossible : il doit rester au moins un chef de centre ou admin dans la caserne.'),
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
                          '${user.firstName} ${user.lastName}',
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
                        final canRemove = await repo.canRemovePrivileges(user.station, user.id);
                        if (!canRemove) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Impossible : il doit rester au moins un chef de centre ou admin dans la caserne.'),
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
                          '${user.firstName} ${user.lastName}',
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
              ? colorScheme.primaryContainer.withOpacity(0.3)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
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
              ? colorScheme.primaryContainer.withOpacity(0.3)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
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
                          '${user.firstName} ${user.lastName} n\'est plus dans aucune équipe',
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
                            '${user.firstName} ${user.lastName} affecté à ${team.name}',
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
          'Envoyer une notification de test à ${targetUser.firstName} ${targetUser.lastName} ?',
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
            '✅ Notification de test envoyée à ${targetUser.firstName} ${targetUser.lastName}',
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
