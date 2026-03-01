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

class _VehicleDetailDialog extends StatelessWidget {
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

  bool get _canSearch =>
      currentUser != null &&
      onReplacementSearch != null &&
      (currentUser!.admin ||
          (currentUser!.status == KConstants.statusChief &&
              currentUser!.team == currentPlanning?.team) ||
          (currentUser!.status == KConstants.statusLeader));

  @override
  Widget build(BuildContext context) {
    final problematicRanges = (timeRanges ?? [])
        .where(
          (tr) =>
              tr.status == VehicleStatus.orange ||
              tr.status == VehicleStatus.red,
        )
        .toList();

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      title: Row(
        children: [
          BackButton(onPressed: () => Navigator.pop(context)),
          Icon(icon, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusPill(crewResult),
              if (problematicRanges.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Plages horaires problématiques',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.grey[700],
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 10),
                ...problematicRanges.map(
                  (range) => _buildRangeSection(range),
                ),
              ] else ...[
                const SizedBox(height: 16),
                _buildAllPositionsList(),
              ],
              _buildApprenticeBlock(truck, crewResult),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(CrewResult result) {
    final color = _statusToColor(result.status);
    final icon = result.status == VehicleStatus.green
        ? Icons.check_circle_rounded
        : result.status == VehicleStatus.orange
        ? Icons.warning_rounded
        : Icons.error_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            result.statusLabel,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeSection(TimeRangeStatus range) {
    final color = _statusToColor(range.status);
    final formatter = DateFormat('dd/MM HH:mm');
    final totalMissing =
        range.unfilledCrewPositions.length + range.missingForFull.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header de la plage
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  range.status == VehicleStatus.orange
                      ? Icons.warning_rounded
                      : Icons.error_rounded,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${formatter.format(range.start)} → ${formatter.format(range.end)}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$totalMissing poste${totalMissing > 1 ? 's' : ''}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Postes vacants (rouge/critique)
          if (range.unfilledCrewPositions.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                children: range.unfilledCrewPositions
                    .map(
                      (p) => _buildPositionTile(
                        position: p,
                        status: range.status,
                        isMissingForFull: false,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          // Postes manquants pour équipage complet (orange)
          if (range.missingForFull.isNotEmpty) ...[
            if (range.unfilledCrewPositions.isEmpty) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (range.unfilledCrewPositions.isNotEmpty) ...[
                    Text(
                      'Pour équipage complet :',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: KColors.medium,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  ...range.missingForFull.map(
                    (p) => _buildPositionTile(
                      position: p,
                      status: VehicleStatus.orange,
                      isMissingForFull: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAllPositionsList() {
    final allPositions = crewResult.positions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Équipage',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Colors.grey[700],
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 10),
        ...allPositions.map(
          (assignment) => _buildPositionTile(
            position: assignment.position,
            status: crewResult.status,
            isMissingForFull: false,
            isFilled: assignment.isFilled,
            isFallback: assignment.isFallback,
          ),
        ),
        if (crewResult.status == VehicleStatus.orange &&
            crewResult.missingForFull.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Pour équipage complet :',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: KColors.medium,
            ),
          ),
          const SizedBox(height: 6),
          ...crewResult.missingForFull.map(
            (p) => _buildPositionTile(
              position: p,
              status: VehicleStatus.orange,
              isMissingForFull: true,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPositionTile({
    required CrewPosition position,
    required VehicleStatus status,
    bool isMissingForFull = false,
    bool isFilled = false,
    bool isFallback = false,
  }) {
    final Color color;
    final IconData leadingIcon;

    if (isFilled) {
      color = KColors.strong;
      leadingIcon = Icons.check_circle_rounded;
    } else if (isMissingForFull) {
      color = KColors.medium;
      leadingIcon = Icons.person_add_rounded;
    } else {
      color = status == VehicleStatus.orange ? KColors.medium : KColors.weak;
      leadingIcon = Icons.person_search_rounded;
    }

    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(leadingIcon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  position.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isFilled ? Colors.grey[800] : color,
                  ),
                ),
                if (position.requiredSkills.isNotEmpty)
                  Text(
                    position.requiredSkills.join(', '),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (isFallback)
            Tooltip(
              message: 'Poste pourvu par un équipier',
              child: InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
            ),
          if (!isFilled && _canSearch)
            TextButton.icon(
              onPressed: () => onReplacementSearch!(truck, position),
              icon: const Icon(Icons.search_rounded, size: 15),
              label: const Text('Chercher', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildApprenticeBlock(Truck truck, CrewResult crewResult) {
    String? apprenticeSkill;
    if (truck.type == 'VSAV') {
      apprenticeSkill = KSkills.suapA;
    } else if (truck.type == 'VTU' || truck.type == 'PPBE') {
      apprenticeSkill = KSkills.ppbeA;
    } else if (truck.type == 'FPT') {
      apprenticeSkill = KSkills.incA;
    }

    if (apprenticeSkill == null) return const SizedBox.shrink();

    if (crewResult.status == VehicleStatus.orange ||
        crewResult.status == VehicleStatus.red) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Icon(Icons.school_rounded, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            apprenticeSkill.replaceAll(' A', ''),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
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
