import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/trucks_model.dart';
import 'package:nexshift_app/core/data/models/crew_position_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/replacement/services/crew_allocator.dart';

class TimeRangeStatus {
  final DateTime start;
  final DateTime end;
  final VehicleStatus status;
  final List<String> unfilledPositions;
  final List<CrewPosition> unfilledCrewPositions; // Postes vacants (rouge)
  final List<CrewPosition>
  missingForFull; // Postes manquants pour équipage complet (orange)

  TimeRangeStatus({
    required this.start,
    required this.end,
    required this.status,
    this.unfilledPositions = const [],
    this.unfilledCrewPositions = const [],
    this.missingForFull = const [],
  });
}

void showVehicleDetailDialog({
  required BuildContext context,
  required Truck truck,
  required CrewResult crewResult,
  String? fptMode,
  List<TimeRangeStatus>? timeRanges,
  VoidCallback? onPositionTap,
  User? currentUser,
  Planning? currentPlanning,
  Function(Truck, CrewPosition)? onReplacementSearch,
}) {
  final icon = KTrucks.vehicleIcons[truck.type] ?? Icons.local_shipping;
  final title = fptMode != null
      ? '${truck.displayName} - Mode $fptMode'
      : truck.displayName;

  showDialog(
    context: context,
    builder: (context) => _VehicleDetailDialog(
      truck: truck,
      crewResult: crewResult,
      fptMode: fptMode,
      timeRanges: timeRanges,
      currentUser: currentUser,
      currentPlanning: currentPlanning,
      onReplacementSearch: onReplacementSearch,
      icon: icon,
      title: title,
    ),
  );
}

class _VehicleDetailDialog extends StatefulWidget {
  final Truck truck;
  final CrewResult crewResult;
  final String? fptMode;
  final List<TimeRangeStatus>? timeRanges;
  final User? currentUser;
  final Planning? currentPlanning;
  final Function(Truck, CrewPosition)? onReplacementSearch;
  final IconData icon;
  final String title;

  const _VehicleDetailDialog({
    required this.truck,
    required this.crewResult,
    this.fptMode,
    this.timeRanges,
    this.currentUser,
    this.currentPlanning,
    this.onReplacementSearch,
    required this.icon,
    required this.title,
  });

  @override
  State<_VehicleDetailDialog> createState() => _VehicleDetailDialogState();
}

class _VehicleDetailDialogState extends State<_VehicleDetailDialog> {
  final Map<int, bool> _expandedTimeRanges = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: BackButton(onPressed: () => Navigator.pop(context)),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusBadge(widget.crewResult),
              if (widget.timeRanges != null &&
                  widget.timeRanges!.isNotEmpty) ...[
                // MODE HOMEPAGE: Affiche les plages horaires avec postes vacants
                const SizedBox(height: 16),
                const Text(
                  "Plages horaires problématiques",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                _buildTimeRangesSection(widget.timeRanges!),
              ] else ...[
                // MODE PLANNING TEAM DETAILS: Affiche tous les postes avec couleurs
                const SizedBox(height: 16),
                _buildAllPositionsList(),
              ],
              const SizedBox(height: 16),
              _buildApprenticeBlock(widget.truck, widget.crewResult),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllPositionsList() {
    // Affiche TOUS les postes avec leurs couleurs (vert/orange/rouge)
    final allPositions = widget.crewResult.positions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Équipage :",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        // All positions (filled and unfilled)
        ...allPositions.map((assignment) {
          return _buildPositionBlockWithColors(
            widget.truck,
            widget.crewResult,
            assignment,
            widget.currentUser,
            widget.currentPlanning,
            widget.onReplacementSearch,
          );
        }).toList(),
        // Missing positions for full crew (only if status is orange)
        if (widget.crewResult.status == VehicleStatus.orange &&
            widget.crewResult.missingForFull.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            "Postes supplémentaires pour équipage complet :",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: KColors.medium,
            ),
          ),
          const SizedBox(height: 8),
          ...widget.crewResult.missingForFull.map((position) {
            return _buildMissingForFullBlock(
              widget.truck,
              position,
              widget.currentUser,
              widget.currentPlanning,
              widget.onReplacementSearch,
            );
          }).toList(),
        ],
      ],
    );
  }

  Widget _buildPositionBlockWithColors(
    Truck truck,
    CrewResult crewResult,
    PositionAssignment assignment,
    User? currentUser,
    Planning? currentPlanning,
    Function(Truck, CrewPosition)? onReplacementSearch,
  ) {
    final isFilled = assignment.isFilled;

    // Determine color based on status and whether position is filled
    Color borderColor;
    Color bgColor;

    if (isFilled) {
      borderColor = KColors.strong.withOpacity(0.3);
      bgColor = KColors.strong.withOpacity(0.05);
    } else {
      // Empty position: color depends on vehicle status
      if (crewResult.status == VehicleStatus.orange) {
        borderColor = KColors.medium.withOpacity(0.5);
        bgColor = KColors.medium.withOpacity(0.1);
      } else {
        // red or grey
        borderColor = KColors.weak.withOpacity(0.5);
        bgColor = KColors.weak.withOpacity(0.1);
      }
    }

    // Check if user can click (chief of astreinte team or leader any team)
    final canClick =
        !isFilled &&
        currentUser != null &&
        onReplacementSearch != null &&
        (currentUser.admin ||
            (currentUser.status == KConstants.statusChief &&
                currentUser.team == currentPlanning?.team) ||
            (currentUser.status == KConstants.statusLeader));

    return GestureDetector(
      onTap: canClick
          ? () => onReplacementSearch(truck, assignment.position)
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isFilled ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: isFilled
                      ? KColors.strong
                      : (crewResult.status == VehicleStatus.orange
                            ? KColors.medium
                            : KColors.weak),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    assignment.position.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                // Afficher l'icône d'avertissement si le poste est en fallback
                if (isFilled && assignment.isFallback)
                  Tooltip(
                    message: 'Poste pourvu par un équipier',
                    child: InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            icon: Icon(
                              Icons.info_outline,
                              color: Colors.orange.shade700,
                              size: 32,
                            ),
                            title: const Text(
                              'Information',
                              style: TextStyle(fontSize: 18),
                            ),
                            content: const Text(
                              'Ce poste de chef d\'équipe est pourvu par un équipier par manque de chef d\'équipe disponible.',
                              textAlign: TextAlign.center,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          Icons.warning_amber,
                          size: 20,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ),
                if (canClick)
                  Icon(Icons.search, size: 18, color: Colors.grey[600]),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Compétences : ${assignment.position.requiredSkills.join(', ')}",
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            if (!isFilled) ...[
              const SizedBox(height: 8),
              Text(
                "Poste vacant",
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRangesSection(List<TimeRangeStatus> timeRanges) {
    debugPrint(
      '_buildTimeRangesSection called with ${timeRanges.length} time ranges',
    );
    for (var i = 0; i < timeRanges.length; i++) {
      final tr = timeRanges[i];
      debugPrint(
        '  Range $i: ${tr.start.hour}:${tr.start.minute.toString().padLeft(2, "0")} - ${tr.end.hour}:${tr.end.minute.toString().padLeft(2, "0")} (${tr.status})',
      );
    }

    // Filter only orange and red ranges
    final problematicRanges = timeRanges
        .where(
          (tr) =>
              tr.status == VehicleStatus.orange ||
              tr.status == VehicleStatus.red,
        )
        .toList();

    debugPrint('Problematic ranges after filter: ${problematicRanges.length}');

    if (problematicRanges.isEmpty) return const SizedBox.shrink();

    return Column(
      children: problematicRanges.asMap().entries.map((entry) {
        final index = entry.key;
        final range = entry.value;
        final isExpanded = _expandedTimeRanges[index] ?? false;
        final formatter = DateFormat('dd/MM HH:mm');
        final startStr = formatter.format(range.start);
        final endStr = formatter.format(range.end);
        final color = _statusToColor(range.status);

        debugPrint(
          'Range $index has ${range.unfilledPositions.length} unfilled: ${range.unfilledPositions.join(", ")}',
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _expandedTimeRanges[index] = !isExpanded;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        range.status == VehicleStatus.orange
                            ? Icons.warning
                            : Icons.error,
                        size: 20,
                        color: color,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '$startStr - $endStr',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: color,
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (range.unfilledCrewPositions.isEmpty &&
                          range.missingForFull.isEmpty)
                        const Text(
                          "Aucun poste vacant",
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.grey,
                          ),
                        )
                      else ...[
                        // Unfilled positions (for red vehicles)
                        if (range.unfilledCrewPositions.isNotEmpty) ...[
                          ...range.unfilledCrewPositions.map((position) {
                            return _buildPositionBlockFromCrewPosition(
                              widget.truck,
                              range.status,
                              position,
                              widget.currentUser,
                              widget.currentPlanning,
                              widget.onReplacementSearch,
                            );
                          }).toList(),
                        ],
                        // Missing positions for full crew (for orange vehicles)
                        if (range.missingForFull.isNotEmpty) ...[
                          if (range.unfilledCrewPositions.isNotEmpty)
                            const SizedBox(height: 8),
                          if (range.unfilledCrewPositions.isNotEmpty)
                            Text(
                              "Postes supplémentaires pour équipage complet :",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: KColors.medium,
                              ),
                            ),
                          if (range.unfilledCrewPositions.isNotEmpty)
                            const SizedBox(height: 8),
                          ...range.missingForFull.map((position) {
                            return _buildMissingForFullBlockFromCrewPosition(
                              widget.truck,
                              position,
                              widget.currentUser,
                              widget.currentPlanning,
                              widget.onReplacementSearch,
                            );
                          }).toList(),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPositionBlock(
    Truck truck,
    CrewResult crewResult,
    PositionAssignment assignment,
    User? currentUser,
    Planning? currentPlanning,
    Function(Truck, CrewPosition)? onReplacementSearch,
  ) {
    // Determine color based on status
    Color borderColor;
    Color bgColor;

    if (crewResult.status == VehicleStatus.orange) {
      borderColor = KColors.medium.withOpacity(0.3);
      bgColor = KColors.medium.withOpacity(0.05);
    } else {
      borderColor = KColors.weak.withOpacity(0.3);
      bgColor = KColors.weak.withOpacity(0.05);
    }

    // Check if user can click
    final canClick =
        currentUser != null &&
        onReplacementSearch != null &&
        ((currentUser.status == KConstants.statusChief &&
                currentUser.team == currentPlanning?.team) ||
            (currentUser.status == KConstants.statusLeader));

    return GestureDetector(
      onTap: canClick
          ? () => onReplacementSearch(truck, assignment.position)
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.radio_button_unchecked,
                  size: 18,
                  color: crewResult.status == VehicleStatus.orange
                      ? KColors.medium
                      : KColors.weak,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    assignment.position.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (canClick)
                  Icon(Icons.search, size: 16, color: Colors.grey[600]),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Compétences : ${assignment.position.requiredSkills.join(', ')}",
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionBlockFromCrewPosition(
    Truck truck,
    VehicleStatus rangeStatus,
    CrewPosition position,
    User? currentUser,
    Planning? currentPlanning,
    Function(Truck, CrewPosition)? onReplacementSearch,
  ) {
    // Determine color based on range status
    Color borderColor;
    Color bgColor;

    if (rangeStatus == VehicleStatus.orange) {
      borderColor = KColors.medium.withOpacity(0.3);
      bgColor = KColors.medium.withOpacity(0.05);
    } else {
      borderColor = KColors.weak.withOpacity(0.3);
      bgColor = KColors.weak.withOpacity(0.05);
    }

    // Check if user can click
    final canClick =
        currentUser != null &&
        onReplacementSearch != null &&
        (currentUser.admin ||
            (currentUser.status == KConstants.statusChief &&
                currentUser.team == currentPlanning?.team) ||
            (currentUser.status == KConstants.statusLeader));

    return GestureDetector(
      onTap: canClick ? () => onReplacementSearch(truck, position) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.radio_button_unchecked,
                  size: 18,
                  color: rangeStatus == VehicleStatus.orange
                      ? KColors.medium
                      : KColors.weak,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    position.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (canClick)
                  Icon(Icons.search, size: 16, color: Colors.grey[600]),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Compétences : ${position.requiredSkills.join(', ')}",
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissingForFullBlock(
    Truck truck,
    CrewPosition position,
    User? currentUser,
    Planning? currentPlanning,
    Function(Truck, CrewPosition)? onReplacementSearch,
  ) {
    final canClick =
        currentUser != null &&
        onReplacementSearch != null &&
        (currentUser.admin ||
            (currentUser.status == KConstants.statusChief &&
                currentUser.team == currentPlanning?.team) ||
            (currentUser.status == KConstants.statusLeader));

    return GestureDetector(
      onTap: canClick ? () => onReplacementSearch(truck, position) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: KColors.medium.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: KColors.medium.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_circle_outline, size: 18, color: KColors.medium),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    position.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (canClick)
                  Icon(Icons.search, size: 16, color: Colors.grey[600]),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Compétences : ${position.requiredSkills.join(', ')}",
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissingForFullBlockFromCrewPosition(
    Truck truck,
    CrewPosition position,
    User? currentUser,
    Planning? currentPlanning,
    Function(Truck, CrewPosition)? onReplacementSearch,
  ) {
    final canClick =
        currentUser != null &&
        onReplacementSearch != null &&
        (currentUser.admin ||
            (currentUser.status == KConstants.statusChief &&
                currentUser.team == currentPlanning?.team) ||
            (currentUser.status == KConstants.statusLeader));

    return GestureDetector(
      onTap: canClick ? () => onReplacementSearch(truck, position) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: KColors.medium.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: KColors.medium.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_circle_outline, size: 18, color: KColors.medium),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    position.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (canClick)
                  Icon(Icons.search, size: 16, color: Colors.grey[600]),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Compétences : ${position.requiredSkills.join(', ')}",
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApprenticeBlock(Truck truck, CrewResult crewResult) {
    // Map vehicle types to apprentice skills
    String? apprenticeSkill;
    if (truck.type == 'VSAV') {
      apprenticeSkill = KSkills.suapA;
    } else if (truck.type == 'VTU' || truck.type == 'PPBE') {
      apprenticeSkill = KSkills.ppbeA;
    } else if (truck.type == 'FPT') {
      apprenticeSkill = KSkills.incA;
    }

    if (apprenticeSkill == null) return const SizedBox.shrink();

    // Hide apprentice block for degraded (orange) or incomplete (red) vehicles
    if (crewResult.status == VehicleStatus.orange ||
        crewResult.status == VehicleStatus.red) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[400]!),
      ),
      child: Row(
        children: [
          Icon(Icons.school, color: Colors.grey[700]),
          const SizedBox(width: 8),
          Text(
            apprenticeSkill.replaceAll(' A', ''),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildStatusBadge(CrewResult crewResult) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _statusToColor(crewResult.status).withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: _statusToColor(crewResult.status).withOpacity(0.5),
      ),
    ),
    child: Row(
      children: [
        Icon(
          crewResult.status == VehicleStatus.green
              ? Icons.check_circle
              : crewResult.status == VehicleStatus.orange
              ? Icons.warning
              : Icons.error,
          color: _statusToColor(crewResult.status),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            crewResult.statusLabel,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _statusToColor(crewResult.status),
            ),
          ),
        ),
      ],
    ),
  );
}

Color _statusToColor(VehicleStatus status) {
  switch (status) {
    case VehicleStatus.green:
      return KColors.strong;
    case VehicleStatus.orange:
      return KColors.medium;
    case VehicleStatus.red:
      return KColors.weak;
    case VehicleStatus.grey:
      return Colors.grey;
  }
}
