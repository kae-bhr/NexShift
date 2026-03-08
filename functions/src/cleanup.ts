import {onSchedule} from "firebase-functions/v2/scheduler";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

/**
 * Résout le chemin complet d'une collection dans une station.
 * Gère les collections imbriquées sous replacements/.
 */
function getStationCollectionPath(
  stationPath: string,
  collectionKey: string,
): string {
  const nestedPaths: Record<string, string> = {
    subshifts: "replacements/all/subshifts",
    shiftExchangeRequests: "replacements/exchange/shiftExchangeRequests",
    shiftExchangeProposals: "replacements/exchange/shiftExchangeProposals",
    replacementAcceptances: "replacements/automatic/replacementAcceptances",
  };

  const subPath = nestedPaths[collectionKey] || collectionKey;
  return `${stationPath}/${subPath}`;
}

/**
 * Cloud Function de nettoyage automatique des anciennes données
 * S'exécute chaque dimanche à 3h du matin (Europe/Paris)
 * Supprime les documents de plus de 6 mois
 *
 * Parcourt tous les SDIS et toutes les casernes :
 * sdis/{sdisId}/stations/{stationId}/...
 */
export const cleanupOldData = onSchedule(
  {
    region: "europe-west1",
    schedule: "0 3 * * 0", // Chaque dimanche à 3h
    timeZone: "Europe/Paris",
  },
  async () => {
    const db = getFirestore();
    const sixMonthsAgo = new Date();
    sixMonthsAgo.setMonth(sixMonthsAgo.getMonth() - 6);
    const cutoffTimestamp = Timestamp.fromDate(sixMonthsAgo);

    console.log(
      `🗑️ Starting cleanup of data older than ${sixMonthsAgo.toISOString()}`,
    );

    let totalDeleted = 0;

    // Collections à nettoyer au niveau station
    const collectionsToClean: Array<{
      key: string;
      dateField: string;
      label: string;
    }> = [
      {key: "plannings", dateField: "endDate", label: "Plannings"},
      {key: "replacementRequests", dateField: "createdAt", label: "ReplacementRequests"},
      {key: "subshifts", dateField: "end", label: "Subshifts"},
      {key: "availabilities", dateField: "end", label: "Availabilities"},
      {key: "notificationTriggers", dateField: "processedAt", label: "NotificationTriggers"},
      {key: "shiftExchangeRequests", dateField: "completedAt", label: "ShiftExchangeRequests"},
      {key: "replacementAcceptances", dateField: "createdAt", label: "ReplacementAcceptances"},
      {key: "shiftExchangeProposals", dateField: "createdAt", label: "ShiftExchangeProposals"},
    ];

    // Parcourir toutes les stations via collectionGroup
    // (les documents sdis/{sdisId} peuvent être implicites sans document explicite)
    const stationsSnapshot = await db.collectionGroup("stations").get();

    for (const stationDoc of stationsSnapshot.docs) {
      const stationRefPath = stationDoc.ref.path;
      const parts = stationRefPath.split("/");
      if (parts.length !== 4 || parts[0] !== "sdis" || parts[2] !== "stations") continue;
      const sdisId = parts[1];
      const stationPath = stationRefPath;
      console.log(`  📍 Station: ${stationDoc.id} (SDIS: ${sdisId})`);

        for (const {key, dateField, label} of collectionsToClean) {
          try {
            const collectionPath = getStationCollectionPath(stationPath, key);
            const snapshot = await db
              .collection(collectionPath)
              .where(dateField, "<", cutoffTimestamp)
              .limit(500)
              .get();

            if (snapshot.empty) continue;

            const batch = db.batch();
            snapshot.docs.forEach((doc) => batch.delete(doc.ref));
            await batch.commit();
            totalDeleted += snapshot.size;

            console.log(
              `    🗑️ ${label}: ${snapshot.size} document(s) supprimé(s)`,
            );
          } catch (error) {
            console.error(`    ❌ Erreur ${label}:`, error);
          }
        }
    }

    console.log(
      `✅ Nettoyage terminé: ${totalDeleted} document(s) supprimé(s) au total`,
    );
  },
);
