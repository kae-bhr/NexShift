import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/trucks_model.dart';
import 'package:nexshift_app/core/data/models/crew_mode_model.dart';
import 'package:nexshift_app/core/data/models/crew_position_model.dart';
import 'package:nexshift_app/core/data/models/vehicle_rule_set_model.dart';
import 'package:nexshift_app/core/repositories/vehicle_rules_repository.dart';
import 'package:nexshift_app/core/repositories/truck_repository.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/utils/default_vehicle_rules.dart';

// Internal editable representation for dialog (top-level, private to file)
class _EditablePosition {
  String id;
  String label;
  List<String> requiredSkills;
  bool isOptional;
  _EditablePosition({
    required this.id,
    required this.label,
    required this.requiredSkills,
    this.isOptional = false,
  });
}

/// Vehicles tab page - manages station vehicles and crew requirements
/// EXACT copy from StationPage with all functionalities
class VehiclesTabPage extends StatefulWidget {
  final List<Truck> allTrucks;
  final User? currentUser;
  final VoidCallback onDataChanged;

  const VehiclesTabPage({
    super.key,
    required this.allTrucks,
    required this.currentUser,
    required this.onDataChanged,
  });

  @override
  State<VehiclesTabPage> createState() => _VehiclesTabPageState();
}

class _VehiclesTabPageState extends State<VehiclesTabPage> {
  // Expanded state for each vehicle type in Vehicles tab
  final Map<String, bool> _expandedVehicleTypes = {};

  // Custom (station-specific) rules loaded/modified during session
  final Map<String, VehicleRuleSet> _customRuleSets = {};
  final VehicleRulesRepository _rulesRepo = VehicleRulesRepository();

  // Expanded state for availability categories
  bool _expandedAvailable = true;
  bool _expandedUnavailable = true;

  bool get _isLeader =>
      widget.currentUser?.status == 'leader' ||
      widget.currentUser?.admin == true;

  @override
  void initState() {
    super.initState();
    _loadStationCustomRules();
  }

  Future<void> _loadStationCustomRules() async {
    // Load station-specific rules for all present vehicle types so the UI
    // reflects previously saved edits instead of defaults.
    final stationId = KConstants.station;
    final types = widget.allTrucks.map((t) => t.type).toSet().toList();
    for (final type in types) {
      final rs = await _rulesRepo.getRules(
        vehicleType: type,
        stationId: stationId,
      );
      if (rs != null && rs.stationId != null) {
        // Only cache station-specific overrides (keep defaults implicit)
        setState(() {
          _customRuleSets[type] = rs;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildVehiclesTab();
  }

  Widget _buildVehiclesTab() {
    // Group trucks by availability then by type
    final availableTrucks = widget.allTrucks.where((t) => t.available).toList();
    final unavailableTrucks = widget.allTrucks
        .where((t) => !t.available)
        .toList();

    final Map<String, List<Truck>> availableTrucksByType = {};
    for (final truck in availableTrucks) {
      availableTrucksByType.putIfAbsent(truck.type, () => []).add(truck);
    }

    final Map<String, List<Truck>> unavailableTrucksByType = {};
    for (final truck in unavailableTrucks) {
      unavailableTrucksByType.putIfAbsent(truck.type, () => []).add(truck);
    }

    // Collecter tous les types de véhicules présents dans le centre
    final presentTypes = widget.allTrucks.map((t) => t.type).toSet();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header with statistics
        _buildVehiclesHeader(),
        const SizedBox(height: 24),

        // VÉHICULES DISPONIBLES
        _buildAvailabilityCategory(
          title: 'Véhicules disponibles',
          count: availableTrucks.length,
          icon: Icons.check_circle,
          color: Colors.green,
          isExpanded: _expandedAvailable,
          onToggle: () {
            setState(() {
              _expandedAvailable = !_expandedAvailable;
            });
          },
          child: Column(
            children: KTrucks.vehicleTypeOrder
                .where((type) => presentTypes.contains(type))
                .map((type) {
                  final trucks = availableTrucksByType[type] ?? [];
                  return Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: _buildVehicleTypeSection(
                      type,
                      trucks,
                      isAvailable: true,
                    ),
                  );
                })
                .toList(),
          ),
        ),

        const SizedBox(height: 16),

        // VÉHICULES INDISPONIBLES (inclut types présents + types absents)
        _buildAvailabilityCategory(
          title: 'Véhicules indisponibles',
          count: unavailableTrucks.length,
          icon: Icons.cancel,
          color: Colors.orange,
          isExpanded: _expandedUnavailable,
          onToggle: () {
            setState(() {
              _expandedUnavailable = !_expandedUnavailable;
            });
          },
          child: Column(
            children: KTrucks.vehicleTypeOrder.map((type) {
              final trucks = unavailableTrucksByType[type] ?? [];
              final isPresent = presentTypes.contains(type);

              // Afficher types indisponibles OU types absents du centre
              if (trucks.isNotEmpty || !isPresent) {
                return Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: _buildVehicleTypeSection(
                    type,
                    trucks,
                    isAvailable: false,
                  ),
                );
              }
              return const SizedBox.shrink();
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildAvailabilityCategory({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Icon(icon, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Divider(color: colorScheme.primary.withOpacity(0.3)),
                ),
                const SizedBox(width: 8),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded) ...[const SizedBox(height: 12), child],
      ],
    );
  }

  Widget _buildVehiclesHeader() {
    final vehicleCount = widget.allTrucks.length;
    final typeCount = widget.allTrucks.map((t) => t.type).toSet().length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            KColors.appNameColor.withOpacity(0.15),
            KColors.appNameColor.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: KColors.appNameColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Véhicules de la caserne',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: KColors.appNameColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Gestion du parc automobile',
                    style: TextStyle(color: Colors.grey[700], fontSize: 14),
                  ),
                ],
              ),
              if (_isLeader)
                IconButton.filled(
                  onPressed: _showAddVehicleDialog,
                  icon: const Icon(Icons.add),
                  style: IconButton.styleFrom(
                    backgroundColor: KColors.appNameColor,
                    foregroundColor: Colors.white,
                  ),
                  tooltip: 'Ajouter un véhicule',
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildStatCard(
                icon: Icons.local_shipping,
                label: 'Total véhicules',
                value: vehicleCount.toString(),
                color: KColors.appNameColor,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                icon: Icons.category,
                label: 'Types',
                value: typeCount.toString(),
                color: KColors.appNameColor.withOpacity(0.7),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleTypeSection(
    String type,
    List<Truck> trucks, {
    bool isAvailable = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = KTrucks.vehicleIcons[type] ?? Icons.local_shipping;
    final vehicleColor = KTrucks.vehicleColors[type] ?? Colors.grey;
    final description = KTrucks.vehicleDescriptions[type] ?? '';
    final isExpanded = _expandedVehicleTypes[type] ?? false;
    final hasVehicles = trucks.isNotEmpty;

    // Get rules for this vehicle type
    final ruleSet =
        _customRuleSets[type] ?? KDefaultVehicleRules.getDefaultRuleSet(type);
    final modes = ruleSet?.modes ?? [];

    // Couleurs selon la présence de véhicules
    final headerColor = hasVehicles
        ? colorScheme.primaryContainer.withOpacity(0.4)
        : Colors.grey[200]!;
    final iconColor = hasVehicles ? vehicleColor : Colors.grey[500]!;
    final textColor = hasVehicles ? colorScheme.primary : Colors.grey[600]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header - clickable to expand/collapse
        InkWell(
          onTap: () {
            setState(() {
              _expandedVehicleTypes[type] = !isExpanded;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  type,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: hasVehicles
                        ? colorScheme.primary.withOpacity(0.15)
                        : Colors.grey[400]!,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${trucks.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: hasVehicles
                          ? colorScheme.primary
                          : Colors.grey[700]!,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: KColors.appNameColor,
                ),
              ],
            ),
          ),
        ),

        // Collapsible content
        if (isExpanded) ...[
          const SizedBox(height: 12),

          // Description
          if (description.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Requirements card
          if (modes.isNotEmpty) _buildRequirementsCard(type, modes),

          // Vehicle cards
          if (trucks.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...trucks.map((truck) => _buildVehicleCard(truck, icon)),
          ],
        ],

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildRequirementsCard(String type, List<CrewMode> modes) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people_alt, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Modes d\'équipage',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                if (_isLeader)
                  Tooltip(
                    message: 'Ajouter un mode',
                    child: IconButton(
                      splashRadius: 18,
                      onPressed: () => _showEditModeDialog(type, null),
                      icon: const Icon(Icons.add_circle_outline),
                      color: colorScheme.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: modes.map((mode) {
                return _buildModeChip(type, mode);
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeChip(String vehicleType, CrewMode mode) {
    final colorScheme = Theme.of(context).colorScheme;
    final positionsCount = mode.mandatoryPositions.length;
    final hasRestricted = mode.hasRestrictedVariant;

    return InkWell(
      onTap: _isLeader ? () => _showEditModeDialog(vehicleType, mode) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mode.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$positionsCount poste${positionsCount > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                if (hasRestricted) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'PS',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                      ),
                    ),
                  ),
                ],
                if (_isLeader) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 12, color: Colors.grey[500]),
                ],
              ],
            ),
            const SizedBox(height: 6),
            // Affichage des postes du mode
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: mode.mandatoryPositions.map((position) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    position.label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // Slugify helper for ids
  String _slugify(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s_-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
  }

  void _showEditModeDialog(String vehicleType, CrewMode? existingMode) {
    final isNew = existingMode == null;
    // Load current ruleSet (custom or default)
    final baseRuleSet =
        _customRuleSets[vehicleType] ??
        KDefaultVehicleRules.getDefaultRuleSet(vehicleType);
    if (baseRuleSet == null) return;

    // Editable copies
    String modeLabel = existingMode?.label ?? 'Nouveau mode';
    String modeDisplaySuffix = existingMode?.displaySuffix ?? '';
    String modeId = existingMode?.id ?? _slugify(modeLabel);
    bool isDefault = existingMode?.isDefault ?? false;
    bool hasRestrictedVariant = existingMode?.hasRestrictedVariant ?? false;

    List<_EditablePosition> positions = existingMode != null
        ? existingMode.allPositions
              .map(
                (p) => _EditablePosition(
                  id: p.id,
                  label: p.label,
                  requiredSkills: List<String>.from(p.requiredSkills),
                  isOptional: p.isOptional,
                ),
              )
              .toList()
        : <_EditablePosition>[];

    List<_EditablePosition> restrictedPositions =
        (existingMode?.restrictedVariant != null)
        ? existingMode!.restrictedVariant!.allPositions
              .map(
                (p) => _EditablePosition(
                  id: p.id,
                  label: p.label,
                  requiredSkills: List<String>.from(p.requiredSkills),
                  isOptional: p.isOptional,
                ),
              )
              .toList()
        : <_EditablePosition>[];

    void saveMode(StateSetter setStateDialog) async {
      // Validation
      if (modeLabel.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Le label du mode est requis')),
        );
        return;
      }
      final mandatoryPositions = positions.where((p) => !p.isOptional).toList();
      if (mandatoryPositions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Au moins un poste obligatoire')),
        );
        return;
      }
      // Unique id for new mode
      if (isNew) {
        final existingIds = baseRuleSet.modes.map((m) => m.id).toSet();
        modeId = _slugify(modeLabel);
        int suffix = 1;
        String original = modeId;
        while (existingIds.contains(modeId)) {
          modeId = '${original}_$suffix';
          suffix++;
        }
      }

      final newMode = CrewMode(
        id: modeId,
        label: modeLabel,
        displaySuffix: modeDisplaySuffix,
        isDefault: isDefault && !isNew ? true : false,
        positions: [
          for (final p in mandatoryPositions)
            CrewPosition(
              id: p.id,
              label: p.label,
              requiredSkills: p.requiredSkills,
              isOptional: p.isOptional,
            ),
        ],
        optionalPositions: [
          for (final p in positions.where((p) => p.isOptional))
            CrewPosition(
              id: p.id,
              label: p.label,
              requiredSkills: p.requiredSkills,
              isOptional: p.isOptional,
            ),
        ],
        restrictedVariant:
            (hasRestrictedVariant && restrictedPositions.isNotEmpty)
            ? CrewMode(
                id: '${modeId}_ps',
                label: 'Prompt secours',
                positions: [
                  for (final p in restrictedPositions.where(
                    (p) => !p.isOptional,
                  ))
                    CrewPosition(
                      id: p.id,
                      label: p.label,
                      requiredSkills: p.requiredSkills,
                      isOptional: p.isOptional,
                    ),
                ],
                optionalPositions: [
                  for (final p in restrictedPositions.where(
                    (p) => p.isOptional,
                  ))
                    CrewPosition(
                      id: p.id,
                      label: p.label,
                      requiredSkills: p.requiredSkills,
                      isOptional: p.isOptional,
                    ),
                ],
              )
            : null,
      );

      // Build new modes list
      final updatedModes = List<CrewMode>.from(baseRuleSet.modes);
      final idx = updatedModes.indexWhere((m) => m.id == existingMode?.id);
      if (idx != -1) {
        updatedModes[idx] = newMode;
      } else {
        updatedModes.add(newMode);
      }

      final updatedRuleSet = VehicleRuleSet(
        vehicleType: baseRuleSet.vehicleType,
        modes: updatedModes,
        defaultModeId: baseRuleSet.defaultModeId,
        stationId: KConstants.station, // mark station-specific
      );

      await _rulesRepo.saveStationRules(updatedRuleSet);
      setState(() {
        _customRuleSets[vehicleType] = updatedRuleSet;
      });
      if (mounted) Navigator.of(context).pop();
    }

    void deleteMode(StateSetter setStateDialog) async {
      if (isNew) {
        Navigator.of(context).pop();
        return;
      }
      if (isDefault) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de supprimer le mode par défaut'),
          ),
        );
        return;
      }
      final updatedModes = baseRuleSet.modes
          .where((m) => m.id != modeId)
          .toList();
      final updatedRuleSet = VehicleRuleSet(
        vehicleType: baseRuleSet.vehicleType,
        modes: updatedModes,
        defaultModeId: baseRuleSet.defaultModeId,
        stationId: KConstants.station,
      );
      await _rulesRepo.saveStationRules(updatedRuleSet);
      setState(() {
        _customRuleSets[vehicleType] = updatedRuleSet;
      });
      if (mounted) Navigator.of(context).pop();
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: StatefulBuilder(
            builder: (context, setStateDialog) {
              return ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 520,
                  maxHeight: 700,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Row(
                        children: [
                          Icon(
                            Icons.build,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              isNew
                                  ? 'Ajouter un mode - $vehicleType'
                                  : 'Modifier le mode "$modeLabel" - $vehicleType',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Mode label
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Nom du mode',
                          border: OutlineInputBorder(),
                        ),
                        controller: TextEditingController(text: modeLabel),
                        onChanged: (val) {
                          modeLabel = val;
                          if (isNew) {
                            setStateDialog(() {
                              modeId = _slugify(modeLabel);
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Display suffix
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Suffixe d\'affichage (planning)',
                          hintText: 'Ex: 4H, 6H, PS... (vide = mode unique)',
                          border: OutlineInputBorder(),
                          helperText:
                              'Laissez vide pour les véhicules à mode unique',
                          helperMaxLines: 2,
                        ),
                        controller: TextEditingController(
                          text: modeDisplaySuffix,
                        ),
                        onChanged: (val) {
                          modeDisplaySuffix = val;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Positions list
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Postes du mode',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: () {
                                      setStateDialog(() {
                                        positions.add(
                                          _EditablePosition(
                                            id: 'pos_${positions.length + 1}',
                                            label:
                                                'Poste ${positions.length + 1}',
                                            requiredSkills: [KSkills.inc],
                                          ),
                                        );
                                      });
                                    },
                                    icon: const Icon(Icons.add),
                                    label: const Text('Ajouter'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...positions.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final pos = entry.value;
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'Libellé',
                                                    ),
                                                controller:
                                                    TextEditingController(
                                                      text: pos.label,
                                                    ),
                                                onChanged: (val) =>
                                                    pos.label = val,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Switch(
                                              value: pos.isOptional,
                                              onChanged: (v) {
                                                setStateDialog(() {
                                                  pos.isOptional = v;
                                                });
                                              },
                                              activeColor: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              activeTrackColor:
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withOpacity(0.35),
                                              inactiveThumbColor:
                                                  Colors.grey[600],
                                              inactiveTrackColor:
                                                  Colors.grey[300],
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Optionnel',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Supprimer',
                                              icon: const Icon(
                                                Icons.delete_outline,
                                              ),
                                              onPressed: () {
                                                setStateDialog(() {
                                                  positions.removeAt(idx);
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        // Required skill selector (multi-sélection)
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: KSkills.listSkills.map((
                                            skill,
                                          ) {
                                            final selected = pos.requiredSkills
                                                .contains(skill);
                                            return FilterChip(
                                              label: Text(
                                                skill,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                              selected: selected,
                                              onSelected: (sel) {
                                                setStateDialog(() {
                                                  if (sel) {
                                                    pos.requiredSkills.add(
                                                      skill,
                                                    );
                                                  } else {
                                                    pos.requiredSkills.remove(
                                                      skill,
                                                    );
                                                  }
                                                });
                                              },
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                              const SizedBox(height: 16),
                              // Restricted variant section
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () {
                                      setStateDialog(() {
                                        hasRestrictedVariant =
                                            !hasRestrictedVariant;
                                        if (hasRestrictedVariant &&
                                            restrictedPositions.isEmpty) {
                                          restrictedPositions = positions
                                              .where((p) => !p.isOptional)
                                              .take(
                                                positions.length >= 2
                                                    ? positions.length - 1
                                                    : 1,
                                              )
                                              .map(
                                                (p) => _EditablePosition(
                                                  id: 'r_${p.id}',
                                                  label: p.label,
                                                  requiredSkills:
                                                      List<String>.from(
                                                        p.requiredSkills,
                                                      ),
                                                ),
                                              )
                                              .toList();
                                        }
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: hasRestrictedVariant
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Colors.grey[400]!,
                                          width: 2,
                                        ),
                                        color: hasRestrictedVariant
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Colors.white,
                                      ),
                                      child: hasRestrictedVariant
                                          ? const Icon(
                                              Icons.check,
                                              size: 16,
                                              color: Colors.white,
                                            )
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('Variante'),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Divider(
                                      color: Colors.grey[300],
                                      thickness: 1,
                                    ),
                                  ),
                                ],
                              ),
                              if (hasRestrictedVariant) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Text(
                                      'Postes de la variante',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const Spacer(),
                                    TextButton.icon(
                                      onPressed: () {
                                        setStateDialog(() {
                                          restrictedPositions.add(
                                            _EditablePosition(
                                              id: 'r_${restrictedPositions.length + 1}',
                                              label:
                                                  'Poste ${restrictedPositions.length + 1}',
                                              requiredSkills: [KSkills.inc],
                                            ),
                                          );
                                        });
                                      },
                                      icon: const Icon(Icons.add),
                                      label: const Text('Ajouter'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ...restrictedPositions.asMap().entries.map((
                                  entry,
                                ) {
                                  final idx = entry.key;
                                  final pos = entry.value;
                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                        color: Colors.grey[300]!,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  decoration:
                                                      const InputDecoration(
                                                        labelText: 'Libellé',
                                                      ),
                                                  controller:
                                                      TextEditingController(
                                                        text: pos.label,
                                                      ),
                                                  onChanged: (val) =>
                                                      pos.label = val,
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                ),
                                                onPressed: () {
                                                  setStateDialog(() {
                                                    restrictedPositions
                                                        .removeAt(idx);
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: KSkills.listSkills.map((
                                              skill,
                                            ) {
                                              final selected = pos
                                                  .requiredSkills
                                                  .contains(skill);
                                              return FilterChip(
                                                label: Text(
                                                  skill,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                selected: selected,
                                                onSelected: (sel) {
                                                  setStateDialog(() {
                                                    if (sel) {
                                                      pos.requiredSkills.add(
                                                        skill,
                                                      );
                                                    } else {
                                                      pos.requiredSkills.remove(
                                                        skill,
                                                      );
                                                    }
                                                  });
                                                },
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Action buttons
                      Row(
                        children: [
                          if (!isNew)
                            IconButton(
                              onPressed: () => deleteMode(setStateDialog),
                              icon: const Icon(Icons.delete_outline),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                            ),
                          const Spacer(),
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Annuler'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: () => saveMode(setStateDialog),
                            icon: const Icon(Icons.save),
                            label: Text(isNew ? 'Créer' : 'Enregistrer'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildVehicleCard(Truck truck, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // Could open detailed view
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Vehicle icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 28, color: colorScheme.primary),
              ),
              const SizedBox(width: 16),
              // Vehicle info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      truck.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.category, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          truck.type,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Delete button (only for leaders)
              if (_isLeader)
                IconButton(
                  onPressed: () => _showDeleteVehicleDialog(truck),
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red[400],
                  tooltip: 'Supprimer',
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddVehicleDialog() {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 600),
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
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.local_shipping,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ajouter un véhicule',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sélectionnez le type de véhicule',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Vehicle type options - SCROLLABLE
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: KTrucks.vehicleTypeOrder.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, index) {
                      final type = KTrucks.vehicleTypeOrder[index];
                      final icon =
                          KTrucks.vehicleIcons[type] ?? Icons.local_shipping;
                      final color = KTrucks.vehicleColors[type] ?? Colors.grey;
                      final description =
                          KTrucks.vehicleDescriptions[type] ?? '';

                      return _buildVehicleTypeOption(
                        type: type,
                        description: description,
                        icon: icon,
                        color: color,
                        onTap: () async {
                          final truckRepo = TruckRepository();

                          // Get next global ID (unique pour Firestore)
                          final nextId = await truckRepo.getNextId();

                          // Get next display number for this type
                          final nextDisplayNumber =
                              await truckRepo.getNextDisplayNumber(
                            type,
                            KConstants.station,
                          );

                          final newTruck = Truck(
                            id: nextId,
                            displayNumber: nextDisplayNumber,
                            type: type,
                            station: KConstants.station,
                          );

                          await truckRepo.save(newTruck);

                          navigator.pop();

                          if (mounted) {
                            widget.onDataChanged();
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${newTruck.displayName} ajouté avec succès',
                                ),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
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
      ),
    );
  }

  Widget _buildVehicleTypeOption({
    required String type,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final existingCount = widget.allTrucks.where((t) => t.type == type).length;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '$existingCount véhicule${existingCount > 1 ? 's' : ''} existant${existingCount > 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(Icons.add_circle_outline, color: color, size: 24),
          ],
        ),
      ),
    );
  }

  void _showDeleteVehicleDialog(Truck truck) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer le véhicule'),
        content: Text(
          'Êtes-vous sûr de vouloir supprimer ${truck.displayName} ? Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              final truckRepo = TruckRepository();
              await truckRepo.delete(truck.id);

              navigator.pop();

              if (mounted) {
                widget.onDataChanged();
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('${truck.displayName} supprimé')),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}
