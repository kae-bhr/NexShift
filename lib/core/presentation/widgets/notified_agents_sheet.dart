import 'package:flutter/material.dart';

/// Statut d'un agent dans le dialog des agents notifiés
enum AgentNotifiedStatus {
  declined,
  validated,
  pendingValidation,
  seen,
  waiting,
  notNotified,
}

/// Entrée d'un agent avec son statut
class AgentStatusEntry {
  final String name;
  final AgentNotifiedStatus status;

  const AgentStatusEntry({required this.name, required this.status});
}

/// Sous-groupe d'agents avec label (ex: "Agents en astreinte", "Agents sous-qualifiés")
class AgentSubGroup {
  final String label;
  final List<AgentStatusEntry> agents;

  const AgentSubGroup({required this.label, required this.agents});
}

/// Groupe d'agents (ex: "Vague 1", "Agents notifiés", "Agents non-notifiés")
class AgentGroup {
  final String label;
  final Color color;

  /// Information de timing optionnelle (ex: "Envoyé il y a 5 min")
  final String? timingInfo;

  /// Agents à plat (groupes simples)
  final List<AgentStatusEntry> agents;

  /// Sous-groupes avec labels (pour "Agents non-notifiés" avec catégories)
  final List<AgentSubGroup> subGroups;

  /// Si true, le groupe est déplié par défaut
  final bool initiallyExpanded;

  const AgentGroup({
    required this.label,
    required this.color,
    this.timingInfo,
    this.agents = const [],
    this.subGroups = const [],
    this.initiallyExpanded = false,
  });

  /// Nombre total d'agents (plats + sous-groupes)
  int get totalCount =>
      agents.length + subGroups.fold(0, (sum, sg) => sum + sg.agents.length);
}

/// BottomSheet déroulable affichant des groupes d'agents avec statuts colorés.
///
/// Utilisé pour :
/// - Détails des vagues (Remplacements) : groupe 0→5 avec timing
/// - Agents notifiés (Recherches) : "Agents non-notifiés" + "Agents notifiés"
class NotifiedAgentsSheet extends StatefulWidget {
  final Color headerColor;
  final IconData headerIcon;
  final String title;
  final List<AgentGroup> groups;

  const NotifiedAgentsSheet({
    super.key,
    required this.headerColor,
    required this.headerIcon,
    required this.title,
    required this.groups,
  });

  /// Affiche la sheet via showModalBottomSheet.
  static Future<void> show({
    required BuildContext context,
    required Color headerColor,
    required IconData headerIcon,
    required String title,
    required List<AgentGroup> groups,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NotifiedAgentsSheet(
        headerColor: headerColor,
        headerIcon: headerIcon,
        title: title,
        groups: groups,
      ),
    );
  }

  @override
  State<NotifiedAgentsSheet> createState() => _NotifiedAgentsSheetState();
}

class _NotifiedAgentsSheetState extends State<NotifiedAgentsSheet> {
  late final Set<int> _expandedGroups;

  @override
  void initState() {
    super.initState();
    _expandedGroups = {
      for (int i = 0; i < widget.groups.length; i++)
        if (widget.groups[i].initiallyExpanded) i,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Material(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: Column(
              children: [
                // ── Header ──────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  color: widget.headerColor,
                  child: Row(
                    children: [
                      Icon(widget.headerIcon, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // ── Liste des groupes ────────────────────────────────────────
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: widget.groups.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                    itemBuilder: (_, i) {
                      final group = widget.groups[i];
                      final isExpanded = _expandedGroups.contains(i);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // En-tête de groupe (cliquable)
                          InkWell(
                            onTap: () => setState(() {
                              if (isExpanded) {
                                _expandedGroups.remove(i);
                              } else {
                                _expandedGroups.add(i);
                              }
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isExpanded
                                        ? Icons.expand_less_rounded
                                        : Icons.expand_more_rounded,
                                    color: group.color,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          group.label,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: group.color,
                                            fontSize: 14,
                                          ),
                                        ),
                                        if (group.timingInfo != null) ...[
                                          const SizedBox(height: 1),
                                          Text(
                                            group.timingInfo!,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? Colors.grey[400]
                                                  : Colors.grey[600],
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  // Badge compteur
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: group.color.withValues(
                                        alpha: isDark ? 0.2 : 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: group.color.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      '${group.totalCount}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: group.color,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Contenu déplié : tuiles d'agents (plat ou avec sous-groupes)
                          if (isExpanded) ...[
                            if (group.subGroups.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: group.subGroups
                                      .where((sg) => sg.agents.isNotEmpty)
                                      .map((sg) => Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(top: 8, bottom: 4),
                                                child: Text(
                                                  sg.label,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: isDark
                                                        ? Colors.grey[400]
                                                        : Colors.grey.shade600,
                                                  ),
                                                ),
                                              ),
                                              ...sg.agents.map((e) => _buildAgentTile(e, isDark)),
                                            ],
                                          ))
                                      .toList(),
                                ),
                              )
                            else if (group.agents.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                                child: Column(
                                  children: group.agents
                                      .map((e) => _buildAgentTile(e, isDark))
                                      .toList(),
                                ),
                              ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAgentTile(AgentStatusEntry entry, bool isDark) {
    final (icon, color, label) = _statusDisplay(entry.status, isDark);
    final isDeclined = entry.status == AgentNotifiedStatus.declined;
    final isActive = entry.status == AgentNotifiedStatus.validated ||
        entry.status == AgentNotifiedStatus.pendingValidation ||
        entry.status == AgentNotifiedStatus.waiting;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.name,
              style: TextStyle(
                fontSize: 13,
                color: isDeclined
                    ? (isDark ? Colors.grey[500] : Colors.grey.shade500)
                    : null,
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.normal,
                decoration:
                    isDeclined ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.18 : 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color, String) _statusDisplay(
    AgentNotifiedStatus status,
    bool isDark,
  ) {
    switch (status) {
      case AgentNotifiedStatus.declined:
        return (Icons.cancel_rounded, Colors.red.shade400, 'Refusé');
      case AgentNotifiedStatus.validated:
        return (Icons.check_circle_rounded, Colors.green.shade400, 'Validé');
      case AgentNotifiedStatus.pendingValidation:
        return (
          Icons.schedule_rounded,
          Colors.green.shade400,
          'En attente valid.',
        );
      case AgentNotifiedStatus.seen:
        return (
          Icons.visibility_rounded,
          isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          'Vu',
        );
      case AgentNotifiedStatus.waiting:
        return (Icons.schedule_rounded, Colors.orange.shade400, 'En attente');
      case AgentNotifiedStatus.notNotified:
        return (
          Icons.person_outline_rounded,
          isDark ? Colors.grey.shade500 : Colors.grey.shade500,
          'Non notifié',
        );
    }
  }
}
