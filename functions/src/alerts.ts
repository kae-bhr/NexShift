import {onSchedule} from "firebase-functions/v2/scheduler";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

/**
 * Helper : récupérer toutes les paires (sdisId, stationId, stationPath)
 */
async function getAllStationPaths(): Promise<
  Array<{sdisId: string; stationId: string; stationPath: string}>
> {
  const db = getFirestore();
  const result: Array<{sdisId: string; stationId: string; stationPath: string}> = [];

  const sdisSnapshot = await db.collection("sdis").get();
  for (const sdisDoc of sdisSnapshot.docs) {
    const sdisId = sdisDoc.id;
    const stationsSnapshot = await db
      .collection(`sdis/${sdisId}/stations`)
      .get();

    for (const stationDoc of stationsSnapshot.docs) {
      result.push({
        sdisId,
        stationId: stationDoc.id,
        stationPath: `sdis/${sdisId}/stations/${stationDoc.id}`,
      });
    }
  }

  return result;
}

/**
 * Rappel quotidien d'astreinte
 * S'exécute toutes les heures pour couvrir toutes les heures configurées.
 * Pour chaque utilisateur avec personalAlertEnabled = true :
 *   - Si l'heure courante (Europe/Paris) == personalAlertHour
 *   - Cherche les astreintes chevauchant les prochaines 24h
 *   - Envoie un récapitulatif si au moins une astreinte trouvée
 */
export const sendDailyShiftReminder = onSchedule(
  {
    region: "europe-west1",
    schedule: "every 1 hours",
    timeZone: "Europe/Paris",
  },
  async () => {
    const db = getFirestore();
    console.log("🔔 [Rappel quotidien] Vérification des rappels quotidiens...");

    try {
      const stationPaths = await getAllStationPaths();

      // Heure courante en Europe/Paris
      const nowUtc = new Date();
      const parisNow = new Date(
        nowUtc.toLocaleString("en-US", {timeZone: "Europe/Paris"}),
      );
      const currentHour = parisNow.getHours();

      const windowStart = nowUtc;
      const windowEnd = new Date(nowUtc.getTime() + 24 * 60 * 60 * 1000);

      let remindersSent = 0;

      for (const {stationPath} of stationPaths) {
        // Utilisateurs avec rappel quotidien activé
        const usersSnapshot = await db
          .collection(`${stationPath}/users`)
          .where("personalAlertEnabled", "==", true)
          .get();

        if (usersSnapshot.empty) continue;

        // Filtrer en mémoire sur l'heure (gère les documents anciens sans personalAlertHour)
        const eligibleUsers = usersSnapshot.docs.filter((doc) => {
          const hour = doc.data().personalAlertHour;
          const effectiveHour = (hour === undefined || hour === null) ? 18 : hour;
          return effectiveHour === currentHour;
        });

        for (const userDoc of eligibleUsers) {
          const userId = userDoc.id;

          // Plannings où l'agent est présent (filtre temporel entièrement en mémoire
          // pour éviter l'index composite array-contains + range)
          const planningsSnapshot = await db
            .collection(`${stationPath}/plannings`)
            .where("agentsId", "array-contains", userId)
            .get();

          const overlapping = planningsSnapshot.docs.filter((doc) => {
            const data = doc.data();
            const startDate: Date =
              data.startTime?.toDate?.() ?? data.startDate?.toDate?.();
            const endDate: Date =
              data.endTime?.toDate?.() ?? data.endDate?.toDate?.();
            return startDate && endDate &&
              startDate < windowEnd &&
              endDate > windowStart;
          });

          if (overlapping.length === 0) continue;

          const planningsSummary = overlapping.map((doc) => {
            const data = doc.data();
            const startDate: Date =
              data.startTime?.toDate?.() ?? data.startDate?.toDate?.();
            const endDate: Date =
              data.endTime?.toDate?.() ?? data.endDate?.toDate?.();
            return {
              planningId: doc.id,
              startDate: startDate.toISOString(),
              endDate: endDate.toISOString(),
              team: (data.team as string) || "",
            };
          });

          await db.collection(`${stationPath}/notificationTriggers`).add({
            type: "daily_shift_reminder",
            targetUserIds: [userId],
            title: "⏰ Astreintes à venir",
            body: `${overlapping.length} astreinte(s) dans les prochaines 24h`,
            data: {
              plannings: planningsSummary,
            },
            createdAt: Timestamp.now(),
            processed: false,
          });

          remindersSent++;
        }
      }

      console.log(`✅ [Rappel quotidien] ${remindersSent} rappel(s) envoyé(s)`);
    } catch (error) {
      console.error("💥 [Rappel quotidien] Erreur:", error);
    }
  },
);

/**
 * Formater une date au format français DD/MM/YYYY HH:mm
 */
export function formatDateFR(date: Date): string {
  const parisDate = new Date(
    date.toLocaleString("en-US", {timeZone: "Europe/Paris"}),
  );
  const day = String(parisDate.getDate()).padStart(2, "0");
  const month = String(parisDate.getMonth() + 1).padStart(2, "0");
  const year = parisDate.getFullYear();
  const hours = String(parisDate.getHours()).padStart(2, "0");
  const minutes = String(parisDate.getMinutes()).padStart(2, "0");
  return `${day}/${month}/${year} ${hours}:${minutes}`;
}

/**
 * Formater uniquement la date (sans l'année) : DD/MM
 */
export function formatShortDateFR(date: Date): string {
  const parisDate = new Date(
    date.toLocaleString("en-US", {timeZone: "Europe/Paris"}),
  );
  const day = String(parisDate.getDate()).padStart(2, "0");
  const month = String(parisDate.getMonth() + 1).padStart(2, "0");
  return `${day}/${month}`;
}

/**
 * Formater uniquement l'heure : HHhMM (ex: 19h, 04h30)
 */
export function formatTimeFR(date: Date): string {
  const parisDate = new Date(
    date.toLocaleString("en-US", {timeZone: "Europe/Paris"}),
  );
  const hours = String(parisDate.getHours()).padStart(2, "0");
  const minutes = String(parisDate.getMinutes()).padStart(2, "0");
  return minutes !== "00" ? `${hours}h${minutes}` : `${hours}h`;
}
