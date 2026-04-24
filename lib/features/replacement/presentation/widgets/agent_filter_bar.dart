import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Barre de filtre par agent, à placer sous le navigateur mensuel dans les historiques.
class AgentFilterBar extends StatelessWidget {
  final User? selectedAgent;
  final String stationId;
  final void Function(User? agent) onAgentSelected;

  const AgentFilterBar({
    super.key,
    required this.selectedAgent,
    required this.stationId,
    required this.onAgentSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = KColors.appNameColor;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark
            ? color.withValues(alpha: 0.08)
            : color.withValues(alpha: 0.04),
        border: Border(
          bottom: BorderSide(
            color: color.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.person_search_rounded,
            size: 16,
            color: color.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          if (selectedAgent == null)
            GestureDetector(
              onTap: () => _openPicker(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: color.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Tous les agents',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : color.withValues(alpha: 0.8),
                  ),
                ),
              ),
            )
          else
            GestureDetector(
              onTap: () => _openPicker(context),
              child: Container(
                padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      selectedAgent!.displayName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : color,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => onAgentSelected(null),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: isDark ? Colors.white70 : color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openPicker(BuildContext context) {
    AgentPickerSheet.show(
      context: context,
      stationId: stationId,
      selectedAgentId: selectedAgent?.id,
      onSelected: onAgentSelected,
    );
  }
}

/// Bottom sheet de sélection d'un agent avec recherche par nom ou matricule.
class AgentPickerSheet extends StatefulWidget {
  final String stationId;
  final String? selectedAgentId;
  final void Function(User? agent) onSelected;

  const AgentPickerSheet._({
    required this.stationId,
    required this.selectedAgentId,
    required this.onSelected,
  });

  static Future<void> show({
    required BuildContext context,
    required String stationId,
    required String? selectedAgentId,
    required void Function(User? agent) onSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AgentPickerSheet._(
        stationId: stationId,
        selectedAgentId: selectedAgentId,
        onSelected: onSelected,
      ),
    );
  }

  @override
  State<AgentPickerSheet> createState() => _AgentPickerSheetState();
}

class _AgentPickerSheetState extends State<AgentPickerSheet> {
  final _userRepository = UserRepository();
  final _searchController = TextEditingController();
  List<User> _allAgents = [];
  List<User> _filteredAgents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAgents();
    _searchController.addListener(() => _onSearchChanged(_searchController.text));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAgents() async {
    final users = await _userRepository.getByStation(widget.stationId);
    users.sort((a, b) => a.displayName.compareTo(b.displayName));
    if (mounted) {
      setState(() {
        _allAgents = users;
        _filteredAgents = users;
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      if (q.isEmpty) {
        _filteredAgents = _allAgents;
      } else {
        _filteredAgents = _allAgents.where((u) {
          return u.displayName.toLowerCase().contains(q) ||
              u.id.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = KColors.appNameColor;
    final bgColor = isDark ? const Color(0xFF1E1E2C) : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Titre
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.person_search_rounded, color: color, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Filtrer par agent',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              // Champ de recherche
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: TextField(
                  controller: _searchController,
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: 'Nom ou matricule…',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    prefixIcon: Icon(Icons.search_rounded, color: color.withValues(alpha: 0.6)),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                ),
              ),
              const Divider(height: 1),
              // Liste
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _filteredAgents.length + 1, // +1 pour "Tous les agents"
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return ListTile(
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: color.withValues(alpha: 0.12),
                                child: Icon(
                                  Icons.people_rounded,
                                  size: 18,
                                  color: color,
                                ),
                              ),
                              title: Text(
                                'Tous les agents',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: widget.selectedAgentId == null
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              trailing: widget.selectedAgentId == null
                                  ? Icon(Icons.check_rounded, color: color, size: 20)
                                  : null,
                              onTap: () {
                                widget.onSelected(null);
                                Navigator.pop(context);
                              },
                            );
                          }
                          final user = _filteredAgents[index - 1];
                          final isSelected = user.id == widget.selectedAgentId;
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: color.withValues(alpha: 0.15),
                              child: Text(
                                user.initials,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                            ),
                            title: Text(
                              user.displayName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight:
                                    isSelected ? FontWeight.w700 : FontWeight.w400,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            subtitle: Text(
                              'Équipe ${user.team}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white38 : Colors.black45,
                              ),
                            ),
                            trailing: isSelected
                                ? Icon(Icons.check_rounded, color: color, size: 20)
                                : null,
                            onTap: () {
                              widget.onSelected(user);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
