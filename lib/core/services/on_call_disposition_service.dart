import 'package:nexshift_app/core/data/models/on_call_level_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';

/// Type de présence d'un agent dans la garde
enum PresenceType { regular, exchange, replacement }

/// Représente un créneau de présence d'un agent dans la garde
class AgentPresenceSlot {
  final String agentId;
  final DateTime start;
  final DateTime end;
  final String levelId;
  final PresenceType type;
  final String? replacedAgentId;
  final bool checkedByChief;

  const AgentPresenceSlot({
    required this.agentId,
    required this.start,
    required this.end,
    required this.levelId,
    required this.type,
    this.replacedAgentId,
    this.checkedByChief = false,
  });
}

class OnCallDispositionService {
  /// Calcule la disposition des agents par niveau d'astreinte.
  /// Lit directement depuis planning.agents — source unique de vérité.
  static Map<String, List<AgentPresenceSlot>> computeDisposition({
    required Planning planning,
    required List<OnCallLevel> levels,
    required Station station,
  }) {
    if (levels.isEmpty) return {};

    final defaultLevelId = station.defaultOnCallLevelId ?? levels.first.id;

    // Mapper chaque PlanningAgent en AgentPresenceSlot
    final slots = planning.agents.map((a) {
      final effectiveLevelId = a.levelId.isNotEmpty ? a.levelId : defaultLevelId;
      final PresenceType type;
      if (a.replacedAgentId != null) {
        type = a.isExchange ? PresenceType.exchange : PresenceType.replacement;
      } else {
        type = PresenceType.regular;
      }

      return AgentPresenceSlot(
        agentId: a.agentId,
        start: a.start,
        end: a.end,
        levelId: effectiveLevelId,
        type: type,
        replacedAgentId: a.replacedAgentId,
        checkedByChief: a.checkedByChief,
      );
    }).toList();

    // Regrouper par niveau et trier
    final result = <String, List<AgentPresenceSlot>>{};
    final sortedLevels = List<OnCallLevel>.from(levels)
      ..sort((a, b) => a.order.compareTo(b.order));

    for (final level in sortedLevels) {
      final levelSlots =
          slots.where((s) => s.levelId == level.id).toList();
      if (levelSlots.isNotEmpty) {
        levelSlots.sort((a, b) => a.start.compareTo(b.start));
        result[level.id] = levelSlots;
      }
    }

    return result;
  }

  /// Calcule le nombre d'agents présents à chaque instant de la garde.
  /// Lit directement depuis planning.agents.
  static ({int min, int max, List<AgentCountIssue> issues})
      computeAgentCount({
    required Planning planning,
  }) {
    final agents = planning.agents;

    if (agents.isEmpty) {
      return (min: 0, max: 0, issues: <AgentCountIssue>[]);
    }

    // Construire les points critiques
    final criticalTimes = <DateTime>{
      planning.startTime,
      planning.endTime,
    };
    for (final a in agents) {
      if (a.start.isAfter(planning.startTime) && a.start.isBefore(planning.endTime)) {
        criticalTimes.add(a.start);
      }
      if (a.end.isAfter(planning.startTime) && a.end.isBefore(planning.endTime)) {
        criticalTimes.add(a.end);
      }
    }

    final sortedTimes = criticalTimes.toList()..sort();

    int minCount = agents.length; // sera réduit
    int maxCount = 0;
    final issues = <AgentCountIssue>[];

    for (int i = 0; i < sortedTimes.length - 1; i++) {
      final rangeStart = sortedTimes[i];
      final rangeEnd = sortedTimes[i + 1];

      if (rangeEnd.difference(rangeStart).inMinutes < 1) continue;

      final sampleTime = rangeStart.add(const Duration(seconds: 30));

      // Compter les agents uniques présents à cet instant
      final presentAgents = <String>{};
      for (final a in agents) {
        if ((a.start.isBefore(sampleTime) || a.start.isAtSameMomentAs(sampleTime)) &&
            a.end.isAfter(sampleTime)) {
          presentAgents.add(a.agentId);
        }
      }
      final count = presentAgents.length;

      if (count < minCount) minCount = count;
      if (count > maxCount) maxCount = count;

      if (count != planning.maxAgents) {
        issues.add(AgentCountIssue(
          start: rangeStart,
          end: rangeEnd,
          count: count,
          expected: planning.maxAgents,
        ));
      }
    }

    if (sortedTimes.length < 2) {
      minCount = agents.length;
      maxCount = agents.length;
    }

    // Fusionner les issues consécutives avec le même count
    final mergedIssues = <AgentCountIssue>[];
    for (final issue in issues) {
      if (mergedIssues.isNotEmpty &&
          mergedIssues.last.count == issue.count &&
          mergedIssues.last.end.isAtSameMomentAs(issue.start)) {
        mergedIssues[mergedIssues.length - 1] = AgentCountIssue(
          start: mergedIssues.last.start,
          end: issue.end,
          count: issue.count,
          expected: issue.expected,
        );
      } else {
        mergedIssues.add(issue);
      }
    }

    return (min: minCount, max: maxCount, issues: mergedIssues);
  }

  /// Détermine le niveau d'astreinte d'un remplacement selon les règles de durée.
  /// Utilitaire utilisé lors de la création/validation d'un remplacement.
  static String getReplacementLevelId({
    required DateTime start,
    required DateTime end,
    required Station station,
    required String defaultLevelId,
  }) {
    if (!station.enableReplacementDurationThreshold) {
      return station.replacementOnCallLevelId ?? defaultLevelId;
    }

    final durationHours = end.difference(start).inMinutes / 60.0;
    final threshold = station.replacementDurationThresholdHours;

    if (durationHours < threshold) {
      return station.shortReplacementLevelId ?? defaultLevelId;
    } else {
      return station.longReplacementLevelId ?? defaultLevelId;
    }
  }
}

/// Décrit un problème de comptage d'agents sur une plage horaire
class AgentCountIssue {
  final DateTime start;
  final DateTime end;
  final int count;
  final int expected;

  const AgentCountIssue({
    required this.start,
    required this.end,
    required this.count,
    required this.expected,
  });
}
