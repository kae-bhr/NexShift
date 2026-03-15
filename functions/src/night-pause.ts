import {onSchedule} from "firebase-functions/v2/scheduler";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

/**
 * Cloud Function pour envoyer les vagues de notifications en attente
 * après la fin de la pause nocturne.
 *
 * S'exécute toutes les 15 minutes pour vérifier si la pause nocturne
 * vient de se terminer et s'il y a des vagues en attente.
 *
 * Parcourt : sdis/{sdisId}/stations/{stationId}
 */
export const sendPendingWavesAfterNightPause = onSchedule(
  {
    region: "europe-west1",
    schedule: "every 15 minutes",
    timeZone: "Europe/Paris",
  },
  async () => {
    const db = getFirestore();
    console.log("🌙 Checking for pending waves after night pause...");

    try {
      const now = new Date();
      const parisNow = new Date(
        now.toLocaleString("en-US", {timeZone: "Europe/Paris"}),
      );
      const currentHour = parisNow.getHours();
      const currentMinute = parisNow.getMinutes();
      const currentTimeMinutes = currentHour * 60 + currentMinute;

      // Parcourir toutes les stations avec pause nocturne activée
      // Utilise collectionGroup car les documents sdis/{sdisId} peuvent être implicites
      const stationsSnapshot = await db
        .collectionGroup("stations")
        .where("nightPauseEnabled", "==", true)
        .get();

      for (const stationDoc of stationsSnapshot.docs) {
        const stationPath = stationDoc.ref.path;
        const parts = stationPath.split("/");
        if (parts.length !== 4 || parts[0] !== "sdis" || parts[2] !== "stations") continue;

        {
          const station = stationDoc.data();
          const stationId = stationDoc.id;

          // Parser les heures de pause
          const pauseEnd = station.nightPauseEnd || "06:00";
          const [endHour, endMinute] = pauseEnd.split(":").map(Number);
          const pauseEndMinutes = endHour * 60 + endMinute;

          // Vérifier si on est dans la fenêtre de 15 minutes après la fin de la pause
          const minutesSincePauseEnd = currentTimeMinutes - pauseEndMinutes;
          if (minutesSincePauseEnd < 0 || minutesSincePauseEnd >= 15) {
            continue;
          }

          console.log(
            `  Station ${stationId}: night pause ended at ${pauseEnd}, ` +
            "processing pending waves...",
          );

          // Récupérer les demandes en attente pour cette station
          const pendingRequests = await db
            .collection(`${stationPath}/replacements/automatic/replacementRequests`)
            .where("status", "==", "pending")
            .get();

          let processedCount = 0;

          for (const requestDoc of pendingRequests.docs) {
            const request = requestDoc.data();
            const lastWaveSentAt = request.lastWaveSentAt?.toDate();

            if (!lastWaveSentAt) continue;

            // Vérifier si la dernière vague a été envoyée pendant la pause nocturne
            const lastWaveParis = new Date(
              lastWaveSentAt.toLocaleString("en-US", {timeZone: "Europe/Paris"}),
            );

            const pauseStart = station.nightPauseStart || "23:00";
            const [startHour, startMinute] = pauseStart.split(":").map(Number);

            const lastWaveHour = lastWaveParis.getHours();
            const lastWaveMinutes = lastWaveHour * 60 + lastWaveParis.getMinutes();
            const pauseStartMinutes = startHour * 60 + startMinute;

            // La vague ne doit pas dater de plus de 24h (évite de reprendre des
            // vagues anciennes qui n'ont rien à voir avec la pause de cette nuit)
            const ageMs = now.getTime() - lastWaveSentAt.getTime();
            if (ageMs > 24 * 60 * 60 * 1000) continue;

            // Déterminer si la dernière vague est tombée pendant la pause
            let wasDuringPause = false;
            if (pauseStartMinutes > pauseEndMinutes) {
              // Pause traversant minuit (ex: 23:00 - 06:00)
              wasDuringPause =
                lastWaveMinutes >= pauseStartMinutes ||
                lastWaveMinutes < pauseEndMinutes;
            } else {
              wasDuringPause =
                lastWaveMinutes >= pauseStartMinutes &&
                lastWaveMinutes < pauseEndMinutes;
            }

            if (!wasDuringPause) continue;

            const currentWave = request.currentWave || 0;
            if (currentWave >= 5) continue;

            // Relancer le timer de vague
            await requestDoc.ref.update({
              lastWaveSentAt: Timestamp.now(),
              nightPauseResumedAt: Timestamp.now(),
            });

            processedCount++;
          }

          if (processedCount > 0) {
            console.log(
              `  ✅ Station ${stationId}: ${processedCount} ` +
              "demande(s) relancée(s) après pause nocturne",
            );
          }
        }
      }
    } catch (error) {
      console.error("💥 Error processing night pause waves:", error);
    }
  },
);

/**
 * Helper pour vérifier si un moment donné tombe pendant la pause nocturne
 * d'une station donnée.
 *
 * @param {string} sdisId - ID du SDIS
 * @param {string} stationId - ID de la station
 * @return {Promise<boolean>} true si on est actuellement en pause nocturne
 */
export async function isInNightPause(
  sdisId: string,
  stationId: string,
): Promise<boolean> {
  const db = getFirestore();
  const stationDoc = await db
    .doc(`sdis/${sdisId}/stations/${stationId}`)
    .get();

  if (!stationDoc.exists) return false;

  const station = stationDoc.data();
  if (!station?.nightPauseEnabled) return false;

  const now = new Date();
  const parisNow = new Date(
    now.toLocaleString("en-US", {timeZone: "Europe/Paris"}),
  );
  const currentHour = parisNow.getHours();
  const currentMinute = parisNow.getMinutes();
  const currentTimeMinutes = currentHour * 60 + currentMinute;

  const pauseStart = station.nightPauseStart || "23:00";
  const pauseEnd = station.nightPauseEnd || "06:00";
  const [startH, startM] = pauseStart.split(":").map(Number);
  const [endH, endM] = pauseEnd.split(":").map(Number);
  const startMinutes = startH * 60 + startM;
  const endMinutes = endH * 60 + endM;

  if (startMinutes > endMinutes) {
    return currentTimeMinutes >= startMinutes || currentTimeMinutes < endMinutes;
  } else {
    return currentTimeMinutes >= startMinutes && currentTimeMinutes < endMinutes;
  }
}
