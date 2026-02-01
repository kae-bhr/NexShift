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
 * Alerte A : Rappel personnel avant astreinte
 * S'exécute toutes les heures.
 * Envoie une notification aux agents dont l'astreinte démarre dans X heures.
 *
 * Parcourt : sdis/{sdisId}/stations/{stationId}/users et /plannings
 */
export const sendPersonalShiftAlerts = onSchedule(
  {
    schedule: "every 1 hours",
    timeZone: "Europe/Paris",
  },
  async () => {
    const db = getFirestore();
    console.log("🔔 [Alerte A] Vérification des rappels personnels avant astreinte...");

    try {
      const stationPaths = await getAllStationPaths();
      const now = new Date();
      let alertsSent = 0;

      for (const {stationPath} of stationPaths) {
        // Utilisateurs avec alerte personnelle activée
        const usersSnapshot = await db
          .collection(`${stationPath}/users`)
          .where("personalAlertEnabled", "==", true)
          .get();

        if (usersSnapshot.empty) continue;

        for (const userDoc of usersSnapshot.docs) {
          const user = userDoc.data();
          const userId = userDoc.id;
          const hoursBeforeShift = user.personalAlertBeforeShiftHours || 1;

          // Fenêtre de temps : astreinte démarrant dans X heures (+/- 30 min)
          const targetTime = new Date(now.getTime() + hoursBeforeShift * 60 * 60 * 1000);
          const windowStart = new Date(targetTime.getTime() - 30 * 60 * 1000);
          const windowEnd = new Date(targetTime.getTime() + 30 * 60 * 1000);

          const planningsSnapshot = await db
            .collection(`${stationPath}/plannings`)
            .where("agentsId", "array-contains", userId)
            .where("startDate", ">=", Timestamp.fromDate(windowStart))
            .where("startDate", "<=", Timestamp.fromDate(windowEnd))
            .limit(1)
            .get();

          if (planningsSnapshot.empty) continue;

          const planning = planningsSnapshot.docs[0].data();
          const startDate = planning.startDate.toDate();
          const formattedDate = formatDateFR(startDate);

          await db.collection(`${stationPath}/notificationTriggers`).add({
            type: "personal_shift_alert",
            targetUserIds: [userId],
            title: "⏰ Rappel d'astreinte",
            body: `Votre astreinte commence le ${formattedDate}`,
            data: {planningId: planningsSnapshot.docs[0].id},
            createdAt: Timestamp.now(),
            processed: false,
          });

          alertsSent++;
        }
      }

      console.log(`✅ [Alerte A] ${alertsSent} rappel(s) personnel(s) envoyé(s)`);
    } catch (error) {
      console.error("💥 [Alerte A] Erreur:", error);
    }
  },
);

/**
 * Alerte B : Rappel chef d'équipe - changements astreinte
 * S'exécute toutes les heures.
 *
 * Parcourt : sdis/{sdisId}/stations/{stationId}/users, /plannings, /replacements/all/subshifts
 */
export const sendChiefShiftAlerts = onSchedule(
  {
    schedule: "every 1 hours",
    timeZone: "Europe/Paris",
  },
  async () => {
    const db = getFirestore();
    console.log("🔔 [Alerte B] Vérification des rappels chefs avant astreinte...");

    try {
      const stationPaths = await getAllStationPaths();
      const now = new Date();
      let alertsSent = 0;

      for (const {stationPath} of stationPaths) {
        const chiefsSnapshot = await db
          .collection(`${stationPath}/users`)
          .where("chiefAlertEnabled", "==", true)
          .get();

        const chiefs = chiefsSnapshot.docs.filter((doc) => {
          const data = doc.data();
          return data.status === "chief" || data.status === "leader";
        });

        if (chiefs.length === 0) continue;

        for (const chiefDoc of chiefs) {
          const chief = chiefDoc.data();
          const chiefId = chiefDoc.id;
          const hoursBeforeShift = chief.chiefAlertBeforeShiftHours || 1;
          const chiefTeam = chief.team;

          if (!chiefTeam) continue;

          const targetTime = new Date(now.getTime() + hoursBeforeShift * 60 * 60 * 1000);
          const windowStart = new Date(targetTime.getTime() - 30 * 60 * 1000);
          const windowEnd = new Date(targetTime.getTime() + 30 * 60 * 1000);

          const planningsSnapshot = await db
            .collection(`${stationPath}/plannings`)
            .where("team", "==", chiefTeam)
            .where("startDate", ">=", Timestamp.fromDate(windowStart))
            .where("startDate", "<=", Timestamp.fromDate(windowEnd))
            .limit(1)
            .get();

          if (planningsSnapshot.empty) continue;

          const planning = planningsSnapshot.docs[0].data();
          const startDate = planning.startDate.toDate();
          const formattedDate = formatDateFR(startDate);

          // Vérifier s'il y a des subshifts (remplacements)
          const subshiftsSnapshot = await db
            .collection(`${stationPath}/replacements/all/subshifts`)
            .where("planningId", "==", planningsSnapshot.docs[0].id)
            .get();

          const hasChanges = !subshiftsSnapshot.empty;
          const bodyMessage = hasChanges
            ? `Pensez à vérifier les changements pour l'astreinte du ${formattedDate} (${subshiftsSnapshot.size} remplacement(s))`
            : `L'astreinte du ${formattedDate} approche. Pensez à effectuer les modifications si nécessaire.`;

          await db.collection(`${stationPath}/notificationTriggers`).add({
            type: "chief_shift_alert",
            targetUserIds: [chiefId],
            title: "📋 Rappel astreinte équipe",
            body: bodyMessage,
            data: {
              planningId: planningsSnapshot.docs[0].id,
              team: chiefTeam,
            },
            createdAt: Timestamp.now(),
            processed: false,
          });

          alertsSent++;
        }
      }

      console.log(`✅ [Alerte B] ${alertsSent} rappel(s) chef(s) envoyé(s)`);
    } catch (error) {
      console.error("💥 [Alerte B] Erreur:", error);
    }
  },
);

/**
 * Alerte C : Astreinte en erreur (anomalies)
 * S'exécute une fois par jour à 8h.
 * Vérifie la cohérence des astreintes futures.
 *
 * Parcourt : sdis/{sdisId}/stations/{stationId} pour config + users + plannings
 */
export const sendAnomalyAlerts = onSchedule(
  {
    schedule: "0 8 * * *", // Chaque jour à 8h
    timeZone: "Europe/Paris",
  },
  async () => {
    const db = getFirestore();
    console.log("🔔 [Alerte C] Vérification des anomalies de planning...");

    try {
      const stationPaths = await getAllStationPaths();
      const now = new Date();
      let alertsSent = 0;

      for (const {stationPath} of stationPaths) {
        // Lire la config station (maxAgentsPerShift)
        const stationDoc = await db.doc(stationPath).get();
        if (!stationDoc.exists) continue;
        const stationData = stationDoc.data();
        const maxAgents = stationData?.maxAgentsPerShift || 6;

        // Chefs avec alerte anomalies activée
        const chiefsSnapshot = await db
          .collection(`${stationPath}/users`)
          .where("anomalyAlertEnabled", "==", true)
          .get();

        const chiefs = chiefsSnapshot.docs.filter((doc) => {
          const data = doc.data();
          return data.status === "chief" || data.status === "leader";
        });

        if (chiefs.length === 0) continue;

        // Grouper les chefs par équipe
        const chiefsByTeam = new Map<string, Array<{id: string; daysBefore: number}>>();
        for (const chiefDoc of chiefs) {
          const chief = chiefDoc.data();
          const team = chief.team;
          if (!team) continue;
          if (!chiefsByTeam.has(team)) chiefsByTeam.set(team, []);
          chiefsByTeam.get(team)!.push({
            id: chiefDoc.id,
            daysBefore: chief.anomalyAlertDaysBefore || 14,
          });
        }

        for (const [team, chiefsInTeam] of chiefsByTeam) {
          const maxDaysBefore = Math.max(...chiefsInTeam.map((c) => c.daysBefore));
          const futureLimit = new Date(now.getTime() + maxDaysBefore * 24 * 60 * 60 * 1000);

          const planningsSnapshot = await db
            .collection(`${stationPath}/plannings`)
            .where("team", "==", team)
            .where("startDate", ">=", Timestamp.fromDate(now))
            .where("startDate", "<=", Timestamp.fromDate(futureLimit))
            .get();

          for (const planningDoc of planningsSnapshot.docs) {
            const planning = planningDoc.data();
            const agentsCount = (planning.agentsId as string[] || []).length;

            if (agentsCount === maxAgents) continue;

            const startDate = planning.startDate.toDate();
            const formattedDate = formatDateFR(startDate);
            const daysUntil = Math.ceil(
              (startDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24),
            );

            const eligibleChiefs = chiefsInTeam
              .filter((c) => daysUntil <= c.daysBefore)
              .map((c) => c.id);

            if (eligibleChiefs.length === 0) continue;

            const anomalyType = agentsCount > maxAgents
              ? `${agentsCount}/${maxAgents} agents (trop d'agents)`
              : `${agentsCount}/${maxAgents} agents (pas assez d'agents)`;

            await db.collection(`${stationPath}/notificationTriggers`).add({
              type: "anomaly_alert",
              targetUserIds: eligibleChiefs,
              title: "⚠️ Anomalie planning",
              body: `Astreinte du ${formattedDate} en erreur : ${anomalyType}`,
              data: {
                planningId: planningDoc.id,
                team: team,
                agentsCount: String(agentsCount),
                maxAgents: String(maxAgents),
              },
              createdAt: Timestamp.now(),
              processed: false,
            });

            alertsSent++;
          }
        }
      }

      console.log(`✅ [Alerte C] ${alertsSent} alerte(s) anomalie(s) envoyée(s)`);
    } catch (error) {
      console.error("💥 [Alerte C] Erreur:", error);
    }
  },
);

/**
 * Formater une date au format français DD/MM/YYYY HH:mm
 */
function formatDateFR(date: Date): string {
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
