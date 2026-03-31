import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {encryptionKey, decryptPII} from "./crypto-utils.js";
import {checkIfFullyCovered} from "./planning-utils.js";

// Re-export des nouvelles Cloud Functions
export {cleanupOldData} from "./cleanup";
export {sendPendingWavesAfterNightPause} from "./night-pause";
// Désactivé : remplacé par les rappels locaux dans l'app Flutter
// export {sendDailyShiftReminder} from "./alerts";

// Auth & User Management Functions
export {
  createAccount,
  requestMembership,
  handleMembershipRequest,
  reserveMatricule,
  preRegisterAgent,
  addExistingUserToStation,
  updateUserRole,
  removeUserFromStation,
  deleteUser,
  createStationWithCode,
} from "./auth-functions.js";

// User Data Functions (avec déchiffrement PII)
export {
  getUserProfile,
  getStationUsers,
  getMembershipRequests,
  getPendingMembershipRequestsCount,
  getSDISStations,
  getMyMembershipRequests,
  getUserByAuthUidForStation,
  getUsersByStation,
  getEmailByMatricule,
} from "./user-functions.js";

initializeApp();

/**
 * Helper pour formater les dates au format français avec timezone Europe/Paris
 * Format : DD/MM/YYYY HH:mm
 * @param {Date} date - Date to format
 * @return {string} Formatted date string
 */
function formatDate(date: Date): string {
  // Convertir en timezone Europe/Paris (France)
  const parisDate = new Date(date.toLocaleString("en-US", {
    timeZone: "Europe/Paris",
  }));

  const day = String(parisDate.getDate()).padStart(2, "0");
  const month = String(parisDate.getMonth() + 1).padStart(2, "0");
  const year = parisDate.getFullYear();
  const hours = String(parisDate.getHours()).padStart(2, "0");
  const minutes = String(parisDate.getMinutes()).padStart(2, "0");

  return `${day}/${month}/${year} ${hours}:${minutes}`;
}

/** Format court : DD/MM HHh(MM) — ex: "21/05 19h", "22/05 04h30" */
function formatShort(date: Date): string {
  const p = new Date(date.toLocaleString("en-US", {timeZone: "Europe/Paris"}));
  const d = String(p.getDate()).padStart(2, "0");
  const m = String(p.getMonth() + 1).padStart(2, "0");
  const H = String(p.getHours()).padStart(2, "0");
  const M = String(p.getMinutes()).padStart(2, "0");
  return M !== "00" ? `${d}/${m} ${H}h${M}` : `${d}/${m} ${H}h`;
}



// calculateSkillDifference was deprecated and removed
// Use calculateWave instead for the new wave system with skill ponderation

// ============================================================================
// NOUVEAU SYSTÈME DE VAGUES AVEC PONDÉRATION
// ============================================================================

interface UserForWaveCalculation {
  id: string;
  team?: string;
  skills?: string[];
}

/**
 * Calcule les poids de rareté pour chaque compétence
 *
 * Plus une compétence est rare dans l'équipe, plus son poids est élevé
 * Cela permet de prioriser les remplaçants qui ont les compétences rares
 *
 * @param {UserForWaveCalculation[]} teamMembers - Tous les membres de l'équipe
 * @param {string[]} requesterSkills - Compétences du demandeur
 * @return {Record<string, number>} Poids pour chaque compétence
 */
function calculateSkillRarityWeights(
  teamMembers: UserForWaveCalculation[],
  requesterSkills: string[],
): Record<string, number> {
  const skillCounts: Record<string, number> = {};

  // Compter combien d'agents ont chaque compétence
  for (const member of teamMembers) {
    for (const skill of member.skills || []) {
      skillCounts[skill] = (skillCounts[skill] || 0) + 1;
    }
  }

  // Compétences de niveau apprentice (poids = 0)
  const apprenticeSkills = [
    "Apprenant SUAP",
    "Apprenant PPBE",
    "Apprenant INC",
  ];

  // Calculer le poids de rareté pour chaque compétence du demandeur
  const weights: Record<string, number> = {};
  for (const skill of requesterSkills) {
    // Les compétences de niveau apprentice ont un poids de 0
    if (apprenticeSkills.includes(skill)) {
      weights[skill] = 0;
      continue;
    }

    const count = skillCounts[skill] || 0;

    // Plus la compétence est rare, plus le poids est élevé
    // Si personne d'autre n'a la compétence : poids = 10
    // Si 1 personne l'a : poids = 5
    // Si 2+ personnes l'ont : poids = 1
    if (count <= 1) {
      weights[skill] = 10; // Très rare
    } else if (count === 2) {
      weights[skill] = 5; // Rare
    } else if (count === 3) {
      weights[skill] = 3; // Peu commun
    } else {
      weights[skill] = 1; // Commun
    }
  }

  return weights;
}

/**
 * Vérifie si deux utilisateurs ont exactement les mêmes compétences
 * @param {string[]} skills1 - Compétences premier utilisateur
 * @param {string[]} skills2 - Compétences deuxième utilisateur
 * @return {boolean} True si les compétences sont identiques
 */
function hasExactSameSkills(
  skills1: string[],
  skills2: string[],
): boolean {
  const set1 = new Set(skills1);
  const set2 = new Set(skills2);

  if (set1.size !== set2.size) return false;

  for (const skill of set1) {
    if (!set2.has(skill)) return false;
  }

  return true;
}

/**
 * Calcule la similarité pondérée entre deux ensembles de compétences
 *
 * Retourne un score entre 0.0 et 1.0
 * - 1.0 = compétences identiques
 * - 0.0 = aucune compétence en commun
 *
 * @param {string[]} requesterSkills - Compétences du demandeur
 * @param {string[]} candidateSkills - Compétences du candidat
 * @param {Record<string, number>} skillRarityWeights - Poids de rareté
 * @return {number} Score de similarité
 */
function calculateSkillSimilarity(
  requesterSkills: string[],
  candidateSkills: string[],
  skillRarityWeights: Record<string, number>,
): number {
  if (requesterSkills.length === 0) return 0.0;

  const candidateSkillsSet = new Set(candidateSkills);

  // Calculer le poids total des compétences du demandeur
  let totalRequiredWeight = 0.0;
  for (const skill of requesterSkills) {
    totalRequiredWeight += skillRarityWeights[skill] || 1;
  }

  // Calculer le poids des compétences en commun
  let matchedWeight = 0.0;
  for (const skill of requesterSkills) {
    if (candidateSkillsSet.has(skill)) {
      matchedWeight += skillRarityWeights[skill] || 1;
    }
  }

  // Pénaliser si le candidat a beaucoup de compétences supplémentaires
  const requesterSkillsSet = new Set(requesterSkills);
  const extraSkills = candidateSkills.filter(
    (skill) => !requesterSkillsSet.has(skill),
  ).length;
  const penalty = extraSkills > 2 ? 0.1 * extraSkills : 0.0;

  const similarity = matchedWeight / totalRequiredWeight;
  return Math.max(0.0, Math.min(1.0, similarity - penalty));
}

/**
 * Calcule la vague basée sur les compétences
 *
 * @param {string[]} requesterSkills - Compétences du demandeur
 * @param {string[]} candidateSkills - Compétences du candidat
 * @param {Record<string, number>} skillRarityWeights - Poids de rareté
 * @return {number} Numéro de vague (2-5)
 */
function calculateWaveBySkills(
  requesterSkills: string[],
  candidateSkills: string[],
  skillRarityWeights: Record<string, number>,
): number {
  // Vérifier si les compétences sont exactement les mêmes
  if (hasExactSameSkills(requesterSkills, candidateSkills)) {
    return 2; // Vague 2 : Compétences identiques
  }

  // Calculer le score de similarité pondéré
  const similarity = calculateSkillSimilarity(
    requesterSkills,
    candidateSkills,
    skillRarityWeights,
  );

  // Définir les seuils pour chaque vague
  // similarity = 1.0 signifie identique
  // similarity = 0.0 signifie complètement différent
  if (similarity >= 0.8) {
    return 3; // Vague 3 : Très similaire (80%+ de match)
  } else if (similarity >= 0.6) {
    return 4; // Vague 4 : Relativement similaire (60%+ de match)
  } else {
    return 5; // Vague 5 : Tous les autres
  }
}

/**
 * Calcule la vague d'un utilisateur pour une demande de remplacement
 *
 * Logique des vagues :
 * - Agents en astreinte (jamais notifiés)
 * - Vague 1 : Agents de la même équipe (hors astreinte)
 * - Vague 2 : Agents avec exactement les mêmes compétences
 * - Vague 3 : Agents avec compétences très proches (80%+)
 * - Vague 4 : Agents avec compétences relativement proches (60%+)
 * - Vague 5 : Tous les autres agents
 *
 * @param {object} params - Paramètres
 * @param {UserForWaveCalculation} params.requester - Demandeur
 * @param {UserForWaveCalculation} params.candidate - Candidat
 * @param {string} params.planningTeam - Équipe du planning
 * @param {string[]} params.agentsInPlanning - IDs agents en astreinte
 * @param {Record<string, number>} params.skillRarityWeights - Poids rareté
 * @return {number} Numéro de vague (0-5)
 */
function calculateWave(params: {
  requester: UserForWaveCalculation;
  candidate: UserForWaveCalculation;
  planningTeam: string;
  agentsInPlanning: string[];
  skillRarityWeights: Record<string, number>;
}): number {
  const {
    requester,
    candidate,
    planningTeam,
    agentsInPlanning,
    skillRarityWeights,
  } = params;

  // Vague 0 : Agents en astreinte (jamais notifiés)
  if (agentsInPlanning.includes(candidate.id)) {
    return 0;
  }

  // Vague 1 : Même équipe que l'astreinte (hors astreinte)
  if (candidate.team === planningTeam &&
    !agentsInPlanning.includes(candidate.id)) {
    return 1;
  }

  // Vague 2-5 : Basé sur les compétences
  return calculateWaveBySkills(
    requester.skills || [],
    candidate.skills || [],
    skillRarityWeights,
  );
}



// ============================================================================
// V2 : FONCTIONS AVEC PATHS SDIS/STATION
// Ces fonctions coexistent avec les fonctions flat-path ci-dessus.
// Elles seront les seules actives une fois tous les utilisateurs migrés.
// ============================================================================

/**
 * Helper : récupérer toutes les paires (sdisId, stationId, stationPath)
 */
async function getAllStationPaths(): Promise<
  Array<{sdisId: string; stationId: string; stationPath: string}>
> {
  const db = getFirestore();
  const result: Array<{sdisId: string; stationId: string; stationPath: string}> = [];

  // collectionGroup("stations") trouve toutes les sous-collections "stations"
  // même si le document parent sdis/<id> n'existe pas en tant que document Firestore
  const stationsSnapshot = await db.collectionGroup("stations").get();
  for (const stationDoc of stationsSnapshot.docs) {
    const ref = stationDoc.ref;
    // chemin attendu : sdis/{sdisId}/stations/{stationId}
    // ref.parent = collection "stations", ref.parent.parent = doc "sdis/{sdisId}"
    const sdisDocRef = ref.parent.parent;
    if (sdisDocRef && sdisDocRef.parent.id === "sdis") {
      result.push({
        sdisId: sdisDocRef.id,
        stationId: stationDoc.id,
        stationPath: `sdis/${sdisDocRef.id}/stations/${stationDoc.id}`,
      });
    }
  }

  return result;
}

/**
 * V2 : Écoute les notificationTriggers dans les paths SDIS/station
 */
export const sendReplacementNotificationsV2 = onDocumentCreated(
  {
    region: "europe-west1",
    document: "sdis/{sdisId}/stations/{stationId}/notificationTriggers/{triggerId}",
    secrets: [encryptionKey],
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }

    const trigger = snapshot.data();
    const stationPath = `sdis/${event.params.sdisId}/stations/${event.params.stationId}`;
      const sdisId = event.params.sdisId;

    if (trigger.processed) {
      console.log("Trigger already processed:", event.params.triggerId);
      return;
    }

    try {
      const type = trigger.type;
      // Supporte à la fois targetUserIds (tableau) et userId (singulier)
      const targetUserIds: string[] = trigger.targetUserIds ||
        (trigger.userId ? [trigger.userId] : []);

      console.log(
        `📤 [V2] Processing ${type} notification for ` +
        `${targetUserIds.length} users (${stationPath})`,
      );

      // Clé de déchiffrement PII
      const key = encryptionKey.value();
      const db = getFirestore();

      // Helper : charge un doc user et retourne son nom déchiffré
      const resolveUserName = async (userId: string): Promise<string> => {
        const userDoc = await db.collection(`${stationPath}/users`).doc(userId).get();
        if (!userDoc.exists) return "";
        const {firstName, lastName} = decryptPII(userDoc.data() || {}, key);
        return `${firstName || ""} ${lastName || ""}`.trim();
      };

      // Helper : charge un doc équipe et retourne son nom complet
      const resolveTeamName = async (teamId: string): Promise<string> => {
        if (!teamId) return "";
        const teamDoc = await db.collection(`${stationPath}/teams`).doc(teamId).get();
        if (!teamDoc.exists) return teamId;
        return (teamDoc.data()?.name as string) || teamId;
      };

      // Récupérer les tokens FCM des utilisateurs cibles
      // Helper : résoudre le token FCM depuis le niveau SDIS (sdis/{sdisId}/users)
      // Les tokens sont stockés par authUid, indexés par le champ 'matricule'
      const getFcmTokenFromSdis = async (matricule: string): Promise<{token: string | null; authUid: string | null}> => {
        const snap = await db.collection(`sdis/${sdisId}/users`)
          .where("matricule", "==", matricule)
          .limit(1)
          .get();
        if (snap.empty) return {token: null, authUid: null};
        const data = snap.docs[0].data();
        return {token: data?.fcmToken ?? null, authUid: snap.docs[0].id};
      };

      const tokens: string[] = [];
      const tokenAuthUids: string[] = []; // Pour nettoyage des tokens invalides
      for (const userId of targetUserIds) {
        // Lire les données depuis la collection station pour le filtrage des préférences
        const stationUserDoc = await db
          .collection(`${stationPath}/users`)
          .doc(userId)
          .get();

        // Pour les demandes d'adhésion, ne notifier que les admins ayant activé la préférence
        if (type === "membership_requested") {
          if (stationUserDoc.data()?.membershipAlertEnabled !== true) {
            console.log(`  ⏭️ Skipping user ${userId} (membershipAlertEnabled not set)`);
            continue;
          }
        }

        // Token FCM lu depuis le niveau SDIS
        const {token: fcmToken, authUid} = await getFcmTokenFromSdis(userId);
        if (fcmToken) {
          tokens.push(fcmToken);
          tokenAuthUids.push(authUid!);
          console.log(`  ✓ Token found for user ${userId}`);
        } else {
          console.log(`  ⚠️ No token for user ${userId}`);
        }
      }

      if (tokens.length === 0) {
        console.log("❌ No FCM tokens found for target users");
        await snapshot.ref.update({
          processed: true,
          processedAt: Timestamp.now(),
          error: "No FCM tokens found",
        });
        return;
      }

      // Construire le message selon le type (même switch que V1)
      let notification: { title: string; body: string };
      let data: { [key: string]: string };

      switch (type) {
      case "replacement_request": {
        const requesterName = await resolveUserName(trigger.requesterId);
        const isSOS = trigger.isSOS === true;
        const teamName1 = await resolveTeamName(trigger.team || "");
        const replacementBody =
          `${requesterName} propose un remplacement du ` +
          `${formatShort(trigger.startTime.toDate())} au ` +
          `${formatShort(trigger.endTime.toDate())}` +
          (teamName1 ? `, ${teamName1}` : "");
        notification = {
          title: isSOS ? "🚨 URGENT : Recherche de remplaçant" : "🔔 Recherche de remplaçant",
          body: isSOS ? `URGENT : ${replacementBody}` : replacementBody,
        };
        data = {
          type: "replacement_request",
          requestId: trigger.requestId,
          requesterId: trigger.requesterId,
          planningId: trigger.planningId,
          station: trigger.station || "",
          team: trigger.team || "",
        };
        break;
      }

      case "availability_request": {
        const requesterName = await resolveUserName(trigger.requesterId);
        notification = {
          title: "🔍 Recherche d'agent disponible",
          body:
              `${requesterName} recherche un ` +
              "agent disponible du " +
              `${formatDate(trigger.startTime.toDate())} au ` +
              `${formatDate(trigger.endTime.toDate())}`,
        };
        data = {
          type: "availability_request",
          requestId: trigger.requestId,
          requesterId: trigger.requesterId,
          planningId: trigger.planningId,
          station: trigger.station || "",
          team: trigger.team || "",
        };
        break;
      }

      case "replacement_found": {
        const replacerName = await resolveUserName(trigger.replacerId);
        const foundBody = (trigger.startTime && trigger.endTime)
          ? `${replacerName} a accepté votre demande de remplacement du ` +
            `${formatShort(trigger.startTime.toDate())} au ` +
            `${formatShort(trigger.endTime.toDate())}`
          : `${replacerName} a accepté votre demande de remplacement`;
        notification = {
          title: "✅ Remplaçant trouvé !",
          body: foundBody,
        };
        data = {
          type: "replacement_found",
          requestId: trigger.requestId,
          replacerId: trigger.replacerId,
        };
        break;
      }

      case "replacement_assigned": {
        const [replacedNameA, replacerNameA] = await Promise.all([
          resolveUserName(trigger.replacedId),
          resolveUserName(trigger.replacerId),
        ]);
        notification = {
          title: "📋 Remplacement assigné",
          body:
              `${replacerNameA} remplacera ${replacedNameA} du ` +
              `${formatShort(trigger.startTime.toDate())} au ` +
              `${formatShort(trigger.endTime.toDate())}`,
        };
        data = {
          type: "replacement_assigned",
          requestId: trigger.requestId,
          replacedId: trigger.replacedId,
          replacerId: trigger.replacerId,
        };
        break;
      }

      case "replacement_completed": {
        // trigger.replacerIds est un tableau d'IDs, résoudre chaque nom
        const replacerIdsList: string[] = trigger.replacerIds || [];
        const replacerNamesList = await Promise.all(
          replacerIdsList.map((id: string) => resolveUserName(id))
        );
        const replacerNamesStr = replacerNamesList.filter(Boolean).join(", ");
        notification = {
          title: "✅ Remplacement complété !",
          body: `Votre remplacement a été trouvé : ${replacerNamesStr}`,
        };
        data = {
          type: "replacement_completed",
          requestId: trigger.requestId,
        };
        break;
      }

      case "replacement_completed_chief": {
        const requesterName = await resolveUserName(trigger.requesterId);
        const replacerIdsList: string[] = trigger.replacerIds || [];
        const replacerNamesList = await Promise.all(
          replacerIdsList.map((id: string) => resolveUserName(id))
        );
        const replacerNamesStr = replacerNamesList.filter(Boolean).join(", ");
        notification = {
          title: "✅ Remplacement complété",
          body: `${requesterName} a trouvé son remplacement : ${replacerNamesStr}`,
        };
        data = {
          type: "replacement_completed_chief",
          requestId: trigger.requestId,
        };
        break;
      }

      case "manual_replacement_proposal": {
        const proposerNameM = await resolveUserName(trigger.proposerId);
        const teamNameM = await resolveTeamName(trigger.team || "");
        notification = {
          title: "🔄 Proposition de remplacement",
          body:
              `${proposerNameM} vous propose un remplacement du ` +
              `${formatShort(trigger.startTime.toDate())} au ` +
              `${formatShort(trigger.endTime.toDate())}` +
              (teamNameM ? `, ${teamNameM}` : ""),
        };
        data = {
          type: "manual_replacement_proposal",
          proposalId: trigger.proposalId,
          proposerId: trigger.proposerId,
          replacedId: trigger.replacedId,
          planningId: trigger.planningId,
        };
        break;
      }

      case "shift_exchange_proposal_received": {
        const proposerIdEx = trigger.data?.proposerId || "";
        const proposerNameEx = proposerIdEx ? await resolveUserName(proposerIdEx) : "";
        const proposerTeamIdEx = trigger.data?.proposerTeam || "";
        const proposerTeamEx = proposerTeamIdEx ? await resolveTeamName(proposerTeamIdEx) : "";
        notification = {
          title: "💬 Proposition d'échange reçue",
          body: proposerNameEx
            ? `${proposerNameEx} a répondu à votre proposition d'échange` +
              (proposerTeamEx ? `, ${proposerTeamEx}` : "")
            : "Un agent a répondu à votre proposition d'échange",
        };
        data = {
          type: "shift_exchange_proposal_received",
          requestId: trigger.data?.requestId || "",
          proposalId: trigger.data?.proposalId || "",
          proposerId: proposerIdEx,
        };
        break;
      }

      case "shift_exchange_validation_required": {
        const initiatorIdV = trigger.data?.initiatorId || "";
        const proposerIdV = trigger.data?.proposerId || "";
        const [initiatorNameV, proposerNameV] = await Promise.all([
          initiatorIdV ? resolveUserName(initiatorIdV) : Promise.resolve(""),
          proposerIdV ? resolveUserName(proposerIdV) : Promise.resolve(""),
        ]);
        notification = {
          title: "✋ Validation d'échange requise",
          body: (initiatorNameV && proposerNameV)
            ? `Validation attendue de votre part pour l'échange d'astreinte de ${initiatorNameV} et ${proposerNameV}`
            : "Un échange d'astreinte nécessite votre validation",
        };
        data = {
          type: "shift_exchange_validation_required",
          requestId: trigger.data?.requestId || "",
          proposalId: trigger.data?.proposalId || "",
          initiatorId: initiatorIdV,
          proposerId: proposerIdV,
        };
        break;
      }

      case "shift_exchange_validated": {
        const initiatorIdC = trigger.data?.initiatorId || "";
        const proposerIdC = trigger.data?.proposerId || "";
        const [initiatorNameC, proposerNameC] = await Promise.all([
          initiatorIdC ? resolveUserName(initiatorIdC) : Promise.resolve(""),
          proposerIdC ? resolveUserName(proposerIdC) : Promise.resolve(""),
        ]);
        notification = {
          title: "✅ Échange conclu",
          body: (initiatorNameC && proposerNameC)
            ? `Échange d'astreinte conclu entre ${initiatorNameC} et ${proposerNameC}`
            : "Votre échange d'astreinte a été validé",
        };
        data = {
          type: "shift_exchange_validated",
          requestId: trigger.data?.requestId || "",
          proposalId: trigger.data?.proposalId || "",
        };
        break;
      }

      case "shift_exchange_rejected":
        notification = {
          title: trigger.title || "❌ Proposition refusée",
          body: trigger.body || "Une proposition d'échange a été refusée",
        };
        data = {
          type: "shift_exchange_rejected",
          requestId: trigger.data?.requestId || "",
          proposalId: trigger.data?.proposalId || "",
          rejectionReason: trigger.data?.rejectionReason || "",
        };
        break;

      case "shift_exchange_proposer_selected": {
        const initiatorId = trigger.data?.initiatorId || "";
        const initiatorName = initiatorId ? await resolveUserName(initiatorId) : "";
        notification = {
          title: trigger.title || "🎯 Votre proposition sélectionnée",
          body: initiatorName ?
            `${initiatorName} a sélectionné votre proposition` :
            "Votre proposition d'échange a été sélectionnée",
        };
        data = {
          type: "shift_exchange_proposer_selected",
          requestId: trigger.data?.requestId || "",
          proposalId: trigger.data?.proposalId || "",
          initiatorId,
        };
        break;
      }

      case "daily_shift_reminder": {
        const plannings = (trigger.data?.plannings as Array<{
          planningId: string;
          startDate: string;
          endDate: string;
          team: string;
        }>) || [];

        const resolvedPlanningTeamNames = await Promise.all(
          plannings.map((p) => resolveTeamName(p.team))
        );

        const lines = plannings.map((p, idx) => {
          const start = new Date(p.startDate);
          const end = new Date(p.endDate);
          const parisStart = new Date(
            start.toLocaleString("en-US", {timeZone: "Europe/Paris"}),
          );
          const parisEnd = new Date(
            end.toLocaleString("en-US", {timeZone: "Europe/Paris"}),
          );
          const day = String(parisStart.getDate()).padStart(2, "0");
          const month = String(parisStart.getMonth() + 1).padStart(2, "0");
          const startHH = String(parisStart.getHours()).padStart(2, "0");
          const startMM = String(parisStart.getMinutes()).padStart(2, "0");
          const endHH = String(parisEnd.getHours()).padStart(2, "0");
          const endMM = String(parisEnd.getMinutes()).padStart(2, "0");
          const startStr = startMM !== "00" ? `${startHH}h${startMM}` : `${startHH}h`;
          const endStr = endMM !== "00" ? `${endHH}h${endMM}` : `${endHH}h`;
          return `- ${day}/${month} de ${startStr} à ${endStr}, ${resolvedPlanningTeamNames[idx]}`;
        });

        notification = {
          title: trigger.title || "⏰ Astreintes à venir",
          body: lines.length > 0
            ? `Astreintes à venir :\n${lines.join("\n")}`
            : "Vous avez des astreintes dans les prochaines 24h",
        };
        data = {
          type: "daily_shift_reminder",
        };
        break;
      }

      case "agent_query_request": {
        const queryTeam = trigger.team ? await resolveTeamName(trigger.team) : "";
        notification = {
          title: "🔎 Recherche d'agent",
          body: `Recherche d'un agent avec vos compétences` +
              (queryTeam ? ` pour ${queryTeam}` : "") +
              ` du ${formatShort(trigger.startTime.toDate())}` +
              ` au ${formatShort(trigger.endTime.toDate())}`,
        };
        data = {
          type: "agent_query_request",
          queryId: trigger.queryId || "",
          createdById: trigger.createdById || "",
          planningId: trigger.planningId || "",
          onCallLevelId: trigger.onCallLevelId || "",
        };
        break;
      }

      case "replacement_validation_required": {
        const acceptorIdV = trigger.data?.acceptorId || "";
        const requesterIdV = trigger.data?.requesterId || "";
        const [acceptorNameV, requesterNameV] = await Promise.all([
          acceptorIdV ? resolveUserName(acceptorIdV) : Promise.resolve(""),
          requesterIdV ? resolveUserName(requesterIdV) : Promise.resolve(""),
        ]);
        const hasDatesDV = trigger.data?.startTime && trigger.data?.endTime;
        const datesSuffixV = hasDatesDV
          ? ` du ${formatShort(trigger.data.startTime.toDate())} au ${formatShort(trigger.data.endTime.toDate())}`
          : "";
        notification = {
          title: "✋ Validation de remplacement requise",
          body: (acceptorNameV && requesterNameV)
            ? `Validation attendue de votre part pour le remplacement de ${requesterNameV} par ${acceptorNameV}${datesSuffixV}`
            : "Un agent souhaite effectuer un remplacement",
        };
        data = {
          type: "replacement_validation_required",
          acceptanceId: trigger.data?.acceptanceId || "",
          requestId: trigger.data?.requestId || "",
          acceptorId: acceptorIdV,
          requesterId: requesterIdV,
        };
        break;
      }

      case "acceptance_validated": {
        const acceptorIdAV = trigger.data?.requesterId || "";
        const acceptorNameAV = acceptorIdAV ? await resolveUserName(acceptorIdAV) : "";
        const hasDateAV = trigger.data?.startTime && trigger.data?.endTime;
        const dateSuffixAV = hasDateAV
          ? ` du ${formatShort(trigger.data.startTime.toDate())} au ${formatShort(trigger.data.endTime.toDate())}`
          : "";
        notification = {
          title: "✅ Remplacement validé",
          body: acceptorNameAV
            ? `${acceptorNameAV} a accepté votre demande de remplacement${dateSuffixAV}`
            : "Votre proposition de remplacement a été acceptée.",
        };
        data = {
          type: "acceptance_validated",
          requestId: trigger.data?.requestId || "",
          acceptanceId: trigger.data?.acceptanceId || "",
          requesterId: acceptorIdAV,
        };
        break;
      }

      case "replacement_reminder": {
        const requesterName = await resolveUserName(trigger.requesterId);
        notification = {
          title: "🔔 Rappel : remplacement en attente",
          body: `${requesterName} recherche toujours un remplaçant du ` +
              `${formatDate(trigger.startTime.toDate())} au ` +
              `${formatDate(trigger.endTime.toDate())}`,
        };
        data = {
          type: "replacement_reminder",
          requestId: trigger.requestId,
          requesterId: trigger.requesterId,
        };
        break;
      }

      case "replacement_acceptance_rejected": {
        // Notification de rejet d'acceptation
        notification = {
          title: trigger.title || "Remplacement refusé",
          body: trigger.reason || "Votre acceptation a été refusée.",
        };
        data = {
          type: "replacement_acceptance_rejected",
          requestId: trigger.data?.requestId || "",
          requesterId: trigger.data?.requesterId || "",
        };
        break;
      }

      case "membership_requested": {
        const agentNameM = await resolveUserName(trigger.agentMatricule || "");
        notification = {
          title: "🏠 Demande d'adhésion",
          body: agentNameM
            ? `${agentNameM} souhaite rejoindre votre caserne`
            : "Un agent souhaite rejoindre votre caserne",
        };
        data = {
          type: "membership_requested",
          agentMatricule: trigger.agentMatricule || "",
        };
        break;
      }

      case "membership_accepted": {
        notification = {
          title: "✅ Adhésion acceptée",
          body: trigger.stationName
            ? `Votre demande d'adhésion à la caserne ${trigger.stationName} a été acceptée`
            : "Votre demande d'adhésion a été acceptée",
        };
        data = {
          type: "membership_accepted",
          stationName: trigger.stationName || "",
        };
        break;
      }

      case "membership_rejected": {
        notification = {
          title: "❌ Adhésion refusée",
          body: trigger.stationName
            ? `Votre demande d'adhésion à la caserne ${trigger.stationName} a été refusée`
            : "Votre demande d'adhésion a été refusée",
        };
        data = {
          type: "membership_rejected",
          stationName: trigger.stationName || "",
        };
        break;
      }

      default:
        console.error("❌ Unknown notification type:", type);
        await snapshot.ref.update({
          processed: true,
          processedAt: Timestamp.now(),
          error: `Unknown notification type: ${type}`,
        });
        return;
      }

      // Envoyer les notifications
      const messaging = getMessaging();
      const message = {
        notification,
        data,
        tokens,
        android: {
          priority: "high" as const,
          notification: {
            channelId: "nexshift_replacement_channel",
            priority: "high" as const,
            sound: "default",
          },
          ttl: 86400,
          collapseKey: `replacement_${type}`,
        },
        apns: {
          headers: {
            "apns-priority": "10",
            "apns-expiration": String(Math.floor(Date.now() / 1000) + 86400),
          },
          payload: {
            aps: {
              "alert": {
                title: notification.title,
                body: notification.body,
              },
              "sound": "default",
              "mutable-content": 1,
              "content-available": 1,
            },
          },
        },
      };

      console.log(
        `  🚀 Sending to ${tokens.length} device(s)...`,
      );
      const response = await messaging.sendEachForMulticast(message);

      console.log(
        `✅ Successfully sent ${response.successCount} ` +
        "notification(s)",
      );
      if (response.failureCount > 0) {
        console.error(
          `❌ Failed to send ${response.failureCount} ` +
          "notification(s)",
        );

        const batch = db.batch();
        let invalidTokensCount = 0;

        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            console.error(
              `  Error for token ${idx}:`,
              resp.error,
            );

            const errorCode = resp.error?.code;
            if (
              errorCode === "messaging/invalid-registration-token" ||
              errorCode === "messaging/registration-token-not-registered"
            ) {
              const authUid = tokenAuthUids[idx];
              console.log(
                `  🧹 Cleaning invalid token for authUid ${authUid}`,
              );
              if (authUid) {
                batch.update(
                  db.collection(`sdis/${sdisId}/users`).doc(authUid),
                  {fcmToken: null},
                );
                invalidTokensCount++;
              }
            }
          }
        });

        if (invalidTokensCount > 0) {
          await batch.commit();
          console.log(
            `  🧹 Cleaned ${invalidTokensCount} invalid token(s)`,
          );
        }
      }

      await snapshot.ref.update({
        processed: true,
        processedAt: Timestamp.now(),
        successCount: response.successCount,
        failureCount: response.failureCount,
      });
    } catch (error) {
      console.error("💥 [V2] Error sending notifications:", error);

      await snapshot.ref.update({
        processed: true,
        processedAt: Timestamp.now(),
        error: String(error),
      });

      throw error;
    }
  },
);

/**
 * V2 : Nettoyage des triggers traités (parcourt tous les SDIS/stations)
 */
export const cleanupProcessedTriggersV2 = onSchedule(
  {
    region: "europe-west1",
    schedule: "every 24 hours",
    timeZone: "Europe/Paris",
  },
  async () => {
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

    const db = getFirestore();
    const stationPaths = await getAllStationPaths();
    let totalDeleted = 0;

    for (const {stationPath} of stationPaths) {
      const snapshot = await db
        .collection(`${stationPath}/notificationTriggers`)
        .where("processed", "==", true)
        .where("processedAt", "<", Timestamp.fromDate(sevenDaysAgo))
        .limit(500)
        .get();

      if (snapshot.empty) continue;

      const batch = db.batch();
      snapshot.docs.forEach((doc) => {
        batch.delete(doc.ref);
      });
      await batch.commit();
      totalDeleted += snapshot.size;
    }

    console.log(
      `🧹 [V2] Cleaned up ${totalDeleted} old notification triggers`,
    );
  },
);

/**
 * V2 : Expiration des demandes en attente (parcourt tous les SDIS/stations)
 */
export const expireOldRequestsV2 = onSchedule(
  {
    region: "europe-west1",
    schedule: "every 1 hours",
    timeZone: "Europe/Paris",
  },
  async () => {
    const oneDayAgo = new Date();
    oneDayAgo.setHours(oneDayAgo.getHours() - 24);

    const db = getFirestore();
    const stationPaths = await getAllStationPaths();
    let totalExpired = 0;

    for (const {stationPath} of stationPaths) {
      const snapshot = await db
        .collection(`${stationPath}/replacements/automatic/replacementRequests`)
        .where("status", "==", "pending")
        .where("createdAt", "<", Timestamp.fromDate(oneDayAgo))
        .get();

      if (snapshot.empty) continue;

      const batch = db.batch();
      snapshot.docs.forEach((doc) => {
        batch.update(doc.ref, {
          status: "expired",
          expiredAt: Timestamp.now(),
        });
      });
      await batch.commit();
      totalExpired += snapshot.size;
    }

    console.log(
      `⏰ [V2] Expired ${totalExpired} old replacement requests`,
    );
  },
);

/**
 * V2 : Écoute les subshifts dans les paths SDIS/station
 */
export const checkReplacementCompletionV2 = onDocumentCreated(
  {region: "europe-west1", document: "sdis/{sdisId}/stations/{stationId}/replacements/all/subshifts/{subshiftId}"},
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }

    const subshift = snapshot.data();
    const planningId = subshift.planningId;
    const replacedId = subshift.replacedId;
    const stationPath = `sdis/${event.params.sdisId}/stations/${event.params.stationId}`;

    console.log(
      "🔍 [V2] Checking if replacement is complete for " +
      `user ${replacedId} in planning ${planningId} (${stationPath})`,
    );

    try {
      const db = getFirestore();

      const requestsSnapshot = await db
        .collection(`${stationPath}/replacements/automatic/replacementRequests`)
        .where("requesterId", "==", replacedId)
        .where("planningId", "==", planningId)
        .where("status", "==", "pending")
        .get();

      console.log(
        `  Found ${requestsSnapshot.size} pending requests for this user`,
      );

      for (const requestDoc of requestsSnapshot.docs) {
        const request = requestDoc.data();
        const requestStart = request.startTime.toDate();
        const requestEnd = request.endTime.toDate();

        const subshiftsSnapshot = await db
          .collection(`${stationPath}/replacements/all/subshifts`)
          .where("planningId", "==", planningId)
          .where("replacedId", "==", replacedId)
          .get();

        const intervals: Array<{ start: Date; end: Date }> = [];
        subshiftsSnapshot.docs.forEach((doc) => {
          const data = doc.data();
          intervals.push({
            start: data.start.toDate(),
            end: data.end.toDate(),
          });
        });

        const isFullyCovered = checkIfFullyCovered(
          requestStart,
          requestEnd,
          intervals,
        );

        if (isFullyCovered) {
          console.log(
            `  ✅ Request ${requestDoc.id} is fully covered!`,
          );

          await requestDoc.ref.update({
            status: "accepted",
            acceptedAt: Timestamp.now(),
          });

          const requesterDoc = await db
            .collection(`${stationPath}/users`)
            .doc(replacedId)
            .get();

          if (!requesterDoc.exists) continue;

          const planningForChiefDoc = await db
            .collection(`${stationPath}/plannings`)
            .doc(planningId)
            .get();

          let chiefId = replacedId;
          if (planningForChiefDoc.exists) {
            const planningData = planningForChiefDoc.data();
            const planningTeam = planningData?.team;

            if (planningTeam) {
              const chiefsSnapshot = await db
                .collection(`${stationPath}/users`)
                .where("team", "==", planningTeam)
                .get();

              const chief = chiefsSnapshot.docs.find((doc) => {
                const userData = doc.data();
                const isChief = userData.status === "chief" ||
                  userData.status === "leader";
                const notRequester = doc.id !== replacedId;
                return isChief && notRequester;
              });

              if (chief) {
                chiefId = chief.id;
              }
            }
          }

          // Collecter les IDs des remplaçants (la CF handler résoudra les noms)
          const replacerIdsSet = new Set<string>(
            intervals.map((interval) => {
              const matchingSubshift = subshiftsSnapshot.docs.find((doc) => {
                const data = doc.data();
                const start = data.start.toDate();
                const end = data.end.toDate();
                return start.getTime() === interval.start.getTime() &&
                  end.getTime() === interval.end.getTime();
              });
              return matchingSubshift?.data().replacerId;
            }).filter(Boolean) as string[],
          );

          const replacerIdsList = Array.from(replacerIdsSet);

          await db.collection(`${stationPath}/notificationTriggers`).add({
            type: "replacement_completed",
            requestId: requestDoc.id,
            targetUserIds: [replacedId],
            replacerIds: replacerIdsList,
            startTime: request.startTime,
            endTime: request.endTime,
            createdAt: Timestamp.now(),
            processed: false,
          });

          if (chiefId !== replacedId) {
            await db.collection(`${stationPath}/notificationTriggers`).add({
              type: "replacement_completed_chief",
              requestId: requestDoc.id,
              targetUserIds: [chiefId],
              requesterId: replacedId,
              replacerIds: replacerIdsList,
              startTime: request.startTime,
              endTime: request.endTime,
              createdAt: Timestamp.now(),
              processed: false,
            });
          }

          console.log(
            "  📨 Completion notifications created for " +
            "requester and chief",
          );
        }
      }
    } catch (error) {
      console.error("💥 [V2] Error checking replacement completion:", error);
    }
  },
);

/**
 * V2 : Notification de test
 */
export const sendTestNotificationV2 = onDocumentCreated(
  {region: "europe-west1", document: "sdis/{sdisId}/stations/{stationId}/testNotifications/{testId}"},
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }

    const test = snapshot.data();
    const stationPath = `sdis/${event.params.sdisId}/stations/${event.params.stationId}`;

    try {
      const targetUserId = test.targetUserId as string;
      const adminId = test.adminId as string;

      console.log(
        `🧪 [V2] Sending test notification to user ${targetUserId} ` +
        `(requested by ${adminId})`,
      );

      const db = getFirestore();
      const userDoc = await db
        .collection(`${stationPath}/users`)
        .doc(targetUserId)
        .get();

      if (!userDoc.exists) {
        console.error(`❌ User ${targetUserId} not found`);
        await snapshot.ref.update({
          processed: true,
          processedAt: Timestamp.now(),
          error: "User not found",
        });
        return;
      }

      const fcmToken = userDoc.data()?.fcmToken;
      if (!fcmToken) {
        console.error(`❌ No FCM token for user ${targetUserId}`);
        await snapshot.ref.update({
          processed: true,
          processedAt: Timestamp.now(),
          error: "No FCM token found",
        });
        return;
      }

      const adminDoc = await db
        .collection(`${stationPath}/users`)
        .doc(adminId)
        .get();
      let adminName = "Admin";
      if (adminDoc.exists) {
        const key = encryptionKey.value();
        const {firstName, lastName} = decryptPII(adminDoc.data() || {}, key);
        adminName = `${firstName || ""} ${lastName || ""}`.trim() || "Admin";
      }

      const notification = {
        title: "🧪 Notification de test",
        body:
          `Test envoyé par ${adminName}. ` +
          "Si vous voyez ce message, les notifications fonctionnent !",
      };

      const data = {
        type: "test_notification",
        adminId: adminId,
        timestamp: new Date().toISOString(),
      };

      const messaging = getMessaging();
      const message = {
        notification,
        data,
        token: fcmToken,
        android: {
          priority: "high" as const,
          notification: {
            channelId: "nexshift_replacement_channel",
            priority: "high" as const,
            sound: "default",
          },
          ttl: 86400,
        },
        apns: {
          headers: {
            "apns-priority": "10",
            "apns-expiration": String(Math.floor(Date.now() / 1000) + 86400),
          },
          payload: {
            aps: {
              "alert": {
                title: notification.title,
                body: notification.body,
              },
              "sound": "default",
              "mutable-content": 1,
              "content-available": 1,
            },
          },
        },
      };

      console.log("  🚀 Sending test notification...");
      const response = await messaging.send(message);

      console.log(`✅ Test notification sent successfully: ${response}`);

      await snapshot.ref.update({
        processed: true,
        processedAt: Timestamp.now(),
        success: true,
        messageId: response,
      });
    } catch (error) {
      console.error("💥 [V2] Error sending test notification:", error);

      const errorCode = (error as {code?: string})?.code;
      if (
        errorCode === "messaging/invalid-registration-token" ||
        errorCode === "messaging/registration-token-not-registered"
      ) {
        console.log(`  🧹 Cleaning invalid token for user ${test.targetUserId}`);
        const db = getFirestore();
        await db
          .collection(`${stationPath}/users`)
          .doc(test.targetUserId)
          .update({fcmToken: null});
      }

      await snapshot.ref.update({
        processed: true,
        processedAt: Timestamp.now(),
        error: String(error),
      });

      throw error;
    }
  },
);

/**
 * V2 : Vagues vides
 */
export const processEmptyWaveV2 = onDocumentCreated(
  {region: "europe-west1", document: "sdis/{sdisId}/stations/{stationId}/replacements/automatic/waveSkipTriggers/{triggerId}"},
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }

    const trigger = snapshot.data();
    const stationPath = `sdis/${event.params.sdisId}/stations/${event.params.stationId}`;

    if (trigger.processed) {
      console.log("Trigger already processed:", event.params.triggerId);
      return;
    }

    try {
      const requestId = trigger.requestId as string;
      const skippedWave = trigger.skippedWave as number;

      console.log(
        `🌊 [V2] Processing empty wave skip for request ${requestId} ` +
        `(skipped wave: ${skippedWave})`,
      );

      const db = getFirestore();

      const requestDoc = await db
        .collection(`${stationPath}/replacements/automatic/replacementRequests`)
        .doc(requestId)
        .get();

      if (!requestDoc.exists) {
        console.error(`  ❌ Request not found: ${requestId}`);
        await snapshot.ref.update({
          processed: true,
          processedAt: Timestamp.now(),
          error: "Request not found",
        });
        return;
      }

      const request = requestDoc.data() as ReplacementRequestDataV2;

      await sendNextWaveV2(requestId, request, stationPath);

      await snapshot.ref.update({
        processed: true,
        processedAt: Timestamp.now(),
      });

      console.log(
        `  ✅ Empty wave processed, next wave sent for request ${requestId}`,
      );
    } catch (error) {
      console.error("💥 [V2] Error processing empty wave:", error);

      await snapshot.ref.update({
        processed: true,
        processedAt: Timestamp.now(),
        error: String(error),
      });
    }
  },
);

/**
 * V2 : Vagues de notifications progressives (parcourt tous les SDIS/stations)
 */
export const processNotificationWavesV2 = onSchedule(
  {
    region: "europe-west1",
    schedule: "every 5 minutes",
    timeZone: "Europe/Paris",
  },
  async () => {
    const db = getFirestore();
    console.log("🌊 [V2] Processing notification waves...");

    try {
      const stationPaths = await getAllStationPaths();

      for (const {stationPath} of stationPaths) {
        const pendingRequests = await db
          .collection(`${stationPath}/replacements/automatic/replacementRequests`)
          .where("status", "==", "pending")
          .get();

        if (pendingRequests.empty) continue;

        for (const requestDoc of pendingRequests.docs) {
          const request = requestDoc.data();
          const requestId = requestDoc.id;

          const lastWaveSentAt = request.lastWaveSentAt?.toDate();
          if (!lastWaveSentAt) continue;

          // Récupérer le délai configuré pour la station
          const stationDoc = await db
            .doc(stationPath)
            .get();

          const delayMinutes = stationDoc.exists ?
            (stationDoc.data()?.notificationWaveDelayMinutes || 30) :
            30;

          const now = new Date();
          const minutesSinceLastWave =
            (now.getTime() - lastWaveSentAt.getTime()) / (1000 * 60);

          if (minutesSinceLastWave < delayMinutes) {
            console.log(
              `  Request ${requestId}: ` +
              `waiting (${Math.round(minutesSinceLastWave)}/${delayMinutes} min)`,
            );
            continue;
          }

          console.log(
            `  Request ${requestId}: ` +
            `sending next wave (current: ${request.currentWave})`,
          );

          await sendNextWaveV2(
            requestId,
            request as ReplacementRequestDataV2,
            stationPath,
          );
        }
      }
    } catch (error) {
      console.error("💥 [V2] Error processing notification waves:", error);
    }
  },
);

interface ReplacementRequestDataV2 {
  requesterId: string;
  station: string;
  sdisId?: string;
  planningId: string;
  startTime: Timestamp;
  endTime: Timestamp;
  team: string;
  currentWave?: number;
  notifiedUserIds?: string[];
}

/**
 * V2 : Envoie la vague suivante de notifications (paths SDIS/station)
 */
async function sendNextWaveV2(
  requestId: string,
  request: ReplacementRequestDataV2,
  stationPath: string,
) {
  const db = getFirestore();

  try {
    const requesterDoc = await db
      .collection(`${stationPath}/users`)
      .doc(request.requesterId)
      .get();

    if (!requesterDoc.exists) {
      console.error(`  ❌ Requester ${request.requesterId} not found`);
      return;
    }

    const requester = requesterDoc.data();
    const requesterSkills = requester?.skills || [];

    // Récupérer tous les utilisateurs de la station
    const allUsersSnapshot = await db
      .collection(`${stationPath}/users`)
      .get();

    interface UserData {
      id: string;
      skills?: string[];
      team?: string;
    }

    const allUsers = allUsersSnapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    })) as UserData[];

    const planningDoc = await db
      .collection(`${stationPath}/plannings`)
      .doc(request.planningId)
      .get();

    const agentsInPlanning: string[] = [];
    if (planningDoc.exists) {
      const planningData = planningDoc.data();
      const requestStart = request.startTime.toDate().getTime();
      const requestEnd = request.endTime.toDate().getTime();

      const agents = planningData?.agents as Array<{
        agentId: string;
        start: {toDate: () => Date};
        end: {toDate: () => Date};
      }> | undefined;

      if (agents) {
        for (const a of agents) {
          if (
            a.start.toDate().getTime() < requestEnd &&
            a.end.toDate().getTime() > requestStart
          ) {
            agentsInPlanning.push(a.agentId);
          }
        }
      } else {
        // Fallback ancien format
        agentsInPlanning.push(...(planningData?.agentsId || []));
      }
    }

    console.log(
      `  Planning ${request.planningId} has ${agentsInPlanning.length} ` +
      "agents on duty",
    );

    const notifiedUserIds = request.notifiedUserIds || [];
    const candidateUsers = allUsers.filter(
      (u) =>
        u.id !== request.requesterId &&
        !notifiedUserIds.includes(u.id) &&
        !(agentsInPlanning.includes(u.id) && u.team === request.team),
    );

    console.log(
      `  Found ${candidateUsers.length} candidate users ` +
      `(${notifiedUserIds.length} already notified)`,
    );

    if (candidateUsers.length === 0) {
      console.log("  ✅ All users have been notified");
      return;
    }

    const nextWave = (request.currentWave || 0) + 1;

    if (nextWave > 5) {
      console.log("  ✅ All 5 waves have been processed");
      return;
    }

    const planningData = planningDoc.data();
    const planningTeam = planningData?.team || "";

    const skillRarityWeights = calculateSkillRarityWeights(
      allUsers.map((u) => ({
        id: u.id,
        team: u.team,
        skills: u.skills,
      })),
      requesterSkills,
    );

    const candidatesWithWave = candidateUsers.map((user) => ({
      user,
      wave: calculateWave({
        requester: {
          id: request.requesterId,
          team: requester?.team,
          skills: requesterSkills,
        },
        candidate: {
          id: user.id,
          team: user.team,
          skills: user.skills || [],
        },
        planningTeam,
        agentsInPlanning,
        skillRarityWeights,
      }),
    }));

    const waveUsers = candidatesWithWave
      .filter((c) => c.wave === nextWave)
      .map((c) => c.user);

    const waveCounts = candidatesWithWave.map((c) => c.wave).join(", ");
    console.log(
      `  Wave ${nextWave}: ${waveUsers.length} users ` +
      `(total candidates by wave: ${waveCounts})`,
    );

    if (waveUsers.length === 0) {
      console.log(
        `  ⚠️ No users for wave ${nextWave}, ` +
        "skipping to next wave immediately",
      );

      await db
        .collection(`${stationPath}/replacements/automatic/replacementRequests`)
        .doc(requestId)
        .update({currentWave: nextWave});

      const updatedRequestDoc = await db
        .collection(`${stationPath}/replacements/automatic/replacementRequests`)
        .doc(requestId)
        .get();

      if (updatedRequestDoc.exists) {
        const updatedRequest =
          updatedRequestDoc.data() as ReplacementRequestDataV2;
        await sendNextWaveV2(requestId, updatedRequest, stationPath);
      }
      return;
    }

    const newNotifiedUserIds = [
      ...notifiedUserIds,
      ...waveUsers.map((u) => u.id),
    ];

    await db
      .collection(`${stationPath}/replacements/automatic/replacementRequests`)
      .doc(requestId)
      .update({
        currentWave: nextWave,
        notifiedUserIds: newNotifiedUserIds,
        lastWaveSentAt: Timestamp.now(),
        [`waveUserIds.${nextWave}`]: waveUsers.map((u) => u.id),
      });

    // requesterName résolu par sendReplacementNotificationsV2 via decryptPII
    const notificationData = {
      type: "replacement_request",
      requestId: requestId,
      requesterId: request.requesterId,
      planningId: request.planningId,
      startTime: request.startTime,
      endTime: request.endTime,
      station: request.station,
      team: request.team,
      targetUserIds: waveUsers.map((u) => u.id),
      wave: nextWave,
      createdAt: Timestamp.now(),
      processed: false,
    };

    await db
      .collection(`${stationPath}/notificationTriggers`)
      .add(notificationData);

    console.log(
      `  ✅ Wave ${nextWave} trigger created for ` +
      `${waveUsers.length} users`,
    );
  } catch (error) {
    console.error(
      `  💥 [V2] Error sending wave for request ${requestId}:`,
      error,
    );
  }
}

/**
 * V2 : Proposition de remplacement manuel
 */
export const handleManualReplacementAcceptanceV2 = onDocumentCreated(
  {region: "europe-west1", document: "sdis/{sdisId}/stations/{stationId}/replacements/automatic/manualReplacementProposals/{proposalId}"},
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }

    const proposalId = event.params.proposalId;
    console.log(
      `📝 [V2] Manual replacement proposal created: ${proposalId}`,
    );
  },
);

/**
 * V2 : Acceptation de remplacement manuel
 */
export const onManualReplacementAcceptedV2 = onDocumentCreated(
  {region: "europe-west1", document: "sdis/{sdisId}/stations/{stationId}/replacements/automatic/replacementAcceptances/{acceptanceId}"},
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }

    const acceptance = snapshot.data();
    const proposalId = acceptance.proposalId as string;
    const stationPath = `sdis/${event.params.sdisId}/stations/${event.params.stationId}`;

    console.log(
      "✅ [V2] Processing manual replacement acceptance for proposal: " +
      `${proposalId}`,
    );

    try {
      const db = getFirestore();

      // Récupérer la proposition
      const proposalDoc = await db
        .collection(`${stationPath}/replacements/automatic/manualReplacementProposals`)
        .doc(proposalId)
        .get();

      if (!proposalDoc.exists) {
        console.error(
          `❌ Proposal not found: ${proposalId}`,
        );
        return;
      }

      const proposal = proposalDoc.data();
      if (!proposal) {
        console.error(
          `❌ Proposal data is empty: ${proposalId}`,
        );
        return;
      }

      // Mettre à jour le statut de la proposition
      await proposalDoc.ref.update({
        status: "accepted",
        acceptedAt: Timestamp.now(),
      });

      // Créer le subshift
      const subshiftsCollection = `${stationPath}/replacements/all/subshifts`;
      const subshiftId = db.collection(subshiftsCollection).doc().id;
      await db.collection(subshiftsCollection).doc(subshiftId).set({
        id: subshiftId,
        replacedId: proposal.replacedId,
        replacerId: proposal.replacerId,
        start: proposal.startTime,
        end: proposal.endTime,
        planningId: proposal.planningId,
      });

      console.log(
        `  ✓ Subshift created: ${subshiftId}`,
      );

      // Récupérer le planning pour trouver les chefs d'équipe
      const planningDoc = await db
        .collection(`${stationPath}/plannings`)
        .doc(proposal.planningId as string)
        .get();

      let chiefIds: string[] = [];

      if (planningDoc.exists) {
        const planningData = planningDoc.data();
        const planningTeam = planningData?.team as string | undefined;

        if (planningTeam) {
          const usersSnapshot = await db
            .collection(`${stationPath}/users`)
            .where("team", "==", planningTeam)
            .get();

          usersSnapshot.docs.forEach((doc) => {
            const userData = doc.data();
            if (
              userData.status === "chief" ||
              userData.status === "leader"
            ) {
              chiefIds.push(doc.id);
            }
          });

          console.log(
            `  ✓ Found ${chiefIds.length} chief(s) for team ` +
            `${planningTeam}`,
          );
        }
      }

      // Envoyer notification au remplacé — replacerName résolu par CF handler via decryptPII
      await db.collection(`${stationPath}/notificationTriggers`).add({
        type: "replacement_found",
        requestId: proposalId,
        targetUserIds: [proposal.replacedId],
        replacerId: proposal.replacerId,
        startTime: proposal.startTime,
        endTime: proposal.endTime,
        createdAt: Timestamp.now(),
        processed: false,
      });

      console.log(
        "  ✓ Notification sent to replaced agent: " +
        `${proposal.replacedId}`,
      );

      // Envoyer notifications aux chefs d'équipe — noms résolus par CF handler
      if (chiefIds.length > 0) {
        chiefIds = chiefIds.filter(
          (id) => id !== proposal.replacedId,
        );

        if (chiefIds.length > 0) {
          await db.collection(`${stationPath}/notificationTriggers`).add({
            type: "replacement_assigned",
            requestId: proposalId,
            targetUserIds: chiefIds,
            replacedId: proposal.replacedId,
            replacerId: proposal.replacerId,
            startTime: proposal.startTime,
            endTime: proposal.endTime,
            createdAt: Timestamp.now(),
            processed: false,
          });

          console.log(
            `  ✓ Notifications sent to ${chiefIds.length} chief(s)`,
          );
        }
      }

      console.log(
        "✅ [V2] Manual replacement acceptance processed successfully",
      );
    } catch (error) {
      console.error(
        "❌ [V2] Error processing manual replacement acceptance:",
        error,
      );
    }
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// handleAgentSuspension
// Déclenché à la création d'un suspensionTrigger (depuis AgentSuspensionService).
// Actions :
//   1. Retire l'agent des plannings futurs (>= suspensionStartDate)
//   2. Annule ses replacementRequests pending
//   3. Annule ses shiftExchangeRequests open
//   4. Marque le trigger comme traité
// ─────────────────────────────────────────────────────────────────────────────
export const handleAgentSuspension = onDocumentCreated(
  {region: "europe-west1", document: "sdis/{sdisId}/stations/{stationId}/replacements/automatic/suspensionTriggers/{triggerId}"},
  async (event) => {
    const trigger = event.data?.data();
    if (!trigger || trigger.processed) return;

    const {sdisId, stationId} = event.params;
    const {agentId, suspensionStartDate} = trigger;

    if (!agentId || !suspensionStartDate) {
      console.error("❌ [handleAgentSuspension] Missing agentId or suspensionStartDate");
      return;
    }

    const db = getFirestore();
    const stationPath = `sdis/${sdisId}/stations/${stationId}`;
    const suspensionDate: Date = suspensionStartDate.toDate();

    console.log(
      `🔄 [handleAgentSuspension] Processing suspension for agent ${agentId} from ${suspensionDate.toISOString()}`,
    );

    try {
      // 1. Retirer l'agent de tous les plannings de la station
      //    Critère : l'entrée agent dans planning.agents[] a un start >= suspensionDate
      const planningsSnap = await db
        .collection(`${stationPath}/plannings`)
        .get();

      const planningBatch = db.batch();
      let planningUpdates = 0;
      for (const planningDoc of planningsSnap.docs) {
        const planning = planningDoc.data();
        const agents: unknown[] = planning.agents ?? [];
        const filteredAgents = (agents as Array<{agentId: string; start: Timestamp}>).filter(
          (a) => a.agentId !== agentId || a.start.toDate() < suspensionDate,
        );
        if (filteredAgents.length !== agents.length) {
          planningBatch.update(planningDoc.ref, {agents: filteredAgents});
          planningUpdates++;
        }
      }
      await planningBatch.commit();
      console.log(`✅ [handleAgentSuspension] Updated ${planningUpdates} plannings`);

      // 2. Annuler les AgentQuery pending créées par l'agent
      const agentQueriesSnap = await db
        .collection(`${stationPath}/replacements/queries/agentQueries`)
        .where("createdById", "==", agentId)
        .where("status", "==", "pending")
        .get();

      const agentQueryBatch = db.batch();
      for (const doc of agentQueriesSnap.docs) {
        agentQueryBatch.update(doc.ref, {
          status: "cancelled",
          cancelledAt: Timestamp.now(),
          cancelReason: "agent_suspended",
        });
      }
      await agentQueryBatch.commit();
      console.log(
        `✅ [handleAgentSuspension] Cancelled ${agentQueriesSnap.size} agentQueries`,
      );

      // 3. Annuler les shiftExchangeRequests open de l'agent
      const exchangesSnap = await db
        .collection(`${stationPath}/replacements/exchanges/requests`)
        .where("initiatorId", "==", agentId)
        .where("status", "==", "open")
        .get();

      const exchangeBatch = db.batch();
      for (const doc of exchangesSnap.docs) {
        exchangeBatch.update(doc.ref, {
          status: "cancelled",
          cancelledAt: Timestamp.now(),
          cancelReason: "agent_suspended",
        });
      }
      await exchangeBatch.commit();
      console.log(
        `✅ [handleAgentSuspension] Cancelled ${exchangesSnap.size} shiftExchangeRequests`,
      );

      // 4. Marquer le trigger comme traité
      await event.data!.ref.update({
        processed: true,
        processedAt: Timestamp.now(),
      });

      console.log("✅ [handleAgentSuspension] Suspension processed successfully");
    } catch (error) {
      console.error("❌ [handleAgentSuspension] Error:", error);
    }
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// handleAgentReinstatement
// Déclenché à la création d'un reinstatementTrigger (depuis AgentSuspensionService).
// Actions :
//   1. Ajoute l'agent aux plannings futurs de son équipe (>= reinstatementDate)
//      si non déjà présent
//   2. Marque le trigger comme traité
// ─────────────────────────────────────────────────────────────────────────────
export const handleAgentReinstatement = onDocumentCreated(
  {
    region: "europe-west1",
    document: "sdis/{sdisId}/stations/{stationId}/replacements/automatic/reinstatementTriggers/{triggerId}",
  },
  async (event) => {
    const trigger = event.data?.data();
    if (!trigger || trigger.processed) return;

    const {sdisId, stationId} = event.params;
    const {agentId, teamId, reinstatementDate} = trigger;

    if (!agentId || !teamId) {
      console.error("❌ [handleAgentReinstatement] Missing agentId or teamId");
      return;
    }

    const db = getFirestore();
    const stationPath = `sdis/${sdisId}/stations/${stationId}`;
    const now: Date = reinstatementDate.toDate();

    console.log(
      `🔄 [handleAgentReinstatement] Processing reinstatement for agent ${agentId} in team ${teamId}`,
    );

    try {
      const planningsSnap = await db
        .collection(`${stationPath}/plannings`)
        .where("team", "==", teamId)
        .where("startTime", ">=", Timestamp.fromDate(now))
        .get();

      const batch = db.batch();
      let planningUpdates = 0;

      for (const planningDoc of planningsSnap.docs) {
        const planning = planningDoc.data();
        const agents: Array<{agentId: string}> = planning.agents ?? [];

        if (agents.some((a) => a.agentId === agentId)) continue;

        // replacedAgentId omis — cohérent avec PlanningAgent.toJson() qui l'omet si null
        const newEntry: Record<string, unknown> = {
          agentId: agentId,
          start: planning.startTime,
          end: planning.endTime,
          levelId: "",
          isExchange: false,
          checkedByChief: false,
        };

        batch.update(planningDoc.ref, {
          agents: [...agents, newEntry],
        });
        planningUpdates++;
      }

      await batch.commit();
      console.log(`✅ [handleAgentReinstatement] Added agent to ${planningUpdates} plannings`);

      await event.data!.ref.update({
        processed: true,
        processedAt: Timestamp.now(),
        planningsUpdated: planningUpdates,
      });

      console.log("✅ [handleAgentReinstatement] Reinstatement processed successfully");
    } catch (error) {
      console.error("❌ [handleAgentReinstatement] Error:", error);
    }
  },
);
