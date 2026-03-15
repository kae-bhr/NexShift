/**
 * Vérifie si une période est complètement couverte par des intervalles.
 * Fusionne les intervalles chevauchants et applique une tolérance d'1 minute.
 *
 * @param {Date} targetStart - Début de la période cible
 * @param {Date} targetEnd - Fin de la période cible
 * @param {Array} intervals - Intervalles de couverture
 * @return {boolean} True si complètement couvert
 */
export function checkIfFullyCovered(
  targetStart: Date,
  targetEnd: Date,
  intervals: Array<{start: Date; end: Date}>,
): boolean {
  if (intervals.length === 0) return false;

  const sorted = intervals
    .map((i) => ({start: i.start.getTime(), end: i.end.getTime()}))
    .sort((a, b) => a.start - b.start);

  const targetStartTime = targetStart.getTime();
  const targetEndTime = targetEnd.getTime();

  // Fusionner les intervalles qui se chevauchent ou sont contigus
  const merged: Array<{start: number; end: number}> = [];
  let current = sorted[0];
  for (let i = 1; i < sorted.length; i++) {
    const next = sorted[i];
    if (next.start <= current.end) {
      current = {
        start: Math.min(current.start, next.start),
        end: Math.max(current.end, next.end),
      };
    } else {
      merged.push(current);
      current = next;
    }
  }
  merged.push(current);

  // Vérifier si la période cible est couverte (avec tolérance d'1 minute)
  const tolerance = 60 * 1000;
  for (const interval of merged) {
    if (
      interval.start - tolerance <= targetStartTime &&
      interval.end + tolerance >= targetEndTime
    ) {
      return true;
    }
  }

  return false;
}
