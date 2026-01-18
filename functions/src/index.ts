import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";

initializeApp();

/**
 * Cloud Function qui écoute les nouveaux documents dans notificationTriggers
 * et envoie les notifications FCM correspondantes
 */
export const sendReplacementNotifications = onDocumentCreated(
  "notificationTriggers/{triggerId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }

    const trigger = snapshot.data();

    // Vérifier si déjà traité
    if (trigger.processed) {
      console.log("Trigger already processed:", event.params.triggerId);
      return;
    }

    try {
      const type = trigger.type;
      const targetUserIds = trigger.targetUserIds as string[];

      console.log(
        `📤 Processing ${type} notification for ` +
        `${targetUserIds.length} users`,
      );

      // Récupérer les tokens FCM des utilisateurs cibles
      const tokens: string[] = [];
      const db = getFirestore();
      for (const userId of targetUserIds) {
        const userDoc = await db
          .collection("users")
          .doc(userId)
          .get();

        const fcmToken = userDoc.data()?.fcmToken;
        if (fcmToken) {
          tokens.push(fcmToken);
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

      // Construire le message selon le type
      let notification: { title: string; body: string };
      let data: { [key: string]: string };

      switch (type) {
      case "replacement_request":
        notification = {
          title: "🔔 Recherche de remplaçant",
          body:
              `${trigger.requesterName} recherche un ` +
              "remplaçant du " +
              `${formatDate(trigger.startTime.toDate())} au ` +
              `${formatDate(trigger.endTime.toDate())}`,
        };
        data = {
          type: "replacement_request",
          requestId: trigger.requestId,
          requesterId: trigger.requesterId,
          planningId: trigger.planningId,
          station: trigger.station || "",
          team: trigger.team || "",
        };
        console.log(
          "  📨 Replacement request notification: " +
            `${trigger.requesterName}`,
        );
        break;

      case "availability_request":
        notification = {
          title: "🔍 Recherche d'agent disponible",
          body:
              `${trigger.requesterName} recherche un ` +
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
        console.log(
          "  📨 Availability request notification: " +
            `${trigger.requesterName}`,
        );
        break;

      case "replacement_found":
        notification = {
          title: "✅ Remplaçant trouvé !",
          body:
              `${trigger.replacerName} a accepté de ` +
              "vous remplacer",
        };
        data = {
          type: "replacement_found",
          requestId: trigger.requestId,
          replacerName: trigger.replacerName,
        };
        console.log(
          "  📨 Replacement found notification: " +
            `${trigger.replacerName}`,
        );
        break;

      case "replacement_assigned":
        notification = {
          title: "📋 Remplacement assigné",
          body:
              `${trigger.replacedName} sera remplacé par ` +
              `${trigger.replacerName} du ` +
              `${formatDate(trigger.startTime.toDate())} au ` +
              `${formatDate(trigger.endTime.toDate())}`,
        };
        data = {
          type: "replacement_assigned",
          requestId: trigger.requestId,
          replacedName: trigger.replacedName,
          replacerName: trigger.replacerName,
        };
        console.log(
          "  📨 Replacement assigned notification: " +
            `${trigger.replacedName} → ${trigger.replacerName}`,
        );
        break;

      case "replacement_completed":
        notification = {
          title: "✅ Remplacement complété !",
          body:
              `Votre remplacement a été trouvé : ${trigger.replacerNames}`,
        };
        data = {
          type: "replacement_completed",
          requestId: trigger.requestId,
          replacerNames: trigger.replacerNames,
        };
        console.log(
          "  📨 Replacement completed notification for requester",
        );
        break;

      case "replacement_completed_chief":
        notification = {
          title: "✅ Remplacement complété",
          body:
              `${trigger.requesterName} a trouvé son remplacement : ` +
              `${trigger.replacerNames}`,
        };
        data = {
          type: "replacement_completed_chief",
          requestId: trigger.requestId,
          requesterName: trigger.requesterName,
          replacerNames: trigger.replacerNames,
        };
        console.log(
          "  📨 Replacement completed notification for chief",
        );
        break;

      case "manual_replacement_proposal":
        notification = {
          title: "🔄 Proposition de remplacement",
          body:
              `${trigger.proposerName} propose que vous ` +
              `remplaciez ${trigger.replacedName} du ` +
              `${formatDate(trigger.startTime.toDate())} au ` +
              `${formatDate(trigger.endTime.toDate())}`,
        };
        data = {
          type: "manual_replacement_proposal",
          proposalId: trigger.proposalId,
          proposerId: trigger.proposerId,
          proposerName: trigger.proposerName,
          replacedId: trigger.replacedId,
          replacedName: trigger.replacedName,
          planningId: trigger.planningId,
        };
        console.log(
          "  📨 Manual replacement proposal notification: " +
            `${trigger.proposerName} → ${trigger.replacedName}`,
        );
        break;

      // Notifications pour les échanges d'astreintes
      case "shift_exchange_proposal_received":
        notification = {
          title: trigger.title || "Nouvelle proposition d'échange",
          body: trigger.body || "Une nouvelle proposition d'échange a été reçue",
        };
        data = {
          type: "shift_exchange_proposal_received",
          requestId: trigger.data?.requestId || "",
          proposalId: trigger.data?.proposalId || "",
          proposerName: trigger.data?.proposerName || "",
        };
        console.log(
          "  📨 Shift exchange proposal received notification",
        );
        break;

      case "shift_exchange_validation_required":
        notification = {
          title: trigger.title || "Validation d'échange requise",
          body: trigger.body || "Un échange d'astreinte nécessite votre validation",
        };
        data = {
          type: "shift_exchange_validation_required",
          requestId: trigger.data?.requestId || "",
          proposalId: trigger.data?.proposalId || "",
          initiatorName: trigger.data?.initiatorName || "",
          proposerName: trigger.data?.proposerName || "",
        };
        console.log(
          "  📨 Shift exchange validation required notification",
        );
        break;

      case "shift_exchange_validated":
        notification = {
          title: trigger.title || "✅ Échange validé",
          body: trigger.body || "Votre échange d'astreinte a été validé",
        };
        data = {
          type: "shift_exchange_validated",
          requestId: trigger.data?.requestId || "",
          proposalId: trigger.data?.proposalId || "",
        };
        console.log(
          "  📨 Shift exchange validated notification",
        );
        break;

      case "shift_exchange_rejected":
        notification = {
          title: trigger.title || "❌ Proposition refusée",
          body: trigger.body || "Une proposition d'échange a été refusée",
        };
        data = {
          type: "shift_exchange_rejected",
          requestId: trigger.data?.requestId || "",
          proposalId: trigger.data?.proposalId || "",
          proposerName: trigger.data?.proposerName || "",
          leaderName: trigger.data?.leaderName || "",
          rejectionReason: trigger.data?.rejectionReason || "",
        };
        console.log(
          "  📨 Shift exchange rejected notification",
        );
        break;

      case "shift_exchange_proposer_selected":
        notification = {
          title: trigger.title || "🎯 Votre proposition sélectionnée",
          body: trigger.body || "Votre proposition d'échange a été sélectionnée",
        };
        data = {
          type: "shift_exchange_proposer_selected",
          requestId: trigger.data?.requestId || "",
          proposalId: trigger.data?.proposalId || "",
          initiatorName: trigger.data?.initiatorName || "",
        };
        console.log(
          "  📨 Shift exchange proposer selected notification",
        );
        break;

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
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
          ttl: 86400, // 24 heures (en secondes)
          collapseKey: `replacement_${type}`,
        },
        apns: {
          headers: {
            "apns-priority": "10", // Priorité immédiate
            "apns-expiration": String(Math.floor(Date.now() / 1000) + 86400),
          },
          payload: {
            aps: {
              "alert": {
                title: notification.title,
                body: notification.body,
              },
              "sound": "default",
              "badge": 1,
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

        // Nettoyer les tokens invalides
        const batch = db.batch();
        let invalidTokensCount = 0;

        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            console.error(
              `  Error for token ${idx}:`,
              resp.error,
            );

            // Si le token est invalide/non enregistré,
            // le supprimer de Firestore
            const errorCode = resp.error?.code;
            if (
              errorCode === "messaging/invalid-registration-token" ||
              errorCode === "messaging/registration-token-not-registered"
            ) {
              const userId = targetUserIds[idx];

              console.log(
                `  🧹 Cleaning invalid token for user ${userId}`,
              );

              // Supprimer le token du document utilisateur
              batch.update(
                db.collection("users").doc(userId),
                {fcmToken: null},
              );
              invalidTokensCount++;
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

      // Marquer comme traité
      await snapshot.ref.update({
        processed: true,
        processedAt: Timestamp.now(),
        successCount: response.successCount,
        failureCount: response.failureCount,
      });
    } catch (error) {
      console.error("💥 Error sending notifications:", error);

      // Marquer comme échoué
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

/**
 * OPTIONNEL : Cloud Function de nettoyage pour les triggers traités
 * Supprime automatiquement les triggers traités de plus de 7 jours
 */
export const cleanupProcessedTriggers = onSchedule(
  "every 24 hours",
  async () => {
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

    const db = getFirestore();
    const snapshot = await db
      .collection("notificationTriggers")
      .where("processed", "==", true)
      .where("processedAt", "<", Timestamp.fromDate(sevenDaysAgo))
      .get();

    const batch = db.batch();
    snapshot.docs.forEach((doc) => {
      batch.delete(doc.ref);
    });

    await batch.commit();
    console.log(
      `🧹 Cleaned up ${snapshot.size} old notification triggers`,
    );
  },
);

/**
 * OPTIONNEL : Cloud Function pour expirer les demandes en attente
 * Marque comme expired les demandes de plus de 24h sans réponse
 */
export const expireOldRequests = onSchedule(
  "every 1 hours",
  async () => {
    const oneDayAgo = new Date();
    oneDayAgo.setHours(oneDayAgo.getHours() - 24);

    const db = getFirestore();
    const snapshot = await db
      .collection("replacementRequests")
      .where("status", "==", "pending")
      .where("createdAt", "<", Timestamp.fromDate(oneDayAgo))
      .get();

    const batch = db.batch();
    snapshot.docs.forEach((doc) => {
      batch.update(doc.ref, {
        status: "expired",
        expiredAt: Timestamp.now(),
      });
    });

    await batch.commit();
    console.log(
      `⏰ Expired ${snapshot.size} old replacement requests`,
    );
  },
);

/**
 * Cloud Function qui écoute les changements sur les subshifts
 * pour détecter quand une demande de remplacement est complétée
 */
export const checkReplacementCompletion = onDocumentCreated(
  "subshifts/{subshiftId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }

    const subshift = snapshot.data();
    const planningId = subshift.planningId;
    const replacedId = subshift.replacedId;

    console.log(
      "🔍 Checking if replacement is complete for " +
      `user ${replacedId} in planning ${planningId}`,
    );

    try {
      const db = getFirestore();

      // Trouver toutes les demandes de remplacement pending
      // pour cet utilisateur
      const requestsSnapshot = await db
        .collection("replacementRequests")
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

        // Récupérer tous les subshifts pour cette demande
        const subshiftsSnapshot = await db
          .collection("subshifts")
          .where("planningId", "==", planningId)
          .where("replacedId", "==", replacedId)
          .get();

        // Calculer la couverture totale
        const intervals: Array<{ start: Date; end: Date }> = [];
        subshiftsSnapshot.docs.forEach((doc) => {
          const data = doc.data();
          intervals.push({
            start: data.start.toDate(),
            end: data.end.toDate(),
          });
        });

        // Vérifier si la demande est complètement couverte
        const isFullyCovered = checkIfFullyCovered(
          requestStart,
          requestEnd,
          intervals,
        );

        if (isFullyCovered) {
          console.log(
            `  ✅ Request ${requestDoc.id} is fully covered!`,
          );

          // Marquer la demande comme acceptée
          await requestDoc.ref.update({
            status: "accepted",
            acceptedAt: Timestamp.now(),
          });

          // Récupérer les informations pour les notifications
          const requesterDoc = await db
            .collection("users")
            .doc(replacedId)
            .get();

          if (!requesterDoc.exists) continue;

          const requester = requesterDoc.data();
          const requesterName =
            `${requester?.firstName} ${requester?.lastName}`;

          // Trouver le chef de garde de l'astreinte (via l'équipe du planning)
          const planningForChiefDoc = await db
            .collection("plannings")
            .doc(planningId)
            .get();

          let chiefId = replacedId; // Par défaut, notifier le demandeur
          if (planningForChiefDoc.exists) {
            const planningData = planningForChiefDoc.data();
            const planningTeam = planningData?.team;
            const planningStation = planningData?.station;

            if (planningTeam && planningStation) {
              // Chercher le chef de garde : status 'chief' ou 'leader'
              // dans cette équipe
              const chiefsSnapshot = await db
                .collection("users")
                .where("station", "==", planningStation)
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

          // Récupérer les noms des remplaçants
          const replacerIds = new Set(
            intervals.map((interval) => {
              // Trouver le subshift correspondant à cet interval
              const matchingSubshift = subshiftsSnapshot.docs.find((doc) => {
                const data = doc.data();
                const start = data.start.toDate();
                const end = data.end.toDate();
                return start.getTime() === interval.start.getTime() &&
                  end.getTime() === interval.end.getTime();
              });
              return matchingSubshift?.data().replacerId;
            }).filter(Boolean),
          );

          const replacerNames: string[] = [];
          for (const replacerId of replacerIds) {
            const replacerDoc = await db
              .collection("users")
              .doc(replacerId)
              .get();
            if (replacerDoc.exists) {
              const replacer = replacerDoc.data();
              replacerNames.push(
                `${replacer?.firstName} ${replacer?.lastName}`,
              );
            }
          }

          const replacerNameStr = replacerNames.join(", ");

          // Créer les notifications de confirmation
          // 1. Notification au demandeur
          await db.collection("notificationTriggers").add({
            type: "replacement_completed",
            requestId: requestDoc.id,
            targetUserIds: [replacedId],
            replacerNames: replacerNameStr,
            startTime: request.startTime,
            endTime: request.endTime,
            createdAt: Timestamp.now(),
            processed: false,
          });

          // 2. Notification au chef d'équipe
          if (chiefId !== replacedId) {
            await db.collection("notificationTriggers").add({
              type: "replacement_completed_chief",
              requestId: requestDoc.id,
              targetUserIds: [chiefId],
              requesterName: requesterName,
              replacerNames: replacerNameStr,
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
      console.error("💥 Error checking replacement completion:", error);
    }
  },
);

/**
 * Vérifie si une période est complètement couverte par des intervalles
 * @param {Date} targetStart - Début de la période cible
 * @param {Date} targetEnd - Fin de la période cible
 * @param {Array} intervals - Intervalles de couverture
 * @return {boolean} True si complètement couvert
 */
function checkIfFullyCovered(
  targetStart: Date,
  targetEnd: Date,
  intervals: Array<{ start: Date; end: Date }>,
): boolean {
  if (intervals.length === 0) return false;

  // Trier les intervalles par date de début
  const sorted = intervals
    .map((i) => ({
      "start": i.start.getTime(),
      "end": i.end.getTime(),
    }))
    .sort((a, b) => a.start - b.start);

  const targetStartTime = targetStart.getTime();
  const targetEndTime = targetEnd.getTime();

  // Fusionner les intervalles qui se chevauchent
  const merged: Array<{ start: number; end: number }> = [];
  let current = sorted[0];

  for (let i = 1; i < sorted.length; i++) {
    const next = sorted[i];
    if (next.start <= current.end) {
      // Chevauchement ou contigus: fusionner
      current = {
        start: Math.min(current.start, next.start),
        end: Math.max(current.end, next.end),
      };
    } else {
      // Pas de chevauchement: ajouter current et passer au suivant
      merged.push(current);
      current = next;
    }
  }
  merged.push(current);

  // Vérifier si la période cible est couverte (avec tolérance d'1 minute)
  const tolerance = 60 * 1000; // 1 minute en millisecondes
  for (const interval of merged) {
    if (interval.start - tolerance <= targetStartTime &&
      interval.end + tolerance >= targetEndTime) {
      return true;
    }
  }

  return false;
}

/**
 * Cloud Function pour envoyer une notification de test
 * Permet aux admins de tester la réception de notifications push
 */
export const sendTestNotification = onDocumentCreated(
  "testNotifications/{testId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }

    const test = snapshot.data();

    try {
      const targetUserId = test.targetUserId as string;
      const adminId = test.adminId as string;

      console.log(
        `🧪 Sending test notification to user ${targetUserId} ` +
        `(requested by ${adminId})`,
      );

      // Récupérer le token FCM de l'utilisateur cible
      const db = getFirestore();
      const userDoc = await db.collection("users").doc(targetUserId).get();

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

      // Récupérer les infos de l'admin
      const adminDoc = await db.collection("users").doc(adminId).get();
      const adminName = adminDoc.exists ?
        `${adminDoc.data()?.firstName} ${adminDoc.data()?.lastName}` :
        "Admin";

      // Construire le message de test
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

      // Envoyer la notification
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
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
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
              "badge": 1,
              "mutable-content": 1,
              "content-available": 1,
            },
          },
        },
      };

      console.log("  🚀 Sending test notification...");
      const response = await messaging.send(message);

      console.log(`✅ Test notification sent successfully: ${response}`);

      // Marquer comme traité
      await snapshot.ref.update({
        processed: true,
        processedAt: Timestamp.now(),
        success: true,
        messageId: response,
      });
    } catch (error) {
      console.error("💥 Error sending test notification:", error);

      // Gérer les tokens invalides
      const errorCode = (error as {code?: string})?.code;
      if (
        errorCode === "messaging/invalid-registration-token" ||
        errorCode === "messaging/registration-token-not-registered"
      ) {
        console.log(`  🧹 Cleaning invalid token for user ${test.targetUserId}`);
        const db = getFirestore();
        await db.collection("users").doc(test.targetUserId).update({
          fcmToken: null,
        });
      }

      // Marquer comme échoué
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
 * Cloud Function pour traiter immédiatement les vagues vides
 * S'exécute lorsqu'une vague est vide et qu'il faut passer à la suivante
 */
export const processEmptyWave = onDocumentCreated(
  "waveSkipTriggers/{triggerId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }

    const trigger = snapshot.data();

    // Vérifier si déjà traité
    if (trigger.processed) {
      console.log("Trigger already processed:", event.params.triggerId);
      return;
    }

    try {
      const requestId = trigger.requestId as string;
      const skippedWave = trigger.skippedWave as number;

      console.log(
        `🌊 Processing empty wave skip for request ${requestId} ` +
        `(skipped wave: ${skippedWave})`,
      );

      const db = getFirestore();

      // Récupérer la demande
      const requestDoc = await db
        .collection("replacementRequests")
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

      const request = requestDoc.data() as ReplacementRequestData;

      // Envoyer immédiatement la vague suivante
      await sendNextWave(requestId, request);

      // Marquer comme traité
      await snapshot.ref.update({
        processed: true,
        processedAt: Timestamp.now(),
      });

      console.log(
        `  ✅ Empty wave processed, next wave sent for request ${requestId}`,
      );
    } catch (error) {
      console.error("💥 Error processing empty wave:", error);

      // Marquer comme échoué
      await snapshot.ref.update({
        processed: true,
        processedAt: Timestamp.now(),
        error: String(error),
      });
    }
  },
);

/**
 * Cloud Function pour traiter les vagues de notifications progressives
 * S'exécute toutes les 5 minutes pour vérifier les demandes en attente
 * et envoyer la vague suivante si le délai est écoulé
 */
export const processNotificationWaves = onSchedule(
  "every 5 minutes",
  async () => {
    const db = getFirestore();
    console.log("🌊 Processing notification waves...");

    try {
      // Récupérer toutes les demandes en attente
      const pendingRequests = await db
        .collection("replacementRequests")
        .where("status", "==", "pending")
        .get();

      console.log(
        `Found ${pendingRequests.size} pending requests to check`,
      );

      for (const requestDoc of pendingRequests.docs) {
        const request = requestDoc.data();
        const requestId = requestDoc.id;

        // Vérifier si la demande a été créée ou
        // si la dernière vague a été envoyée
        const lastWaveSentAt = request.lastWaveSentAt?.toDate();
        if (!lastWaveSentAt) {
          // Pas encore de vague envoyée,
          // skip (sera géré par _triggerNotifications)
          continue;
        }

        // Récupérer le délai configuré pour la station
        const stationDoc = await db
          .collection("stations")
          .doc(request.station)
          .get();

        const delayMinutes = stationDoc.exists ?
          (stationDoc.data()?.notificationWaveDelayMinutes || 30) :
          30;

        // Vérifier si le délai est écoulé
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

        // Temps d'envoyer la vague suivante
        console.log(
          `  Request ${requestId}: ` +
          `sending next wave (current: ${request.currentWave})`,
        );

        await sendNextWave(requestId, request as ReplacementRequestData);
      }
    } catch (error) {
      console.error("💥 Error processing notification waves:", error);
    }
  },
);

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

interface ReplacementRequestData {
  requesterId: string;
  station: string;
  planningId: string;
  startTime: Timestamp;
  endTime: Timestamp;
  team: string;
  currentWave?: number;
  notifiedUserIds?: string[];
}

/**
 * Envoie la vague suivante de notifications
 * @param {string} requestId - ID de la demande
 * @param {ReplacementRequestData} request - Données de la demande
 */
async function sendNextWave(
  requestId: string,
  request: ReplacementRequestData,
) {
  const db = getFirestore();

  try {
    // Récupérer le demandeur pour connaître ses compétences
    const requesterDoc = await db
      .collection("users")
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
      .collection("users")
      .where("station", "==", request.station)
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

    // Récupérer le planning pour connaître les agents en astreinte
    const planningDoc = await db
      .collection("plannings")
      .doc(request.planningId)
      .get();

    const agentsInPlanning: string[] = [];
    if (planningDoc.exists) {
      const planningData = planningDoc.data();
      agentsInPlanning.push(...(planningData?.agentsId || []));
    }

    console.log(
      `  Planning ${request.planningId} has ${agentsInPlanning.length} ` +
      "agents on duty",
    );

    // Exclure les utilisateurs déjà notifiés, le demandeur,
    // ET les agents en astreinte de la même équipe
    const notifiedUserIds = request.notifiedUserIds || [];
    const candidateUsers = allUsers.filter(
      (u) =>
        u.id !== request.requesterId &&
        !notifiedUserIds.includes(u.id) &&
        // Exclure les agents en astreinte qui sont de la même équipe
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

    // Déterminer la vague suivante
    const nextWave = (request.currentWave || 0) + 1;

    // Limite max de vagues
    if (nextWave > 5) {
      console.log("  ✅ All 5 waves have been processed");
      return;
    }

    // Récupérer l'équipe du planning
    const planningData = planningDoc.data();
    const planningTeam = planningData?.team || "";

    // Calculer les poids de rareté des compétences
    const skillRarityWeights = calculateSkillRarityWeights(
      allUsers.map((u) => ({
        id: u.id,
        team: u.team,
        skills: u.skills,
      })),
      requesterSkills,
    );

    console.log(
      "  Skill rarity weights:",
      JSON.stringify(skillRarityWeights),
    );

    // Calculer la vague de chaque candidat avec le nouveau système
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

    // Filtrer les candidats pour cette vague uniquement
    const waveUsers = candidatesWithWave
      .filter((c) => c.wave === nextWave)
      .map((c) => c.user);

    const waveCounts = candidatesWithWave.map((c) => c.wave).join(", ");
    console.log(
      `  Wave ${nextWave}: ${waveUsers.length} users ` +
      `(total candidates by wave: ${waveCounts})`,
    );

    if (waveUsers.length === 0) {
      // Aucun utilisateur pour cette vague, passer à la suivante IMMÉDIATEMENT
      console.log(
        `  ⚠️ No users for wave ${nextWave}, ` +
        "skipping to next wave immediately",
      );

      // Mettre à jour uniquement currentWave, SANS mettre à jour lastWaveSentAt
      // pour permettre de sauter immédiatement à la vague suivante
      await db.collection("replacementRequests").doc(requestId).update({
        currentWave: nextWave,
      });

      // Récupérer la demande mise à jour et appeler récursivement
      const updatedRequestDoc = await db
        .collection("replacementRequests")
        .doc(requestId)
        .get();

      if (updatedRequestDoc.exists) {
        const updatedRequest =
          updatedRequestDoc.data() as ReplacementRequestData;
        // Appel récursif pour traiter la vague suivante immédiatement
        await sendNextWave(requestId, updatedRequest);
      }
      return;
    }

    // Mettre à jour la demande
    const newNotifiedUserIds = [
      ...notifiedUserIds,
      ...waveUsers.map((u) => u.id),
    ];

    await db.collection("replacementRequests").doc(requestId).update({
      currentWave: nextWave,
      notifiedUserIds: newNotifiedUserIds,
      lastWaveSentAt: Timestamp.now(),
    });

    // Créer le trigger de notification
    const notificationData = {
      type: "replacement_request",
      requestId: requestId,
      requesterId: request.requesterId,
      requesterName: `${requester?.firstName} ${requester?.lastName}`,
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

    await db.collection("notificationTriggers").add(notificationData);

    console.log(
      `  ✅ Wave ${nextWave} trigger created for ` +
      `${waveUsers.length} users`,
    );
  } catch (error) {
    console.error(
      `  💥 Error sending wave for request ${requestId}:`,
      error,
    );
  }
}

/**
 * Cloud Function pour gérer l'acceptation d'une proposition
 * de remplacement manuel
 * Écoute les mises à jour dans manualReplacementProposals
 * où le statut passe à "accepted"
 */
export const handleManualReplacementAcceptance = onDocumentCreated(
  "manualReplacementProposals/{proposalId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }

    const proposalId = event.params.proposalId;

    // Attendre que le statut soit "accepted"
    // Cette fonction sera réexécutée par un trigger client
    // Pour l'instant, on ne fait rien au moment de la création
    console.log(
      `📝 Manual replacement proposal created: ${proposalId}`,
    );
  },
);

/**
 * Cloud Function pour créer le subshift et envoyer les notifications
 * quand une proposition de remplacement manuel est acceptée
 */
export const onManualReplacementAccepted = onDocumentCreated(
  "manualReplacementAcceptances/{acceptanceId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }

    const acceptance = snapshot.data();
    const proposalId = acceptance.proposalId as string;

    console.log(
      "✅ Processing manual replacement acceptance for proposal: " +
      `${proposalId}`,
    );

    try {
      const db = getFirestore();

      // Récupérer la proposition
      const proposalDoc = await db
        .collection("manualReplacementProposals")
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
      const subshiftId = db.collection("subshifts").doc().id;
      await db.collection("subshifts").doc(subshiftId).set({
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
        .collection("plannings")
        .doc(proposal.planningId as string)
        .get();

      let chiefIds: string[] = [];

      if (planningDoc.exists) {
        const planningData = planningDoc.data();
        const planningTeam = planningData?.team as string | undefined;
        const planningStation =
          planningData?.station as string | undefined;

        if (planningTeam && planningStation) {
          // Chercher les chefs de garde de cette équipe
          const usersSnapshot = await db
            .collection("users")
            .where("station", "==", planningStation)
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

      // Envoyer notification au remplacé
      await db.collection("notificationTriggers").add({
        type: "replacement_found",
        requestId: proposalId,
        targetUserIds: [proposal.replacedId],
        replacerName: proposal.replacerName,
        startTime: proposal.startTime,
        endTime: proposal.endTime,
        createdAt: Timestamp.now(),
        processed: false,
      });

      console.log(
        "  ✓ Notification sent to replaced agent: " +
        `${proposal.replacedName}`,
      );

      // Envoyer notifications aux chefs d'équipe
      if (chiefIds.length > 0) {
        // Exclure le remplacé s'il est chef
        chiefIds = chiefIds.filter(
          (id) => id !== proposal.replacedId,
        );

        if (chiefIds.length > 0) {
          await db.collection("notificationTriggers").add({
            type: "replacement_assigned",
            requestId: proposalId,
            targetUserIds: chiefIds,
            replacedName: proposal.replacedName,
            replacerName: proposal.replacerName,
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
        "✅ Manual replacement acceptance processed successfully",
      );
    } catch (error) {
      console.error(
        "❌ Error processing manual replacement acceptance:",
        error,
      );
    }
  },
);
