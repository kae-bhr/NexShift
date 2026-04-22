import {onSchedule} from "firebase-functions/v2/scheduler";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {checkIfFullyCovered} from "./planning-utils.js";

/**
 * Helper : récupérer toutes les paires (sdisId, stationId, stationPath)
 * Utilise collectionGroup("stations") car les documents sdis/{sdisId} peuvent
 * être implicites (sans document explicite, seules les sous-collections existent).
 */
async function getAllStationPaths(): Promise<
  Array<{sdisId: string; stationId: string; stationPath: string}>
> {
  const db = getFirestore();
  const result: Array<{sdisId: string; stationId: string; stationPath: string}> = [];

  // collectionGroup liste toutes les collections "stations" à n'importe quelle profondeur
  const stationsSnapshot = await db.collectionGroup("stations").get();

  for (const stationDoc of stationsSnapshot.docs) {
    const stationPath = stationDoc.ref.path; // ex: "sdis/30/stations/station_xxx"
    const parts = stationPath.split("/");
    // Structure attendue : sdis/{sdisId}/stations/{stationId}
    if (parts.length === 4 && parts[0] === "sdis" && parts[2] === "stations") {
      result.push({
        sdisId: parts[1],
        stationId: parts[3],
        stationPath,
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

        if (eligibleUsers.length === 0) continue;

        // Récupérer tous les plannings actifs de la station en une seule query
        // (agents[] est un tableau d'objets — pas de champ agentsId en Firestore)
        const planningsSnapshot = await db
          .collection(`${stationPath}/plannings`)
          .where("endTime", ">", Timestamp.fromDate(windowStart))
          .get();

        // Filtrer en mémoire sur la fenêtre de 24h
        const activePlannings = planningsSnapshot.docs.filter((doc) => {
          const data = doc.data();
          const startDate: Date =
            data.startTime?.toDate?.() ?? data.startDate?.toDate?.();
          return startDate && startDate < windowEnd;
        });

        for (const userDoc of eligibleUsers) {
          const userId = userDoc.id;

          // Plannings pertinents pour cet agent :
          // Cas 1 : il est agent de base ET pas totalement remplacé
          // Cas 2 : il est remplaçant d'un autre agent
          const userPlannings = activePlannings.filter((doc) => {
            const agents = doc.data().agents as Array<{agentId: string; replacedAgentId?: string | null}> | undefined;
            if (!agents) return false;

            // Cas 2 : l'agent est remplaçant dans ce planning
            const isReplacing = agents.some((a) => a.agentId === userId && a.replacedAgentId);
            if (isReplacing) return true;

            // Cas 1 : l'agent est agent de base (sans replacedAgentId)
            const isBaseAgent = agents.some((a) => a.agentId === userId && !a.replacedAgentId);
            if (!isBaseAgent) return false;

            // Vérifier si l'agent de base est totalement remplacé
            const hasAnyReplacement = agents.some((a) => a.replacedAgentId === userId);
            if (!hasAnyReplacement) return true; // Pas du tout remplacé → à notifier

            // Construire les intervalles de couverture par les remplaçants
            type AgentEntry = {agentId: string; replacedAgentId?: string | null; start?: {toDate?: () => Date}; end?: {toDate?: () => Date}};
            const typedAgents = agents as AgentEntry[];
            const baseEntry = typedAgents.find((a) => a.agentId === userId && !a.replacedAgentId);
            if (!baseEntry?.start?.toDate || !baseEntry?.end?.toDate) return true;

            const replacementIntervals = typedAgents
              .filter((a) => a.replacedAgentId === userId && a.start?.toDate && a.end?.toDate)
              .map((a) => ({start: a.start!.toDate!(), end: a.end!.toDate!()}));

            return !checkIfFullyCovered(
              baseEntry.start.toDate(),
              baseEntry.end.toDate(),
              replacementIntervals,
            );
          });

          if (userPlannings.length === 0) continue;

          const planningsSummary = userPlannings.map((doc) => {
            const data = doc.data();
            const startDate: Date =
              data.startTime?.toDate?.() ?? data.startDate?.toDate?.();
            const endDate: Date =
              data.endTime?.toDate?.() ?? data.endDate?.toDate?.();
            const docAgents = (data.agents as Array<{agentId: string; replacedAgentId?: string | null}>) ?? [];
            const isReplacing = docAgents.some((a) => a.agentId === userId && a.replacedAgentId);
            return {
              planningId: doc.id,
              startDate: startDate.toISOString(),
              endDate: endDate.toISOString(),
              team: (data.team as string) || "",
              isReplacing,
            };
          });

          const replacingCount = planningsSummary.filter((p) => p.isReplacing).length;
          const baseCount = planningsSummary.length - replacingCount;

          let body = "";
          if (baseCount > 0 && replacingCount > 0) {
            body = `${baseCount} astreinte(s) + ${replacingCount} remplacement(s) dans les prochaines 24h`;
          } else if (replacingCount > 0) {
            body = `${replacingCount} remplacement(s) dans les prochaines 24h`;
          } else {
            body = `${baseCount} astreinte(s) dans les prochaines 24h`;
          }

          await db.collection(`${stationPath}/notificationTriggers`).add({
            type: "daily_shift_reminder",
            targetUserIds: [userId],
            title: "⏰ Astreintes à venir",
            body,
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
 * Extrait les composantes UTC d'une date.
 * Convention : les timestamps sont stockés en "flat UTC"
 * (06:00 UTC = affichage 06h, aucune conversion de fuseau).
 */
function getUtcComponents(date: Date): {
  day: string; month: string; year: number;
  hours: string; minutes: string;
} {
  return {
    day: String(date.getUTCDate()).padStart(2, "0"),
    month: String(date.getUTCMonth() + 1).padStart(2, "0"),
    year: date.getUTCFullYear(),
    hours: String(date.getUTCHours()).padStart(2, "0"),
    minutes: String(date.getUTCMinutes()).padStart(2, "0"),
  };
}

/**
 * Formater une date au format français DD/MM/YYYY HH:mm
 */
export function formatDateFR(date: Date): string {
  const {day, month, year, hours, minutes} = getUtcComponents(date);
  return `${day}/${month}/${year} ${hours}:${minutes}`;
}

/**
 * Formater uniquement la date (sans l'année) : DD/MM
 */
export function formatShortDateFR(date: Date): string {
  const {day, month} = getUtcComponents(date);
  return `${day}/${month}`;
}

/**
 * Formater uniquement l'heure : HHhMM (ex: 19h, 04h30)
 */
export function formatTimeFR(date: Date): string {
  const {hours, minutes} = getUtcComponents(date);
  return minutes !== "00" ? `${hours}h${minutes}` : `${hours}h`;
}
