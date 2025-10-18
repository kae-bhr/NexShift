import 'package:nexshift_app/core/data/models/subshift_model.dart';

/// Extension utilitaire pour firstWhereOrNull
extension IterableFirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

/// Normalise une liste de subshifts pour un agent donné, en gérant les cascades de remplacements.
/// Par exemple :
///   - B remplace A de 20h à 22h
///   - C remplace B de 21h à 22h
/// devient :
///   - B remplace A de 20h à 21h
///   - C remplace A de 21h à 22h
List<Subshift> normalizeSubshifts(List<Subshift> subshifts) {
  if (subshifts.isEmpty) return [];
  final planningId = subshifts.first.planningId;
  final replacedId = subshifts.first.replacedId;
  final filtered = subshifts
      .where((s) => s.planningId == planningId && s.replacedId == replacedId)
      .toList();
  filtered.sort((a, b) => a.start.compareTo(b.start));
  final result = <Subshift>[];
  for (var i = 0; i < filtered.length; i++) {
    final current = filtered[i];
    final next = filtered
        .skip(i + 1)
        .firstWhereOrNull(
          (s) =>
              s.start.isBefore(current.end) &&
              s.replacerId != current.replacerId &&
              s.start.isAfter(current.start),
        );
    if (next != null) {
      if (current.start.isBefore(next.start)) {
        result.add(
          Subshift(
            id: current.id,
            replacedId: current.replacedId,
            replacerId: current.replacerId,
            start: current.start,
            end: next.start,
            planningId: current.planningId,
          ),
        );
      }
      result.add(
        Subshift(
          id: next.id,
          replacedId: current.replacedId,
          replacerId: next.replacerId,
          start: next.start,
          end: next.end.isBefore(current.end) ? next.end : current.end,
          planningId: current.planningId,
        ),
      );
      if (current.end.isAfter(next.end)) {
        result.add(
          Subshift(
            id: '${current.id}_tail',
            replacedId: current.replacedId,
            replacerId: current.replacerId,
            start: next.end,
            end: current.end,
            planningId: current.planningId,
          ),
        );
      }
    } else {
      result.add(current);
    }
  }
  // Fusionner les subshifts consécutifs identiques
  final merged = <Subshift>[];
  for (final s in result) {
    if (merged.isNotEmpty &&
        merged.last.replacerId == s.replacerId &&
        merged.last.end.isAtSameMomentAs(s.start)) {
      merged[merged.length - 1] = Subshift(
        id: merged.last.id,
        replacedId: merged.last.replacedId,
        replacerId: merged.last.replacerId,
        start: merged.last.start,
        end: s.end,
        planningId: merged.last.planningId,
      );
    } else {
      merged.add(s);
    }
  }
  return merged;
}

/// Résout les cascades de remplacements pour pointer directement vers l'agent original
/// ET découpe les périodes pour gérer les chevauchements.
///
/// Par exemple :
///   - B remplace A de 20h à 23h
///   - C remplace B de 21h à 22h
/// devient :
///   - B remplace A de 20h à 21h
///   - C remplace A de 21h à 22h
///   - B remplace A de 22h à 23h
///
/// Cette fonction :
/// 1. Résout les cascades pour pointer vers l'agent original
/// 2. Découpe les périodes pour montrer correctement les remplacements successifs
List<Subshift> resolveReplacementCascades(List<Subshift> subshifts) {
  if (subshifts.isEmpty) return [];

  // Étape 1: Résoudre les cascades pour pointer vers l'agent original
  final List<Subshift> resolvedSubshifts = [];

  for (final subshift in subshifts) {
    String finalReplacedId = subshift.replacedId;

    // Remonter la chaîne de remplacements pour trouver l'agent original
    bool foundOriginal = false;
    int maxIterations = 100;
    int iteration = 0;

    while (!foundOriginal && iteration < maxIterations) {
      iteration++;

      final parentReplacement = subshifts.firstWhereOrNull(
        (s) => s.replacerId == finalReplacedId && s.id != subshift.id,
      );

      if (parentReplacement != null) {
        finalReplacedId = parentReplacement.replacedId;
      } else {
        foundOriginal = true;
      }
    }

    resolvedSubshifts.add(
      Subshift(
        id: subshift.id,
        replacedId: finalReplacedId,
        replacerId: subshift.replacerId,
        start: subshift.start,
        end: subshift.end,
        planningId: subshift.planningId,
      ),
    );
  }

  // Étape 2: Grouper par planningId et replacedId
  final Map<String, Map<String, List<Subshift>>> grouped = {};

  for (final sub in resolvedSubshifts) {
    grouped.putIfAbsent(sub.planningId, () => {});
    grouped[sub.planningId]!.putIfAbsent(sub.replacedId, () => []);
    grouped[sub.planningId]![sub.replacedId]!.add(sub);
  }

  // Étape 3: Pour chaque groupe, découper les périodes qui se chevauchent
  final List<Subshift> result = [];

  for (final planningEntry in grouped.entries) {
    for (final replacedEntry in planningEntry.value.entries) {
      final subList = replacedEntry.value;
      subList.sort((a, b) => a.start.compareTo(b.start));

      // Collecter tous les points temporels critiques
      final Set<DateTime> criticalPoints = {};
      for (final sub in subList) {
        criticalPoints.add(sub.start);
        criticalPoints.add(sub.end);
      }

      final sortedPoints = criticalPoints.toList()..sort();

      // Pour chaque intervalle entre deux points critiques consécutifs,
      // déterminer qui remplace l'agent
      for (int i = 0; i < sortedPoints.length - 1; i++) {
        final intervalStart = sortedPoints[i];
        final intervalEnd = sortedPoints[i + 1];

        // Trouver quel remplacement est actif dans cet intervalle
        // (on prend le dernier qui commence avant ou à intervalStart)
        Subshift? activeReplacement;

        for (final sub in subList) {
          if ((sub.start.isBefore(intervalStart) ||
                  sub.start.isAtSameMomentAs(intervalStart)) &&
              (sub.end.isAfter(intervalStart))) {
            // Ce remplacement couvre le début de l'intervalle
            // Si plusieurs remplacements couvrent, on prend le dernier commencé
            if (activeReplacement == null ||
                sub.start.isAfter(activeReplacement.start)) {
              activeReplacement = sub;
            }
          }
        }

        // Si un remplacement est actif, créer un segment
        if (activeReplacement != null) {
          result.add(
            Subshift(
              id: '${activeReplacement.id}_${intervalStart.millisecondsSinceEpoch}',
              replacedId: activeReplacement.replacedId,
              replacerId: activeReplacement.replacerId,
              start: intervalStart,
              end: intervalEnd,
              planningId: activeReplacement.planningId,
            ),
          );
        }
      }
    }
  }

  // Étape 4: Fusionner les segments consécutifs identiques
  result.sort((a, b) {
    final cmp = a.replacedId.compareTo(b.replacedId);
    if (cmp != 0) return cmp;
    return a.start.compareTo(b.start);
  });

  final List<Subshift> merged = [];
  for (final sub in result) {
    if (merged.isNotEmpty &&
        merged.last.replacedId == sub.replacedId &&
        merged.last.replacerId == sub.replacerId &&
        merged.last.planningId == sub.planningId &&
        merged.last.end.isAtSameMomentAs(sub.start)) {
      // Fusionner avec le précédent
      merged[merged.length - 1] = Subshift(
        id: merged.last.id,
        replacedId: merged.last.replacedId,
        replacerId: merged.last.replacerId,
        start: merged.last.start,
        end: sub.end,
        planningId: merged.last.planningId,
      );
    } else {
      merged.add(sub);
    }
  }

  return merged;
}
