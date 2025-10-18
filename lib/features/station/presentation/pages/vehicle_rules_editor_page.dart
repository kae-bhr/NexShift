import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/crew_position_model.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/utils/default_vehicle_rules.dart';
import 'package:nexshift_app/core/data/models/crew_mode_model.dart';
import 'package:nexshift_app/core/data/models/vehicle_rule_set_model.dart';

/// Vehicle crew rules editor page with tabs for COMPLET, RÉDUIT, and OPTIONNEL configurations
class VehicleRulesEditorPage extends StatefulWidget {
  final String vehicleType;
  final String initialConfigName;

  const VehicleRulesEditorPage({
    super.key,
    required this.vehicleType,
    required this.initialConfigName,
  });

  @override
  State<VehicleRulesEditorPage> createState() => _VehicleRulesEditorPageState();
}

class _VehicleRulesEditorPageState extends State<VehicleRulesEditorPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<CrewPosition> _fullCrewPositions;
  late List<CrewPosition> _reducedCrewPositions;
  late List<CrewPosition> _optionalPositions;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPositions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadPositions() {
    final VehicleRuleSet? ruleSet = KDefaultVehicleRules.getDefaultRuleSet(
      widget.vehicleType,
    );
    if (ruleSet != null) {
      final defaultMode = ruleSet.defaultMode;
      _fullCrewPositions = defaultMode?.positions ?? [];
      // Reduced: prefer restrictedVariant (prompt secours) if available, otherwise try another mode
      if (defaultMode?.restrictedVariant != null) {
        _reducedCrewPositions = defaultMode!.restrictedVariant!.positions;
      } else {
        final otherModes = ruleSet.modes
            .where((m) => m.id != defaultMode?.id)
            .toList();
        final CrewMode? other = otherModes.isNotEmpty ? otherModes.first : null;
        _reducedCrewPositions = other != null ? other.positions : [];
      }
      _optionalPositions = defaultMode?.optionalPositions ?? [];
    } else {
      _fullCrewPositions = [];
      _reducedCrewPositions = [];
      _optionalPositions = [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Règles - ${widget.vehicleType}'),
        actions: [
          if (_hasChanges)
            TextButton.icon(
              onPressed: _saveChanges,
              icon: const Icon(Icons.save, color: Colors.white),
              label: const Text(
                'Enregistrer',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'COMPLET', icon: Icon(Icons.groups)),
            Tab(text: 'RÉDUIT', icon: Icon(Icons.group)),
            Tab(text: 'OPTIONNEL', icon: Icon(Icons.person_add)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPositionsList(_fullCrewPositions, 'full'),
          _buildPositionsList(_reducedCrewPositions, 'reduced'),
          _buildPositionsList(_optionalPositions, 'optional'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Theme.of(context).colorScheme.primary,
        onPressed: () => _addNewPosition(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un poste'),
      ),
    );
  }

  Widget _buildPositionsList(List<CrewPosition> positions, String crewType) {
    final colorScheme = Theme.of(context).colorScheme;

    if (positions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Aucun poste défini',
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _addNewPosition(),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter le premier poste'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: positions.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final item = positions.removeAt(oldIndex);
          positions.insert(newIndex, item);
          _hasChanges = true;
        });
      },
      itemBuilder: (context, index) {
        final position = positions[index];
        return _buildPositionCard(position, index, positions, crewType);
      },
    );
  }

  Widget _buildPositionCard(
    CrewPosition position,
    int index,
    List<CrewPosition> positions,
    String crewType,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      key: ValueKey('${crewType}_${position.id}_$index'),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      color: isDark ? Colors.grey[850] : Colors.grey[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outline.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: ExpansionTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: Icon(Icons.drag_handle, color: colorScheme.onSurfaceVariant),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                position.label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: () => _editPosition(position, index, positions),
              color: colorScheme.primary,
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20),
              onPressed: () => _deletePosition(index, positions),
              color: colorScheme.error,
            ),
          ],
        ),
        subtitle: Text(
          '${position.requiredSkills.length} compétence(s) requise(s)',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        iconColor: colorScheme.onSurface,
        collapsedIconColor: colorScheme.onSurface,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.white,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Required skills
                Text(
                  'Compétences requises:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                if (position.requiredSkills.isEmpty)
                  Text(
                    'Aucune',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: position.requiredSkills.map((skill) {
                      final skillColor = KSkills.skillColors[skill];
                      final color = skillColor != null
                          ? KSkills.getColorForSkillLevel(skillColor, context)
                          : colorScheme.primary;
                      return Chip(
                        label: Text(skill),
                        backgroundColor: color.withOpacity(0.2),
                        side: BorderSide(color: color.withOpacity(0.5)),
                        labelStyle: TextStyle(
                          color: isDark ? color.withOpacity(0.9) : color,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),

                // Fallback skills
                if (position.fallbackSkills != null &&
                    position.fallbackSkills!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Compétences alternatives:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: position.fallbackSkills!.map((skill) {
                      final skillColor = KSkills.skillColors[skill];
                      final color = skillColor != null
                          ? KSkills.getColorForSkillLevel(skillColor, context)
                          : colorScheme.primary;
                      return Chip(
                        label: Text(skill),
                        backgroundColor: color.withOpacity(0.15),
                        side: BorderSide(color: color.withOpacity(0.3)),
                        labelStyle: TextStyle(
                          color: isDark ? color.withOpacity(0.8) : color,
                          fontWeight: FontWeight.w500,
                        ),
                        avatar: Icon(Icons.alt_route, size: 16, color: color),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addNewPosition() {
    final currentTab = _tabController.index;
    final positions = currentTab == 0
        ? _fullCrewPositions
        : currentTab == 1
        ? _reducedCrewPositions
        : _optionalPositions;

    _editPosition(null, -1, positions);
  }

  void _editPosition(
    CrewPosition? position,
    int index,
    List<CrewPosition> positions,
  ) {
    // TODO: Implement position edit dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Édition de poste - À implémenter')),
    );
  }

  void _deletePosition(int index, List<CrewPosition> positions) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le poste'),
        content: Text(
          'Êtes-vous sûr de vouloir supprimer "${positions[index].label}" ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                positions.removeAt(index);
                _hasChanges = true;
              });
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  void _saveChanges() {
    // TODO: Implement save to repository
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sauvegarde des modifications - À implémenter'),
        duration: Duration(seconds: 2),
      ),
    );

    setState(() => _hasChanges = false);
  }
}
